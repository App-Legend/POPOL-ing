import 'dart:convert';

import 'package:popoling_core/contracts.dart';

import 'qa_summary.dart' show stripHost;

/// AI-02 실행 실패 원인 분석에 쓰는 화면 없는 로직(기획서 §2 AI-02).
///
/// 실패한 항목 하나의 실패 이유·실행 설정·같은 실행의 다른 항목·환경 차이·로그 끝부분을 모아 보낼 글을 만든다.
/// 근거를 번호로 고르게 하려고 실패 이유는 `#R`, 환경 차이는 `#E1…`, 로그는 `#L1…` 을 붙인다.

/// 로그를 몇 줄까지 보낼지.
const failureLogLines = 50;

/// 로그 한 줄을 몇 글자까지 보낼지. 넘으면 자르고 `…` 를 붙인다(확인 창에서 읽을 수 있게).
const logLineMax = 300;

/// 실패 이유 한 줄. 이유에 종료 코드가 없으면 붙인다.
String failureReasonText(ItemResult r) {
  final reason = r.reason;
  final code = r.exitCode;
  if (reason != null && code != null && !reason.contains('종료 코드')) {
    return '$reason · 종료 코드 $code';
  }
  return reason ?? (code != null ? '종료 코드 $code' : '이유를 알 수 없어요.');
}

/// `node 20.11.0 → 22.3.0`. 그때 없었거나 지금 없으면 `없음`.
String envChangeLabel(EnvChange c) => '${c.name} ${c.before ?? '없음'} → ${c.after ?? '없음'}';

/// 실패한 항목 하나를 분석하려고 모은 것과, 그것으로 만든 보낼 글.
class FailureAnalysisInput {
  FailureAnalysisInput({
    required this.item,
    required this.run,
    this.service,
    this.envAvailable = true,
    this.envChanges,
    List<String>? logs,
  }) : logs = logs == null ? null : List.unmodifiable(logs.map(_clip));

  /// 분석할 실패 항목.
  final ItemResult item;

  /// 그 항목이 실패한 전체 실행.
  final RunSummary run;

  /// 그 항목의 실행 설정. 설정에서 찾지 못했으면 null.
  final ServiceConfig? service;

  /// 환경 비교(`EnvDiff`)를 쓸 수 있는지. false 면 [envChanges] 는 보지 않는다.
  final bool envAvailable;

  /// 마지막 성공 실행과 달라진 것. 성공 기록이 없으면 null.
  final List<EnvChange>? envChanges;

  /// 보낼 로그 줄([logLineMax] 에서 자른 것). 근거 칸도 이 줄을 보여준다. 못 읽었으면 null.
  final List<String>? logs;

  /// 화면을 막지 않게 절대 던지지 않는다. 못 읽은 것은 "못 읽음"으로 채운다.
  static Future<FailureAnalysisInput> collect({
    required ItemResult item,
    required RunSummary run,
    required ProjectRepository projects,
    LogExcerpt? logs,
    EnvDiff? envDiff,
  }) async {
    final projectId = item.item.projectId;
    final serviceId = item.item.serviceId;
    ServiceConfig? service;
    try {
      final services = (await projects.getProject(projectId)).config?.services ?? const <ServiceConfig>[];
      service = services.where((s) => s.id == serviceId).firstOrNull;
    } catch (_) {
      service = null; // 목록에서 지워진 프로젝트 등
    }
    List<String>? lines;
    try {
      lines = await logs?.tail(projectId, serviceId, lines: failureLogLines);
    } catch (_) {
      lines = null;
    }
    var envAvailable = envDiff != null;
    List<EnvChange>? changes;
    if (envDiff != null) {
      try {
        changes = await envDiff.sinceLastSuccess(projectId);
      } catch (_) {
        envAvailable = false;
      }
    }
    return FailureAnalysisInput(item: item, run: run, service: service, envAvailable: envAvailable, envChanges: changes, logs: lines);
  }

  String get prompt {
    final id = item.item.serviceId;
    final kind = switch (service) {
      ProcessService() => '내 컴퓨터에서 실행',
      ComposeService() => 'Docker Compose',
      RemoteService() => '원격 연결',
      null => null,
    };
    final others = [for (final r in run.items) if (r.item != item.item) _outcome(r)];
    final logs = this.logs;
    return [
      '[실패한 항목] ${[id, ?kind, '${_mdHm(run.finishedAt)} 전체 실행'].join(' · ')}',
      '#R ${failureReasonText(item)}',
      ..._settings(),
      if (others.isNotEmpty) '[같은 실행의 다른 항목] ${others.join(' · ')}',
      ..._env(),
      if (logs == null)
        '[로그] 로그를 읽지 못했어요.'
      else if (logs.isEmpty)
        '[로그] 남은 로그가 없어요.'
      else ...[
        '[로그] $id 마지막 ${logs.length}줄',
        for (final (i, line) in logs.indexed) '#L${i + 1} $line',
      ],
    ].join('\n');
  }

  List<String> _settings() {
    final s = service;
    if (s == null) {
      return const ['[실행 설정] 설정에서 이 항목을 찾지 못했어요.'];
    }
    final first = switch (s) {
      ProcessService() => [
          '명령 ${s.command.map(_arg).join(' ')}',
          '폴더 ${s.cwd}',
          if (s.ports.isNotEmpty) '포트 ${s.ports.join(', ')}',
          if (s.envFile != null) '.env 파일 씀(내용은 보내지 않음)',
          // env(환경변수)는 이름도 값도 보내지 않는다. 값에 비밀이 섞일 수 있어서.
        ].join(' · '),
      ComposeService() => 'compose 파일 ${s.file} · 서비스 ${s.services.isEmpty ? '파일 전체' : s.services.join(', ')}',
      RemoteService() => '원격 항목(켜고 끄지 않고 연결만 확인)',
    };
    final second = [
      '준비 조건 ${_ready(s.ready)}',
      if (s.dependsOn.isNotEmpty) '먼저 떠야 하는 항목 ${s.dependsOn.join(', ')}',
    ].join(' · ');
    return ['[실행 설정] $first', '  $second'];
  }

  List<String> _env() {
    final changes = envChanges;
    if (!envAvailable) return const ['[환경 차이] 환경 비교를 아직 쓸 수 없어요.'];
    if (changes == null) return const ['[환경 차이] 마지막 성공 실행 기록이 없어요.'];
    if (changes.isEmpty) return const ['[환경 차이] 마지막 성공 실행과 달라진 것이 없어요.'];
    return [
      '[환경 차이] 마지막 성공 실행과 비교',
      for (final (i, c) in changes.indexed) '#E${i + 1} ${envChangeLabel(c)}',
    ];
  }

  /// 주소의 호스트는 보내지 않는다(`PortReady.host` 포함).
  static String _ready(ReadyCondition r) {
    final what = switch (r) {
      HttpReady() => 'HTTP ${stripHost(r.url)} 응답${r.expectStatus == null ? '' : ' 코드 ${r.expectStatus}'}',
      PortReady() => '포트 ${r.port} 연결',
      LogReady() => '로그에 "${r.pattern}" 출력',
      ComposeHealthyReady() => 'compose healthy',
      NoneReady() => null,
    };
    return what == null ? '없음' : '$what(${r.timeout.inSeconds}초 안)';
  }

  static String _outcome(ItemResult r) {
    final label = switch (r.outcome) {
      ItemOutcome.ok => '성공',
      ItemOutcome.failed => '실패',
      ItemOutcome.skipped => '건너뜀',
    };
    return '${r.item.serviceId} ${r.reason == null ? label : '$label(${r.reason})'}';
  }

  /// 공백이 든 인자는 한 인자로 읽히게 따옴표로 묶는다.
  static String _arg(String a) => a.contains(RegExp(r'\s')) ? '"$a"' : a;

  static String _clip(String line) => line.length > logLineMax ? '${line.substring(0, logLineMax)}…' : line;
}

/// AI 에게 주는 역할·형식 지시.
const failureAnalysisSystem = '''
너는 개발 도구 '포폴링'의 실행 실패 원인 분석 도우미다.
- 아래는 실행에 실패한 항목 하나의 실패 이유(#R), 실행 설정, 같은 실행의 다른 항목, 마지막 성공 실행과 달라진 환경(#E 번호), 로그 끝부분(#L 번호)이다.
- 터미널을 잘 모르는 사람도 알아듣게 쉬운 한국어 존댓말(~해요)로 쓴다.
- 원인 후보를 1~3개, 가능성이 높은 것부터 쓴다. 후보마다 원인을 한두 문장으로 쓰고, 가능성(high 또는 possible)을 고른다.
- 후보마다 근거를 고른다: 로그 줄은 logs 에 #L 번호, 환경 차이는 env 에 #E 번호, 실패 이유를 근거로 쓰면 reason 을 true 로. 근거 없는 후보는 쓰지 않는다.
- 해결 방법은 사용자가 직접 할 수 있는 일로 1~4단계. 명령이 필요하면 그대로 칠 수 있는 명령을 쓴다.
- 데이터를 지우는 명령(예: rm -rf, docker compose down -v)은 제안하지 않는다. 꼭 필요하면 무엇이 지워지는지 먼저 말한다.
- 로그·설정·환경에 없는 값(버전, 줄 내용, 경로)을 지어내지 않는다.
- 다른 말 없이 JSON 하나만 답한다: {"candidates":[{"cause":"원인","likelihood":"high","logs":[2],"env":[1],"reason":false,"fixes":["방법"]}]}''';

/// 원인 후보의 가능성. 화면에는 [likelihoodLabel] 로 쓴다.
enum Likelihood { high, possible }

String likelihoodLabel(Likelihood l) => switch (l) {
      Likelihood.high => '가능성 높음',
      Likelihood.possible => '가능성 있음',
    };

/// 원인 후보 하나와 그 근거. 근거는 AI 가 고른 번호로 찾은 입력의 실제 값이다(AI 가 쓴 글이 아니라).
class FailureCandidate {
  const FailureCandidate({
    required this.cause,
    required this.likelihood,
    this.logLines = const [],
    this.envChanges = const [],
    this.reason = false,
    this.fixes = const [],
  });

  final String cause;
  final Likelihood likelihood;
  final List<String> logLines;
  final List<EnvChange> envChanges;

  /// 실패 이유(#R)가 근거다.
  final bool reason;
  final List<String> fixes;
}

/// AI 답에서 원인 후보를 읽는다. 못 읽거나 남는 후보가 없으면 null.
///
/// 이번 글에 없는 근거 번호는 그 번호만 무시하고, 근거가 하나도 남지 않은 후보는 뺀다("근거와 함께"가 원칙).
/// 가능성 높음을 앞으로(같은 가능성끼리는 AI 순서) 세우고 후보 3개, 해결 방법 4개까지 남긴다.
List<FailureCandidate>? parseFailureAnalysis(String reply, FailureAnalysisInput input) {
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
  if (json is! Map || json['candidates'] is! List) {
    return null;
  }
  final logs = input.logs ?? const <String>[];
  final env = (input.envAvailable ? input.envChanges : null) ?? const <EnvChange>[];
  final out = <FailureCandidate>[];
  for (final c in json['candidates'] as List) {
    if (c is! Map || c['cause'] is! String) {
      continue;
    }
    final cause = (c['cause'] as String).trim();
    final logLines = [for (final n in _numbers(c['logs'], logs.length)) logs[n - 1]];
    final changes = [for (final n in _numbers(c['env'], env.length)) env[n - 1]];
    final reason = c['reason'] == true;
    if (cause.isEmpty || (logLines.isEmpty && changes.isEmpty && !reason)) {
      continue;
    }
    final fixes = [
      if (c['fixes'] is List)
        for (final f in c['fixes'] as List)
          if (f is String && f.trim().isNotEmpty) f.trim(),
    ];
    out.add(FailureCandidate(
      cause: cause,
      likelihood: c['likelihood'] == 'high' ? Likelihood.high : Likelihood.possible,
      logLines: logLines,
      envChanges: changes,
      reason: reason,
      fixes: fixes.take(4).toList(),
    ));
  }
  final sorted = [
    ...out.where((c) => c.likelihood == Likelihood.high),
    ...out.where((c) => c.likelihood != Likelihood.high),
  ];
  return sorted.isEmpty ? null : sorted.take(3).toList();
}

/// 1부터 [count] 까지의 정수 번호만, 중복 없이 준 순서대로.
List<int> _numbers(Object? value, int count) => [
      if (value is List)
        ...{
          for (final n in value)
            if (n is int && n >= 1 && n <= count) n,
        },
    ];

String _two(int n) => n.toString().padLeft(2, '0');
String _mdHm(DateTime t) => '${t.month}/${t.day} ${_two(t.hour)}:${_two(t.minute)}';
