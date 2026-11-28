import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 분석 종류. AI 검사 화면 기록의 이름표.
enum AnalysisKind { failure, qaSummary }

/// 답을 받았는지, 보내지 못했는지.
enum AnalysisOutcome { received, failed }

/// AI 분석 기록 하나(기획서 §7: 보낸 내용 요약·결과·근거·사용 모델·시각).
///
/// 화면에 보인 글(이미 비밀값을 가린 것)만 남긴다. 보낸 원문과 API 키는 남기지 않는다.
class AnalysisRecord {
  const AnalysisRecord({
    required this.kind,
    required this.projectId,
    required this.title,
    required this.sentSummary,
    required this.at,
    required this.outcome,
    this.serviceId,
    this.body,
    this.model,
  });

  final AnalysisKind kind;
  final String projectId;
  final String? serviceId;

  /// 한 줄 결과, 보내지 못했으면 그 이유.
  final String title;

  /// 원인·해 볼 것·근거를 사람이 읽을 글로.
  final String? body;

  /// 보낸 것 요약. 예: `web 로그(비밀값 가림), 환경 차이 3건`
  final String sentSummary;
  final String? model;
  final DateTime at;
  final AnalysisOutcome outcome;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'projectId': projectId,
        if (serviceId != null) 'serviceId': serviceId,
        'title': title,
        if (body != null) 'body': body,
        'sentSummary': sentSummary,
        if (model != null) 'model': model,
        'at': at.toIso8601String(),
        'outcome': outcome.name,
      };

  factory AnalysisRecord.fromJson(Map<String, Object?> j) => AnalysisRecord(
        kind: AnalysisKind.values.byName(j['kind']! as String),
        projectId: j['projectId']! as String,
        serviceId: j['serviceId'] as String?,
        title: j['title']! as String,
        body: j['body'] as String?,
        sentSummary: j['sentSummary']! as String,
        model: j['model'] as String?,
        at: DateTime.parse(j['at']! as String),
        outcome: AnalysisOutcome.values.byName(j['outcome']! as String),
      );
}

/// 기록 파일을 읽지 못했다. 덮어쓰면 기록을 잃으므로 고치지 않고 알린다.
class AnalysisHistoryCorrupt implements Exception {
  const AnalysisHistoryCorrupt(this.path);
  final String path;
  @override
  String toString() => 'AI 분석 기록 파일을 읽지 못했어요: $path';
}

/// AI 분석 기록 저장소. 파일 하나(JSON 목록)에 최신순으로 [max] 개까지 둔다.
class AnalysisHistory {
  AnalysisHistory(this._file, {this.max = 100});

  final Future<File> Function() _file;
  final int max;
  final _changes = StreamController<void>.broadcast();

  /// 쓰기를 한 번에 하나씩 한다. 동시에 쓰면 같은 목록을 읽어 기록 하나가 사라진다.
  Future<void> _writing = Future.value();

  /// 기록이 더해질 때마다 알린다.
  Stream<void> get changes => _changes.stream;

  String? _recoveredTo;

  /// 깨진 기록 파일을 옮겨 둔 곳(`ai-history.json.bak`). 옮긴 적이 없으면 null.
  String? get recoveredTo => _recoveredTo;

  /// 최신순. 파일이 없으면 빈 목록.
  ///
  /// 깨졌으면 지우지 않고 `.bak` 으로 옮긴 뒤 빈 목록으로 새로 시작한다. 그대로 두면 다음 기록부터 영영 남지 않아서.
  /// 옮기지도 못하면 덮어쓰지 않도록 [AnalysisHistoryCorrupt].
  Future<List<AnalysisRecord>> list() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<Object?>;
      return [for (final r in raw) AnalysisRecord.fromJson((r! as Map).cast<String, Object?>())];
    } on Object {
      final backup = '${file.path}.bak';
      try {
        await file.rename(backup);
      } on Object {
        throw AnalysisHistoryCorrupt(file.path);
      }
      _recoveredTo = backup;
      return [];
    }
  }

  /// 맨 앞에 더한다. 임시 파일에 쓴 뒤 바꿔 끼워, 쓰다 멈춰도 기존 기록이 깨지지 않게 한다.
  Future<void> add(AnalysisRecord record) {
    final done = _writing.then((_) => _add(record));
    _writing = done.catchError((Object _) {}); // 한 번 실패해도 다음 쓰기는 한다
    return done;
  }

  Future<void> _add(AnalysisRecord record) async {
    final next = [record, ...await list()].take(max).toList();
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode([for (final r in next) r.toJson()]), flush: true);
    await temp.rename(file.path);
    _changes.add(null);
  }
}
