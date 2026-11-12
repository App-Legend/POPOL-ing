import '../models/env_change.dart';
import '../models/errors.dart';

/// 마지막 성공 실행 환경과 지금 환경의 차이(FR-16). AI-02 실행 실패 원인 분석의 재료.
///
/// - 진짜 구현: C (`checks/`)
/// - 쓰는 곳: D(`ai/` 실행 실패 원인 분석)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [envDiffContract] 로 확인한다.
abstract interface class EnvDiff {
  /// 달라진 것 목록. 차이가 없으면 빈 목록, 성공 기록이 아직 없으면 null.
  /// 없는 프로젝트면 [ProjectNotFoundException].
  Future<List<EnvChange>?> sinceLastSuccess(String projectId);
}
