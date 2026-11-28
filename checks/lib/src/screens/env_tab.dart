import 'dart:async';

import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

/// 프로젝트 화면 환경 점검 탭(FR-06·07·16, 목업 v2 4번): 포트, 도구 버전, 마지막 성공 때와 달라진 것.
///
/// 고치기 버튼(설치·버전 바꾸기)은 아직 없다. 내 다른 프로젝트 항목이 포트를 쓸 때만 [그 항목 중지]가 있다.
class EnvTab extends StatefulWidget {
  const EnvTab({
    super.key,
    required this.projectId,
    required this.projects,
    required this.env,
    required this.ports,
    required this.runtime,
    required this.runner,
    this.diff,
    this.onProblems,
  });

  final String projectId;
  final ProjectRepository projects;
  final EnvChecker env;
  final PortProbe ports;
  final RuntimeQuery runtime;
  final Orchestrator runner;

  /// 아직 앱에 없으면 null. 그때는 비교 칸에 기록이 없다고 보인다.
  final EnvDiff? diff;

  /// 다시 점검할 때마다 문제 수를 알린다. 탭 배지가 처음 숫자에 멈춰 있지 않게.
  final void Function(int problems)? onProblems;

  @override
  State<EnvTab> createState() => _EnvTabState();
}

/// 포트 한 줄: 포트, 그 포트를 쓰는 이 프로젝트 항목, 지금 쓰는 곳.
typedef _PortRow = ({int port, String service, PortUsage? usage, ItemRef? owner});

class _EnvTabState extends State<EnvTab> {
  List<EnvCheckResult>? _tools;
  String? _toolsError;
  List<_PortRow> _ports = const [];
  List<EnvChange>? _changes;
  var _diffError = false;
  String? _loadError;
  var _loading = true;
  final _stopping = <ItemRef>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ProjectConfig? config;
    try {
      config = (await widget.projects.getProject(widget.projectId)).config;
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '프로젝트 설정을 읽지 못해 환경을 확인하지 못했어요';
        });
      }
      return;
    }
    List<EnvCheckResult>? tools;
    String? toolsError;
    try {
      tools = await widget.env.check(config?.requires ?? const []);
    } catch (_) {
      toolsError = '도구를 확인하지 못했어요';
    }
    final ports = await _portRows(widget.ports, widget.runtime, config);
    List<EnvChange>? changes;
    var diffError = false;
    try {
      changes = await widget.diff?.sinceLastSuccess(widget.projectId);
    } catch (_) {
      diffError = true;
    }
    if (!mounted) return;
    setState(() {
      _tools = tools;
      _toolsError = toolsError;
      _ports = ports;
      _changes = changes;
      _diffError = diffError;
      _loadError = null;
      _loading = false;
    });
    // 배지(envProblemCount)와 같은 기준: 맞지 않는 도구 + 다른 곳이 쓰는 포트 + 달라진 것.
    widget.onProblems?.call((tools?.where((t) => t.status != EnvStatus.passed).length ?? 0) + ports.where(_foreign).length + (changes?.length ?? 0));
  }

  Future<void> _stop(ItemRef owner) async {
    if (!await confirmStopOther(context, project: owner.projectId, service: owner.serviceId)) return;
    if (!mounted) return;
    setState(() => _stopping.add(owner));
    try {
      final r = await widget.runner.stop(owner);
      if (r.outcome != ItemOutcome.ok) _say(r.reason ?? '$owner 항목을 멈추지 못했어요.');
      await _load();
    } catch (e) {
      _say(e is PopolingException ? e.message : '$owner 항목을 멈추지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _stopping.remove(owner));
    }
  }

  void _say(String message) {
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) return Text(_loadError!, style: TextStyle(fontSize: 14, color: C.bad.$2));
    if (_loading && _tools == null && _toolsError == null) return const LinearProgressIndicator();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Row(children: [
        const Expanded(child: Text('도구와 포트를 확인하고, 마지막으로 성공한 실행과 비교했어요.', style: TextStyle(fontSize: 13, color: C.muted))),
        Btn('환경 다시 점검', small: true, onPressed: _loading ? null : _load),
      ]),
      _portPanel(),
      _toolPanel(),
      _diffPanel(),
    ]);
  }

  bool _foreign(_PortRow r) => r.usage is PortInUse && r.owner?.projectId != widget.projectId;

  Widget _portPanel() {
    final busy = _ports.where(_foreign).length;
    final unknown = _ports.where((r) => r.usage == null).length;
    return Panel(
      title: '포트',
      subtitle: '시작하기 전에 비어 있는지 확인해요',
      titleAction: busy > 0
          ? StatusChip('사용 중 $busy', C.port)
          : unknown > 0
              ? StatusChip('확인하지 못함 $unknown', C.idle)
              : const StatusChip('모두 비어 있어요', C.ok),
      child: _ports.isEmpty
          ? const Text('확인할 포트가 없어요.', style: TextStyle(fontSize: 14))
          : SimpleTable(
              minWidth: 600,
              columns: const ['상태', '포트', '쓰는 항목', '지금 쓰는 곳', '동작'],
              rows: [
                for (final r in _ports)
                  [
                    r.usage == null
                        ? const StatusChip('확인하지 못함', C.idle)
                        : _foreign(r)
                            ? const StatusChip('사용 중', C.port)
                            : const StatusChip('정상', C.ok),
                    Text('${r.port}', style: mono),
                    Text(r.service),
                    Text(_whereText(r)),
                    if (_foreign(r) && r.owner != null)
                      Btn('${r.owner} 중지', small: true, onPressed: _stopping.contains(r.owner) ? null : () => _stop(r.owner!))
                    else
                      const SizedBox(),
                  ],
              ],
            ),
    );
  }

  String _whereText(_PortRow r) => switch (r.usage) {
        null => '확인하지 못했어요',
        PortFree() => '비어 있음',
        PortInUse() when r.owner?.projectId == widget.projectId => '이 프로젝트의 ${r.owner!.serviceId}',
        PortInUse() when r.owner != null => '${r.owner} · 내 다른 프로젝트',
        PortInUse(:final processName, :final pid) => [processName ?? '알 수 없는 프로그램', if (pid != null) '(PID $pid)'].join(' '),
      };

  Widget _toolPanel() {
    final tools = _tools;
    final bad = tools?.where((t) => t.status != EnvStatus.passed).length ?? 0;
    return Panel(
      title: '버전 확인',
      subtitle: '필요한 도구 버전과 이 컴퓨터에 설치된 버전을 비교해요',
      titleAction: tools == null
          ? null
          : bad > 0
              ? StatusChip('맞지 않음 $bad', C.bad)
              : StatusChip('${tools.length}개 모두 맞아요', C.ok),
      child: _toolsError != null
          ? Text(_toolsError!, style: TextStyle(fontSize: 14, color: C.bad.$2))
          : tools == null || tools.isEmpty
              ? const Text('필요한 도구가 적혀 있지 않아요.', style: TextStyle(fontSize: 14))
              : SimpleTable(
                  minWidth: 600,
                  columns: const ['도구', '필요 버전', '이 컴퓨터', '결과'],
                  rows: [
                    for (final t in tools)
                      [
                        Text(switch (t.requirement) { CliRequirement(:final cli) => cli, DockerRequirement() => 'Docker' }, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(switch (t.requirement) {
                          CliRequirement(:final version) => version ?? '설치돼 있으면 돼요',
                          DockerRequirement() => '켜져 있어야 해요',
                        }),
                        Text(t.foundVersion ?? '—', style: mono),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                          _statusChip(t.status),
                          if (t.message != null) Text(t.message!, style: const TextStyle(fontSize: 12, color: C.muted)),
                        ]),
                      ],
                  ],
                ),
    );
  }

  static StatusChip _statusChip(EnvStatus s) => switch (s) {
        EnvStatus.passed => const StatusChip('맞아요', C.ok),
        EnvStatus.notInstalled => const StatusChip('설치되지 않음', C.bad),
        EnvStatus.versionMismatch => const StatusChip('버전이 맞지 않아요', C.bad),
        EnvStatus.daemonNotRunning => const StatusChip('Docker가 꺼져 있어요', C.bad),
        EnvStatus.checkFailed => const StatusChip('확인하지 못함', C.idle),
      };

  Widget _diffPanel() {
    final changes = _changes;
    return Panel(
      title: '마지막 성공 때와 달라진 것',
      subtitle: changes == null || changes.isEmpty ? null : '실행이 실패하면 여기부터 보세요',
      titleAction: changes == null || changes.isEmpty ? null : StatusChip('${changes.length}가지', C.warn),
      child: _diffError
          ? Text('마지막 성공 환경과 비교하지 못했어요', style: TextStyle(fontSize: 14, color: C.bad.$2))
          : changes == null
          ? const Text('아직 성공한 실행 기록이 없어요.', style: TextStyle(fontSize: 14))
          : changes.isEmpty
              ? const Text('마지막으로 성공했을 때와 같아요.', style: TextStyle(fontSize: 14))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                  SimpleTable(
                    minWidth: 480,
                    columns: const ['항목', '지금', '마지막 성공 때'],
                    rows: [
                      for (final c in changes) [Text(c.name, style: mono), Text(c.after ?? '없음', style: mono), Text(c.before ?? '없음', style: mono)],
                    ],
                  ),
                ]),
    );
  }
}

/// 이 프로젝트 프로세스 항목의 포트를 하나씩 확인한다. 확인하지 못한 포트는 사용 정보 없이 둔다.
Future<List<_PortRow>> _portRows(PortProbe ports, RuntimeQuery runtime, ProjectConfig? config) async {
  final rows = <_PortRow>[];
  for (final s in config?.services.whereType<ProcessService>() ?? const <ProcessService>[]) {
    for (final port in s.ports) {
      PortUsage? usage;
      ItemRef? owner;
      try {
        usage = await ports.whoUses(port);
        if (usage case final PortInUse inUse) owner = await runtime.ownerOf(inUse);
      } catch (_) {
        // 확인하지 못하면 비어 있는 것으로 보이지 않게 usage 없이 둔다
      }
      rows.add((port: port, service: s.id, usage: usage, owner: owner));
    }
  }
  return rows;
}

/// 탭 배지: 맞지 않는 도구 + 다른 곳이 쓰는 포트 + 달라진 것 수. 확인하지 못한 칸은 세지 않는다.
Stream<int> envProblemCount({
  required String projectId,
  required ProjectRepository projects,
  required EnvChecker env,
  required PortProbe ports,
  required RuntimeQuery runtime,
  EnvDiff? diff,
  Stream<int> updates = const Stream.empty(),
}) async* {
  final config = (await projects.getProject(projectId)).config;
  var n = 0;
  try {
    n += (await env.check(config?.requires ?? const [])).where((t) => t.status != EnvStatus.passed).length;
  } catch (_) {}
  n += (await _portRows(ports, runtime, config)).where((r) => r.usage is PortInUse && r.owner?.projectId != projectId).length;
  try {
    n += (await diff?.sinceLastSuccess(projectId))?.length ?? 0;
  } catch (_) {}
  yield n;
  yield* updates; // 환경 점검 탭이 다시 점검한 숫자
}
