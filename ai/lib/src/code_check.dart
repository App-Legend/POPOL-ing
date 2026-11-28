import 'dart:convert';
import 'dart:io';

import 'redact.dart';

/// AI-04 코드 점검의 기준 4개(기획서 §2 '코드 점검').
enum CheckCriterion {
  config('설정·환경 및 비밀값'),
  quality('코드 품질·유지보수성'),
  performance('성능·리소스 및 데이터 흐름'),
  release('문서·테스트·릴리스 준비도');

  const CheckCriterion(this.label);

  final String label;
}

/// 기준마다의 상태. 점수는 쓰지 않는다(AI 가 같은 코드에도 매번 다른 숫자를 줄 수 있어서).
enum CheckLevel {
  danger('위험'),
  caution('주의'),
  good('좋음');

  const CheckLevel(this.label);

  final String label;
}

/// 기준 하나의 결과.
class CriterionResult {
  const CriterionResult({required this.criterion, required this.level, required this.reason, this.fix, this.evidence = const []});

  final CheckCriterion criterion;
  final CheckLevel level;

  /// 한 줄 이유.
  final String reason;

  /// 고칠 방법. 좋음이면 없을 수 있다.
  final String? fix;

  /// 근거(보낸 파일의 `경로:줄`).
  final List<String> evidence;

  Map<String, Object?> toJson() => {
        'criterion': criterion.name,
        'level': level.name,
        'reason': reason,
        if (fix != null) 'fix': fix,
        if (evidence.isNotEmpty) 'evidence': evidence,
      };

  /// 모양이 틀리면 [FormatException].
  factory CriterionResult.fromJson(Map<String, Object?> j) => CriterionResult(
        criterion: _byName(CheckCriterion.values, j['criterion']),
        level: _byName(CheckLevel.values, j['level']),
        reason: _string(j['reason']),
        fix: j['fix'] is String && (j['fix']! as String).trim().isNotEmpty ? (j['fix']! as String).trim() : null,
        evidence: [for (final e in (j['evidence'] as List?) ?? const []) if (e is String) e],
      );
}

/// 프로젝트 한 번의 코드 점검 결과. `ai-checks.json` 에 프로젝트마다 마지막 하나만 둔다.
class CodeCheckResult {
  const CodeCheckResult({
    required this.projectId,
    required this.at,
    required this.model,
    required this.files,
    required this.hiddenSecrets,
    required this.results,
  });

  final String projectId;
  final DateTime at;
  final String model;

  /// 보낸 파일 경로.
  final List<String> files;

  /// 보낼 때 가린 비밀값 줄 수.
  final int hiddenSecrets;

  /// 기준 4개, [CheckCriterion] 순서.
  final List<CriterionResult> results;

  int count(CheckLevel level) => results.where((r) => r.level == level).length;

  /// 가장 급한 한 줄: 위험 → 주의 → 좋음 순으로 처음 것의 이유.
  String get mostUrgent => ([...results]..sort((a, b) => a.level.index.compareTo(b.level.index))).first.reason;

  /// 상태별 개수. 예: `위험 1 · 주의 2 · 좋음 1`. 0 인 상태는 뺀다.
  String get countsLabel => [for (final l in CheckLevel.values) if (count(l) > 0) '${l.label} ${count(l)}'].join(' · ');

  Map<String, Object?> toJson() => {
        'projectId': projectId,
        'at': at.toIso8601String(),
        'model': model,
        'files': files,
        'hiddenSecrets': hiddenSecrets,
        'results': [for (final r in results) r.toJson()],
      };

  factory CodeCheckResult.fromJson(Map<String, Object?> j) => CodeCheckResult(
        projectId: _string(j['projectId']),
        at: DateTime.tryParse(_string(j['at'])) ?? (throw const FormatException('시각이 아니에요')),
        model: _string(j['model']),
        files: [for (final f in (j['files'] as List?) ?? const []) if (f is String) f],
        hiddenSecrets: j['hiddenSecrets'] is int ? j['hiddenSecrets']! as int : 0,
        results: _fourCriteria([for (final r in (j['results'] as List?) ?? const []) CriterionResult.fromJson(_map(r))]),
      );
}

/// 보낼 파일 하나(경로와 내용). C 의 규칙 검사(`ProjectScan`, #107)가 고른다.
class CodeCheckFile {
  const CodeCheckFile(this.path, this.text);

  /// 프로젝트 폴더 기준 경로.
  final String path;
  final String text;
}

/// 코드 점검에 쓸 재료: 보낼 파일(최대 5개)과 기준별 "앱이 확인" 줄.
///
/// C 의 `ProjectScan` 계약(#107)이 core 에 들어오면 그걸 이 모양으로 바꿔 준다. 그 전에는 화면이 [AI 검사 시작]을 막는다.
abstract interface class CodeCheckSource {
  Future<List<CodeCheckFile>> filesToSend(String projectId);

  /// 기준별로 앱이 규칙으로 센 것. 예: `.gitignore 에 .env 있음`, `600줄 넘는 파일 2개`
  Future<Map<CheckCriterion, List<String>>> appFindings(String projectId);
}

/// 보낼 파일 수의 상한(기획서 §2).
const maxCheckFiles = 5;

/// 보내기 직전 모양: 비밀값처럼 보이는 줄을 `●●●` 로 바꾼 글과 바꾼 곳.
class PreparedCheck {
  const PreparedCheck({required this.prompt, required this.files, required this.hiddenAt});

  final String prompt;
  final List<String> files;

  /// 가린 곳의 `경로:줄`.
  final List<String> hiddenAt;
}

/// 파일과 "앱이 확인" 줄로 보낼 글을 만든다. 비밀값처럼 보이는 줄은 통째로 `●●●` 로 바꾼다.
PreparedCheck prepareCodeCheck(List<CodeCheckFile> files, Map<CheckCriterion, List<String>> findings, {Iterable<String> secrets = const []}) {
  final picked = files.take(maxCheckFiles).toList();
  final hiddenAt = <String>[];
  final out = StringBuffer();
  for (final c in CheckCriterion.values) {
    final lines = findings[c] ?? const <String>[];
    if (lines.isNotEmpty) out.writeln('[앱이 확인 · ${c.name}] ${lines.join(' / ')}');
  }
  for (final f in picked) {
    out.writeln('=== ${f.path} ===');
    for (final (i, line) in f.text.split('\n').indexed) {
      if (redactSecrets(line, secrets: secrets).count > 0) {
        hiddenAt.add('${f.path}:${i + 1}');
        out.writeln('${i + 1}: ●●●');
      } else {
        out.writeln('${i + 1}: $line');
      }
    }
  }
  return PreparedCheck(prompt: out.toString(), files: [for (final f in picked) f.path], hiddenAt: hiddenAt);
}

/// AI 에 주는 지시. 답은 JSON 하나로만 받는다.
const codeCheckSystem = '너는 개인 프로젝트를 살펴보는 코드 점검 도우미다. 받은 파일과 [앱이 확인] 줄만 근거로, '
    '기준 4개(config: 설정·환경 및 비밀값, quality: 코드 품질·유지보수성, performance: 성능·리소스 및 데이터 흐름, '
    'release: 문서·테스트·릴리스 준비도)마다 level 을 good·caution·danger 중 하나로 고른다. 점수는 매기지 않는다. '
    '●●● 는 가린 비밀값이니 내용을 짐작하지 않는다. 한국어 존댓말로 짧게 쓴다. '
    '답은 다른 글 없이 JSON 하나: {"criteria":[{"id":"config","level":"caution","reason":"한 줄 이유","fix":"고칠 방법","evidence":["경로:줄"]}, ...]}';

/// AI 답을 읽는다. 기준 4개가 다 있어야 하고, 못 읽으면 null.
CodeCheckResult? parseCodeCheck(String reply, {required String projectId, required DateTime at, required String model, required PreparedCheck sent}) {
  try {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final json = _map(jsonDecode(reply.substring(start, end + 1)));
    final items = [
      for (final c in (json['criteria'] as List?) ?? const [])
        CriterionResult.fromJson({..._map(c), 'criterion': _map(c)['id']}),
    ];
    return CodeCheckResult(projectId: projectId, at: at, model: model, files: sent.files, hiddenSecrets: sent.hiddenAt.length, results: _fourCriteria(items));
  } on Object {
    return null;
  }
}

/// 프로젝트마다 마지막 코드 점검 하나(`ai-checks.json`). 분석 기록(최근 100개)에 밀려 지워지지 않게 따로 둔다.
///
/// 결과는 덤이라 파일을 못 읽거나 못 써도 예외를 내지 않는다. 그때도 이번 실행 동안은 메모리에 남는다.
class CodeCheckStore {
  CodeCheckStore(this._file);

  /// 파일에 쓰지 않는 저장소(테스트·데모용).
  CodeCheckStore.memory() : _file = null;

  final Future<File> Function()? _file;
  Map<String, CodeCheckResult>? _cache;
  Future<void> _writing = Future.value();

  Future<Map<String, CodeCheckResult>> load() async => Map.unmodifiable(_cache ??= await _read());

  Future<void> save(CodeCheckResult result) async {
    final next = {...await load(), result.projectId: result};
    _cache = next;
    _writing = _writing.then((_) => _write(next));
    await _writing;
  }

  Future<Map<String, CodeCheckResult>> _read() async {
    try {
      final f = _file;
      if (f == null) return {};
      final file = await f();
      if (!await file.exists()) return {};
      final json = _map(jsonDecode(await file.readAsString()));
      final out = <String, CodeCheckResult>{};
      for (final MapEntry(:key, :value) in json.entries) {
        try {
          out[key] = CodeCheckResult.fromJson(_map(value));
        } on Object {
          // 한 프로젝트만 모양이 틀리면 그것만 건너뛴다.
        }
      }
      return out;
    } on Object {
      return {}; // 깨진 파일이면 결과 없이 시작한다. 다음 저장 때 새로 쓴다.
    }
  }

  Future<void> _write(Map<String, CodeCheckResult> all) async {
    try {
      final f = _file;
      if (f == null) return;
      final file = await f();
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode({for (final MapEntry(:key, :value) in all.entries) key: value.toJson()}), flush: true);
      await tmp.rename(file.path);
    } on Object {
      // 저장이 실패해도 결과는 화면에 그대로 보인다.
    }
  }
}

List<CriterionResult> _fourCriteria(List<CriterionResult> items) => [
      for (final c in CheckCriterion.values) items.firstWhere((r) => r.criterion == c, orElse: () => throw FormatException('${c.name} 결과가 없어요')),
    ];

T _byName<T extends Enum>(List<T> values, Object? name) => values.firstWhere((v) => v.name == name, orElse: () => throw FormatException('$name 은 모르는 값이에요'));

String _string(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : throw const FormatException('글이 아니에요');

Map<String, Object?> _map(Object? v) => v is Map ? v.cast<String, Object?>() : throw const FormatException('맵이 아니에요');
