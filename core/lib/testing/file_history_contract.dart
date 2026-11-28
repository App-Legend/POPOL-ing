import 'package:flutter_test/flutter_test.dart';

import '../contracts/file_history.dart';
import '../models/errors.dart';

/// [fileHistoryContract] 가 테스트마다 받는 준비물.
class FileHistoryFixture {
  FileHistoryFixture({
    required this.history,
    required this.projectId,
    required this.committedPath,
    required this.uncommittedPath,
    this.unknownProjectId = 'no-such-project',
  });

  final FileHistory history;

  /// Git 저장소인 등록된 프로젝트.
  final String projectId;

  /// 커밋된 적 있는 파일. 하위 폴더에 있어야 경로 나눔(`/`)까지 확인한다. 예: `api/popoling.yaml`
  final String committedPath;

  /// 폴더에 있지만 커밋된 적 없는 파일.
  final String uncommittedPath;

  final String unknownProjectId;
}

/// [FileHistory] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
void fileHistoryContract(Future<FileHistoryFixture> Function() setUp) {
  test('커밋된 파일은 마지막 커밋을 돌려준다', () async {
    final f = await setUp();
    final c = await f.history.lastCommit(f.projectId, f.committedPath);
    expect(c, isNotNull);
    expect(c!.shortHash, isNotEmpty);
    expect(c.author, isNotEmpty);
    expect(c.subject, isNotEmpty);
  });

  test('./ 로 시작해도 같은 파일이다', () async {
    final f = await setUp();
    final a = await f.history.lastCommit(f.projectId, f.committedPath);
    final b = await f.history.lastCommit(f.projectId, './${f.committedPath}');
    expect(b?.shortHash, a!.shortHash);
  });

  test('커밋된 적 없거나 없는 파일이면 null', () async {
    final f = await setUp();
    expect(await f.history.lastCommit(f.projectId, f.uncommittedPath), isNull);
    expect(await f.history.lastCommit(f.projectId, 'no/such/file.yaml'), isNull);
  });

  test('프로젝트 폴더 밖 경로는 ArgumentError', () async {
    final f = await setUp();
    for (final p in ['../outside.yaml', 'api/../../outside.yaml', '/etc/passwd', r'C:\Windows\win.ini', '']) {
      await expectLater(f.history.lastCommit(f.projectId, p), throwsArgumentError, reason: p);
    }
  });

  test('없는 프로젝트면 ProjectNotFoundException', () async {
    final f = await setUp();
    await expectLater(
      f.history.lastCommit(f.unknownProjectId, f.committedPath),
      throwsA(isA<ProjectNotFoundException>()),
    );
  });
}
