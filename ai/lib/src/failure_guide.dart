import 'package:flutter/material.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/ui.dart';

import 'redact.dart';

/// 실패 안내 카드의 조치(기획서 §8). 지금 계약으로 바로 할 수 있는 것만 버튼으로 둔다.
///
/// 설치하기·예시 파일 복사(C, FR-07)·더 기다리기·로그 저장(A)은 계약이 생기면 더한다.
/// 그 전에는 "이렇게 해 보세요"에 글로 안내한다(눌러도 아무 일 없는 버튼을 두지 않으려고).
enum GuideAction {
  /// 포트를 쓰는 내 다른 항목을 멈추고 이 항목을 시작한다. 확인 창을 거친다.
  stopOwnerAndStart,

  /// 포트를 쓰는 내 다른 항목의 프로젝트 화면으로 간다.
  openOwner,

  /// 이 항목만 다시 시작한다.
  start,

  /// 이 항목만 끈다.
  stop,
}

/// 실패 안내 한 장: 무슨 일 / 근거 / 이렇게 해 보세요 / 조치 버튼.
class FailureGuide {
  const FailureGuide({required this.what, required this.evidence, required this.tryThis, this.actions = const []});

  final String what;

  /// 필요한 도구·포트 주인·로그 줄 같은 근거. 비밀값은 가린 뒤다.
  final List<String> evidence;
  final String tryThis;

  /// 조치와 버튼 이름. 버튼 이름은 기획서 §8 그대로.
  final List<(GuideAction, String)> actions;
}

/// 실행기가 알려 준 원인([ItemResult.cause], 있어야 한다)으로 실패 안내를 만든다.
/// AI 없이 규칙으로만 만든다(API 키가 없어도 보인다).
FailureGuide failureGuide(ItemResult result) {
  final cause = result.cause!;
  final id = result.item.serviceId;
  // 계약상 이미 가린 줄이지만, 화면에 평문으로 남지 않게 한 번 더 가린다.
  final logs = [for (final line in cause.evidence) redactSecrets(line).text];
  String code(int? exitCode) => exitCode == null ? '' : ' (종료 코드 $exitCode)';
  return switch (cause) {
    CommandFailed(:final exitCode) => FailureGuide(
        what: '$id 명령이 준비되기 전에 끝났어요${code(exitCode)}.',
        evidence: logs,
        tryThis: '로그 마지막 줄에서 원인을 보고, 설정 탭에서 명령과 폴더가 맞는지 확인해 주세요. 고친 뒤 [다시 켜기]를 눌러 주세요.',
        actions: const [(GuideAction.start, '다시 켜기')],
      ),
    ToolMissing(:final tool) => FailureGuide(
        what: '$tool 명령을 찾지 못해 $id을 시작하지 못했어요.',
        evidence: ['필요한 도구: $tool', ...logs],
        tryThis: '$tool을 설치하거나, 이미 설치했다면 PATH 에 들어 있는지 확인해 주세요. 필요한 버전은 환경 점검 탭에서 볼 수 있어요.',
      ),
    EnvFileMissing(:final path) => FailureGuide(
        what: '$path 파일이 없어 $id을 시작하지 못했어요.',
        evidence: ['필요한 파일: $path', ...logs],
        tryThis: '같은 폴더에 예시 파일(.env.example 등)이 있으면 복사해서 $path 를 만들고, 값은 팀원에게 따로 받아 채워 주세요.',
      ),
    PortBusy(:final usage, owner: final mine?) => FailureGuide(
        what: '${usage.port} 포트를 ${mine.projectId} / ${mine.serviceId}이 쓰고 있어서 $id을 시작하지 않았어요.',
        evidence: ['포트 주인: ${mine.projectId} / ${mine.serviceId} (포폴링이 띄운 항목)', ...logs],
        tryThis: '그 항목을 멈추고 $id을 시작하거나, 그 프로젝트로 가서 직접 정리해 주세요.',
        actions: [
          (GuideAction.stopOwnerAndStart, '${mine.projectId} / ${mine.serviceId} 중지하고 $id 시작'),
          (GuideAction.openOwner, '${mine.projectId}으로 이동'),
        ],
      ),
    PortBusy(:final usage) => FailureGuide(
        what: '${usage.port} 포트를 다른 프로그램이 쓰고 있어서 $id을 시작하지 않았어요.',
        evidence: [
          '포트 주인: ${[usage.processName ?? '알 수 없는 프로그램', if (usage.pid != null) '(PID ${usage.pid})'].join(' ')}, 포폴링이 띄우지 않은 프로그램',
          ...logs,
        ],
        // 포폴링이 띄우지 않은 프로그램은 멈추지 않는다(CLAUDE.md "꼭 지킬 것").
        tryThis: '포폴링이 띄운 프로그램이 아니라 멈추지 않아요. 그 프로그램을 직접 끄거나 popoling.yaml 에서 포트를 바꾼 뒤 [다시 시도]를 눌러 주세요.',
        actions: const [(GuideAction.start, '다시 시도')],
      ),
    ReadyTimeout(:final timeout) => FailureGuide(
        what: '$id이 ${timeout.inSeconds}초 안에 준비되지 않았어요. 프로그램은 아직 켜져 있어요.',
        evidence: logs,
        tryThis: '로그를 보고 아직 시작 중인지 확인해 주세요. 원래 오래 걸린다면 설정 탭에서 준비 조건의 시간을 늘려 주세요.',
        actions: const [(GuideAction.stop, '끄기')],
      ),
    Crashed(:final exitCode) => FailureGuide(
        what: '$id이 실행 중에 멈췄어요${code(exitCode)}.',
        evidence: logs,
        tryThis: '로그 마지막 줄에서 원인을 확인한 뒤 다시 켜 주세요.',
        actions: const [(GuideAction.start, '다시 켜기')],
      ),
  };
}

/// 실패 안내 카드(#89, 기획서 §8). 로그 탭의 "○○이 실패한 이유" 칸에서 AI 원인 분석보다 먼저 보인다.
class FailureGuideCard extends StatefulWidget {
  const FailureGuideCard({super.key, required this.item, required this.runner});

  /// 실패한 항목. [ItemResult.cause] 가 없으면 [ItemResult.reason] 한 줄만 보인다.
  final ItemResult item;
  final Orchestrator runner;

  @override
  State<FailureGuideCard> createState() => _FailureGuideCardState();
}

class _FailureGuideCardState extends State<FailureGuideCard> {
  GuideAction? _busy;

  Future<void> _run(GuideAction action) async {
    final item = widget.item.item;
    final owner = switch (widget.item.cause) {
      PortBusy(:final owner?) => owner,
      _ => null,
    };
    if (action == GuideAction.openOwner) {
      await Navigator.pushNamed(context, '/dashboard', arguments: owner!.projectId);
      return;
    }
    // 다른 프로젝트 항목은 확인 창(기본 [취소])을 거친다. 포트 번호만으로 멈추지 않고 실행기가 알려 준 내 항목만 멈춘다.
    if (action == GuideAction.stopOwnerAndStart && !await confirmStopOther(context, project: owner!.projectId, service: owner.serviceId)) return;
    if (!mounted) return;
    setState(() => _busy = action);
    final messenger = ScaffoldMessenger.maybeOf(context);
    String? problem;
    try {
      final result = switch (action) {
        GuideAction.stopOwnerAndStart => await widget.runner.stop(owner!).then((r) => r.outcome == ItemOutcome.ok ? widget.runner.start(item) : Future.value(r)),
        GuideAction.start => await widget.runner.start(item),
        GuideAction.stop => await widget.runner.stop(item),
        GuideAction.openOwner => throw StateError('위에서 처리'),
      };
      if (result.outcome != ItemOutcome.ok) problem = result.reason ?? '${result.item.serviceId}을 처리하지 못했어요.';
    } on PopolingException catch (e) {
      problem = e.message;
    } catch (_) {
      problem = '처리하지 못했어요.';
    }
    if (!mounted) return;
    setState(() => _busy = null);
    if (problem != null) messenger?.showSnackBar(SnackBar(content: Text(problem)));
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text2);
    const body = TextStyle(fontSize: 14, height: 1.6, color: C.text);
    final cause = widget.item.cause;
    if (cause == null) {
      final reason = widget.item.reason;
      return reason == null ? const SizedBox.shrink() : Text(reason, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: C.text));
    }
    final guide = failureGuide(widget.item);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Text(guide.what, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: C.text)),
      if (guide.evidence.isNotEmpty) ...[
        const Text('근거', style: label),
        for (final line in guide.evidence) Text(line, style: mono.copyWith(fontSize: 12, color: C.text2)),
      ],
      const Text('이렇게 해 보세요', style: label),
      Text(guide.tryThis, style: body),
      if (guide.actions.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, (action, text)) in guide.actions.indexed)
            Btn(
              _busy == action ? '처리하는 중…' : text,
              primary: i == 0,
              onPressed: _busy != null ? null : () => _run(action),
            ),
        ]),
    ]);
  }
}
