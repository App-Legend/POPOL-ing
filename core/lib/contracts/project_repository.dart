import '../models/errors.dart';
import '../models/project.dart';

/// 등록한 프로젝트 목록과 각 프로젝트의 설정(ppoling.yaml)을 읽고 쓰는 창구.
///
/// - 진짜 구현: B (`project/`) · 계약과 가짜 구현: D
/// - 쓰는 곳: A(실행할 설정 읽기), C(환경 점검 대상 읽기), D(카탈로그·QA)
///
/// 지켜야 할 약속. `package:ppoling_core/testing.dart` 의 [projectRepositoryContract] 로 확인한다.
/// - 프로젝트 ID 는 등록할 때 정해지고 바뀌지 않는다. 소문자·숫자·- 만 쓴다([Project.idPattern]).
/// - 같은 폴더를 두 번 등록할 수 없다.
/// - 삭제는 앱 목록에서만 뺀다. 폴더와 ppoling.yaml 은 절대 지우지 않는다.
/// - 목록은 등록한 순서대로 돌려준다. 정렬·필터는 쓰는 쪽(카탈로그)이 한다.
abstract interface class ProjectRepository {
  /// 등록한 모든 프로젝트. 등록한 순서대로.
  Future<List<Project>> listProjects();

  /// 목록이 바뀔 때마다 전체 목록을 보낸다. 구독하면 지금 목록부터 한 번 보낸다.
  Stream<List<Project>> watchProjects();

  /// ID 로 프로젝트 하나를 찾는다. 없으면 [ProjectNotFoundException].
  Future<Project> getProject(String id);

  /// 폴더를 등록한다(FR-01). 폴더에 ppoling.yaml 이 있으면 읽어 [Project.config] 에 넣고,
  /// 형식 문제가 있으면 [Project.configIssues] 에 담는다(등록은 된다).
  ///
  /// [name] 을 주지 않으면 폴더 이름을 쓴다.
  /// 폴더가 없으면 [FolderNotFoundException], 이미 등록된 폴더면 [ProjectAlreadyRegisteredException].
  Future<Project> addProject(String folderPath, {String? name});

  /// 이름과 설정을 바꾼다. 설정은 그 폴더의 ppoling.yaml 에 저장한다(FR-02, FR-15).
  /// [Project.id]·[Project.folderPath]·[Project.registeredAt] 은 바뀌지 않는다.
  /// 없으면 [ProjectNotFoundException].
  Future<Project> updateProject(Project project);

  /// 앱 목록에서만 뺀다. 폴더와 ppoling.yaml 은 지우지 않는다.
  /// 없으면 [ProjectNotFoundException].
  Future<void> removeProject(String id);
}
