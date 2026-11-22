import 'dart:convert';

import 'package:ppoling_core/models.dart';

/// AI-03 QA 결과 요약에 쓰는 화면 없는 로직(기획서 §2 "기본 QA와의 연계").
///
/// 보낼 글을 만들고, API 를 부를지 정하고, 실패·느려진 항목을 고른다.
/// 판정(통과·실패)은 규칙(FR-10) 그대로이고 여기서 바꾸지 않는다.

/// 같은 항목의 최근 이력을 몇 번까지 보낼지.
const recentLimit = 5;

/// 이 배수 이상이면서 [slowMinDelta] 이상 늦으면 느려짐이다.
const slowFactor = 2;
const slowMinDelta = Duration(milliseconds: 200);

/// 검사한 곳에서 호스트를 빼고 경로만 남긴다. 쿼리·조각도 뺀다(비밀값이 섞일 수 있어서).
///
/// `GET http://localhost:8080/health?token=x` → `GET /health`, `localhost:3306` → `포트 3306`.
String stripHost(String target) {
  final m = RegExp(r'^(?:([A-Z]+)\s+)?(\S+)$').firstMatch(target.trim());
  if (m == null) {
    return target;
  }
  final method = m[1];
  final address = m[2]!;
  final uri = Uri.tryParse(address);
  if (uri != null && uri.hasScheme && uri.hasAuthority) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return method == null ? path : '$method $path';
  }
  final port = RegExp(r'^[^/]+:(\d+)$').firstMatch(address);
  if (port != null) {
    return '포트 ${port[1]}';
  }
  return target;
}

/// 화면·보낼 글에 쓰는 판정 라벨.
String qaStatusLabel(QaStatus status) => switch (status) {
      QaStatus.passed => '통과',
      QaStatus.failed => '실패',
      QaStatus.needsSetup => '설정 필요',
    };

enum QaFlagKind { failed, slow, needsSetup }

/// 요약 아래 목록에 보여줄 항목. AI 가 아니라 앱이 고른다.
class QaFlag {
  const QaFlag(this.kind, this.result);

  final QaFlagKind kind;
  final QaResult result;

  String get label => switch (kind) {
        QaFlagKind.failed => '실패',
        QaFlagKind.slow => '느려짐',
        QaFlagKind.needsSetup => '설정 필요',
      };
}

/// [now] 가 [recent] 의 응답 시간 평균보다 [slowFactor] 배 이상이고 [slowMinDelta] 이상 늦은지.
/// 응답 시간이 있는 이전 기록이 없으면 판단하지 않는다(false).
bool isSlow(QaResult now, List<QaResult> recent) {
  final current = now.elapsed;
  final samples = [for (final r in recent) ?r.elapsed];
  if (current == null || samples.isEmpty) {
    return false;
  }
  final avg = samples.fold(Duration.zero, (a, b) => a + b) ~/ samples.length;
  return current >= avg * slowFactor && current - avg >= slowMinDelta;
}

/// 검사 한 번을 요약할 재료.
class QaSummaryInput {
  QaSummaryInput({required this.run, List<QaRun> history = const [], this.lastRun})
      : previous = List.unmodifiable(
          history.where((h) => h.startedAt.isBefore(run.startedAt)).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
        );

  /// 요약할 검사.
  final QaRun run;

  /// [run] 보다 앞선 검사. 최근 것이 앞.
  final List<QaRun> previous;

  /// 마지막 전체 실행. 없으면 보낼 글에서 그 줄을 뺀다.
  final RunSummary? lastRun;

  /// 같은 이름 항목의 최근 결과. 최대 [recentLimit] 개, 최근 것이 앞.
  List<QaResult> recentOf(String name) => [
        for (final h in previous) ...h.results.where((r) => r.name == name).take(1),
      ].take(recentLimit).toList();

  /// 실패·느려짐·설정 필요. 검사 순서대로.
  List<QaFlag> get flags => [
        for (final r in run.results)
          if (r.status == QaStatus.failed)
            QaFlag(QaFlagKind.failed, r)
          else if (r.status == QaStatus.needsSetup)
            QaFlag(QaFlagKind.needsSetup, r)
          else if (isSlow(r, recentOf(r.name)))
            QaFlag(QaFlagKind.slow, r),
      ];

  /// false 면 API 를 부르지 않고 "모든 검사를 통과했어요."만 보여준다(AT-20).
  /// 모두 통과, 느려짐 없음, 직전 검사의 같은 항목도 모두 통과일 때 false.
  bool get needsAi {
    if (flags.isNotEmpty) {
      return true;
    }
    final last = previous.firstOrNull;
    if (last == null) {
      return false;
    }
    return run.results.any((r) => last.results.where((p) => p.name == r.name).any((p) => p.status != QaStatus.passed));
  }

  /// AI 에게 보낼 글. 검사마다 `#번호`를 붙여 근거를 번호로 고르게 한다.
  String get prompt {
    final lines = <String>[
      '[이번 검사] ${_ymdHm(run.startedAt)} · 통과 ${run.passed} · 실패 ${run.failed} · 설정 필요 ${run.needsSetup}',
    ];
    for (final (i, r) in run.results.indexed) {
      lines.add('#${i + 1} ${_describe(r)}');
      final recent = recentOf(r.name);
      if (recent.isNotEmpty) {
        lines.add('   최근: ${recent.map(_brief).join(', ')}');
      }
    }
    if (lastRun case final summary?) {
      final items = [for (final i in summary.items) '${i.item.serviceId} ${_outcome(i)}'];
      lines.add('[마지막 전체 실행] ${_mdHm(summary.startedAt)} · ${items.join(' · ')}');
    }
    return lines.join('\n');
  }

  static String _describe(QaResult r) {
    if (r.status == QaStatus.needsSetup) {
      return '${r.name} · 설정 필요(검사할 주소 없음)';
    }
    return [
      r.name,
      qaStatusLabel(r.status),
      if (r.target case final t?) stripHost(t),
      if (r.statusCode case final c?) '$c',
      ?r.failureReason,
      if (r.elapsed case final e?) '${e.inMilliseconds}ms',
      _hms(r.checkedAt),
    ].join(' · ');
  }

  static String _brief(QaResult r) => [
        qaStatusLabel(r.status),
        if (r.statusCode case final c?) '$c',
        if (r.elapsed case final e?) '${e.inMilliseconds}ms',
        '(${_mdHm(r.checkedAt)})',
      ].join(' ');

  static String _outcome(ItemResult i) {
    final label = switch (i.outcome) {
      ItemOutcome.ok => '성공',
      ItemOutcome.failed => '실패',
      ItemOutcome.skipped => '건너뜀',
    };
    return i.reason == null ? label : '$label(${i.reason})';
  }
}

/// AI 에게 주는 역할·형식 지시.
const qaSummarySystem = '''
너는 개발 도구 '포폴링'의 헬스체크(QA) 결과 요약 도우미다.
- 아래 검사 결과를 터미널을 잘 모르는 사람도 알아듣게 쉬운 한국어 존댓말(~해요) 2~3문장으로 요약한다.
- 통과·실패 판정은 이미 규칙으로 정해졌다. 판정을 바꾸거나 뒤집지 않고, 결과에 없는 값을 지어내지 않는다.
- 실패, 느려짐, 설정 필요, 최근 이력과 달라진 점을 먼저 말한다.
- 문장마다 근거가 된 검사 번호(# 뒤의 숫자)를 checks 에 넣는다.
- 다른 말 없이 JSON 하나만 답한다: {"sentences":[{"text":"문장","checks":[1]}]}''';

/// 요약 문장 하나와 그 근거가 된 실제 검사 결과.
class QaSummarySentence {
  const QaSummarySentence(this.text, this.evidence);

  final String text;

  /// AI 가 고른 번호로 찾은 이번 검사의 결과. 근거 칸은 이 값으로 만든다(AI 가 쓴 값이 아니라).
  final List<QaResult> evidence;
}

/// AI 답에서 문장과 근거 번호를 읽는다. 못 읽으면 null.
///
/// 근거 번호가 이번 검사에 없거나(범위 밖·숫자 아님) 비어 있는 문장은 뺀다. "문장마다 근거"가 완료 기준이라서.
List<QaSummarySentence>? parseQaSummary(String reply, QaRun run) {
  final start = reply.indexOf('{');
  final end = reply.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  final Object? json;
  try {
    json = jsonDecode(reply.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (json is! Map || json['sentences'] is! List) {
    return null;
  }
  final out = <QaSummarySentence>[];
  for (final s in json['sentences'] as List) {
    if (s is! Map || s['text'] is! String || s['checks'] is! List) {
      continue;
    }
    final text = (s['text'] as String).trim();
    final numbers = s['checks'] as List;
    final valid = numbers.isNotEmpty && numbers.every((n) => n is int && n >= 1 && n <= run.results.length);
    if (text.isEmpty || !valid) {
      continue;
    }
    out.add(QaSummarySentence(text, [for (final n in numbers.cast<int>().toSet()) run.results[n - 1]]));
  }
  return out.isEmpty ? null : out;
}

/// 근거 칸. `{이름} · {값} · {HH:mm}`. 값은 응답 코드 → 실패 이유 → 응답 시간 → 판정 라벨 중 있는 것 하나.
String evidenceLabel(QaResult r) {
  final value = r.statusCode?.toString() ?? r.failureReason ?? (r.elapsed != null ? '${r.elapsed!.inMilliseconds}ms' : qaStatusLabel(r.status));
  return '${r.name} · $value · ${_hm(r.checkedAt)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
String _hms(DateTime t) => '${_hm(t)}:${_two(t.second)}';
String _mdHm(DateTime t) => '${t.month}/${t.day} ${_hm(t)}';
String _ymdHm(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)} ${_hm(t)}';
