import '../models/errors.dart';
import '../models/file_commit.dart';

/// 프로젝트 파일이 마지막으로 바뀐 커밋(기획서 §8 처음 실행 명령 확인, pull 뒤 바뀐 명령 확인).
///
/// - 진짜 구현: A (`runner/`, Git 으로 읽는다)
/// - 쓰는 곳: B(처음 실행 명령 확인 창), A(pull 뒤 바뀐 명령 확인 창)
///
/// 지켜야 할 약속. `package:popoling_core/testing.dart` 의 [fileHistoryContract] 로 확인한다.
/// 1. Git 저장소가 아니거나, 커밋된 적 없는 파일이거나, 없는 파일이면 null. 예외를 던지지 않는다.
/// 2. 프로젝트 폴더 밖을 가리키는 경로(`../x`, 절대 경로)는 [ArgumentError].
/// 3. 없는 프로젝트면 [ProjectNotFoundException].
/// 4. 저장소 설정에 든 명령을 실행하지 않는다(남에게 받은 폴더에서 읽기만 해도 명령이 돌면 안 된다).
abstract interface class FileHistory {
  /// 프로젝트 [projectId] 폴더 기준 상대 경로 [path] 파일을 마지막으로 바꾼 커밋. 예: `popoling.yaml`, `api/.env`
  Future<FileCommit?> lastCommit(String projectId, String path);
}
