import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ppoling_core/contracts.dart';

/// 띄운 프로세스 하나의 실행 기록. 앱을 다시 켰을 때 소유권을 검증하는 데 쓴다(FR-11).
class ProcessRecord {
  const ProcessRecord({
    required this.item,
    required this.pid,
    required this.pgid,
    required this.command,
    required this.startedAt,
    required this.appRunId,
    this.jobName,
  });

  final ItemRef item;
  final int pid;
  final int pgid;
  final List<String> command;
  final DateTime startedAt;

  /// 띄운 앱 실행의 ID([RuntimeStore.appRunId]). 이번 실행에서 띄운 것인지 가린다.
  final String appRunId;

  /// Windows: 프로세스를 묶은 이름 붙은 Job. 앱을 다시 켠 뒤 이 이름으로 다시 붙는다. macOS 는 null.
  final String? jobName;
}

/// 실행 기록(마지막 전체 실행 결과, 떠 있는 프로세스)을 JSON 파일 하나에 저장한다.
///
/// 파일을 못 읽으면(없음·깨짐) 빈 기록으로 시작하고, 못 써도 실행은 멈추지 않는다. 쓰기 실패는 삼킨다.
class RuntimeStore {
  RuntimeStore(this._file);

  final Future<File> Function() _file;

  /// 이 앱 실행의 ID. 앱을 켤 때마다 바뀐다.
  final String appRunId = '$pid-${DateTime.now().microsecondsSinceEpoch}';

  Future<_Data>? _data;
  Future<void> _writing = Future.value();

  /// [projectId] 의 마지막 전체 실행 결과. 없으면 null.
  Future<RunSummary?> lastRun(String projectId) async => (await _load()).lastRuns[projectId];

  Future<void> saveRun(RunSummary summary) => _change((d) => d.lastRuns[summary.projectId] = summary);

  /// 저장된 프로세스 기록. 앱을 다시 켜기 전에 띄운 것도 들어 있다.
  Future<List<ProcessRecord>> processes() async => [...(await _load()).processes.values];

  Future<void> putProcess(ProcessRecord record) => _change((d) => d.processes[record.item] = record);

  Future<void> removeProcess(ItemRef item) => _change((d) => d.processes.remove(item));

  Future<_Data> _load() => _data ??= () async {
        try {
          return _Data.fromJson(jsonDecode(await (await _file()).readAsString()) as Map<String, dynamic>);
        } catch (_) {
          return _Data({}, {});
        }
      }();

  /// 메모리 기록을 바로 바꾸고, 파일 쓰기는 앞의 쓰기 뒤에 잇는다(쓰기끼리 섞이지 않게).
  Future<void> _change(void Function(_Data) change) async {
    final data = await _load();
    change(data);
    final json = jsonEncode(data.toJson());
    return _writing = _writing.then((_) async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        // 쓰다가 앱이 꺼져도 이전 기록이 깨지지 않게 임시 파일에 다 쓴 뒤 바꿔 끼운다.
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(file.path);
      } catch (_) {}
    });
  }
}

class _Data {
  _Data(this.lastRuns, this.processes);

  final Map<String, RunSummary> lastRuns;
  final Map<ItemRef, ProcessRecord> processes;

  factory _Data.fromJson(Map<String, dynamic> j) => _Data(
        {
          for (final s in (j['lastRuns'] as List? ?? const []).cast<Map<String, dynamic>>())
            s['projectId'] as String: _summaryFromJson(s),
        },
        {
          for (final p in (j['processes'] as List? ?? const []).cast<Map<String, dynamic>>())
            _itemFromJson(p): ProcessRecord(
              item: _itemFromJson(p),
              pid: p['pid'] as int,
              pgid: p['pgid'] as int,
              command: (p['command'] as List).cast<String>(),
              startedAt: DateTime.parse(p['startedAt'] as String),
              appRunId: p['appRunId'] as String,
              jobName: p['jobName'] as String?,
            ),
        },
      );

  Map<String, dynamic> toJson() => {
        'lastRuns': [for (final s in lastRuns.values) _summaryToJson(s)],
        'processes': [
          for (final p in processes.values)
            {
              ..._itemToJson(p.item),
              'pid': p.pid,
              'pgid': p.pgid,
              'command': p.command,
              'startedAt': p.startedAt.toIso8601String(),
              'appRunId': p.appRunId,
              if (p.jobName != null) 'jobName': p.jobName,
            },
        ],
      };
}

Map<String, dynamic> _itemToJson(ItemRef item) => {'projectId': item.projectId, 'serviceId': item.serviceId};

ItemRef _itemFromJson(Map<String, dynamic> j) =>
    ItemRef(projectId: j['projectId'] as String, serviceId: j['serviceId'] as String);

Map<String, dynamic> _summaryToJson(RunSummary s) => {
      'projectId': s.projectId,
      'startedAt': s.startedAt.toIso8601String(),
      'finishedAt': s.finishedAt.toIso8601String(),
      'items': [
        for (final r in s.items)
          {
            ..._itemToJson(r.item),
            'outcome': r.outcome.name,
            if (r.reason != null) 'reason': r.reason,
            if (r.exitCode != null) 'exitCode': r.exitCode,
            if (r.forced) 'forced': true,
          },
      ],
    };

RunSummary _summaryFromJson(Map<String, dynamic> j) => RunSummary(
      projectId: j['projectId'] as String,
      startedAt: DateTime.parse(j['startedAt'] as String),
      finishedAt: DateTime.parse(j['finishedAt'] as String),
      items: [
        for (final r in (j['items'] as List).cast<Map<String, dynamic>>())
          ItemResult(
            item: _itemFromJson(r),
            outcome: ItemOutcome.values.byName(r['outcome'] as String),
            reason: r['reason'] as String?,
            exitCode: r['exitCode'] as int?,
            forced: r['forced'] as bool? ?? false,
          ),
      ],
    );
