import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';

import 'catalog_view.dart';

/// [실행 점검] 결과. [ok] 면 알림으로, 아니면 카드에 빨간 글로 보인다.
typedef StaleCheckResult = ({bool ok, String message});

/// 오래된 프로젝트 실행 점검(FR-17): 환경 점검 → 전체 실행 → 기본 QA 를 차례로 한다.
///
/// 앞 단계에서 문제가 나오면 거기서 멈춘다. 도구가 없는데 전체 실행부터 하면 실패만 쌓여서.
/// 점검이 통과하면 실행한 항목은 그대로 둔다(사용자가 [전체 종료]로 끈다).
Future<StaleCheckResult> runStaleCheck(Project project, {required EnvChecker env, required Orchestrator runner, required QaRunner qa}) async {
  final requires = project.config?.requires ?? const <Requirement>[];
  if (requires.isNotEmpty) {
    final problems = (await env.check(requires)).where((r) => r.status != EnvStatus.passed).length;
    if (problems > 0) {
      return (ok: false, message: '환경 점검에서 문제 $problems개가 나와 실행하지 않았어요. 프로젝트 화면의 환경 점검 탭에서 확인해 주세요.');
    }
  }
  final problem = runProblemText(await runner.runAll(project.id), stopping: false);
  if (problem != null) return (ok: false, message: '실행 점검: $problem');
  final run = await qa.runChecks(project.id, trigger: QaTrigger.staleCheck);
  if (run.failed > 0) return (ok: false, message: '실행은 됐지만 ${qa is FakeQaRunner ? '헬스체크(샘플)' : '헬스체크'} ${run.failed}개가 실패했어요.');
  // 진짜 QaRunner 가 아직 없어 가짜면 결과에 "샘플"을 붙인다(로그 탭 헬스체크와 같게). 가짜 통과가 진짜처럼 보이지 않게.
  final health = qa is FakeQaRunner ? '헬스체크(샘플)' : '헬스체크';
  return (ok: true, message: run.passed == 0 ? '지금도 실행돼요. $health할 주소는 없어요.' : '지금도 실행돼요. $health ${run.passed}개 통과.');
}
