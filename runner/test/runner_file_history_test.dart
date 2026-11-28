import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/testing.dart';
import 'package:popoling_runner/src/git/git_adapter.dart';
import 'package:popoling_runner/src/git/runner_file_history.dart';

void git(String folder, List<String> args) {
  final r = Process.runSync(
      'git', ['-c', 'user.name=민지', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false', ...args],
      workingDirectory: folder);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
}

/// api/popoling.yaml 을 커밋하고 api/.env 는 커밋하지 않은 저장소.
String repo() {
  final dir = Directory.systemTemp.createTempSync('popoling_history_');
  addTearDown(() => dir.deleteSync(recursive: true));
  Directory('${dir.path}/api').createSync();
  File('${dir.path}/api/popoling.yaml').writeAsStringSync('name: demo\n');
  git(dir.path, ['init', '-q', '-b', 'main']);
  git(dir.path, ['add', '.']);
  git(dir.path, ['commit', '-qm', 'api 설정 추가']);
  File('${dir.path}/api/.env').writeAsStringSync('SECRET=x\n');
  return dir.resolveSymbolicLinksSync();
}

RunnerFileHistory history(String folder) => RunnerFileHistory(
      projects: () => FakeProjectRepository(projects: [
        Project(id: 'demo', name: 'demo', folderPath: folder, registeredAt: DateTime(2026, 11, 28)),
      ]),
      git: GitAdapter(),
    );

void main() {
  group('약속 테스트', () {
    fileHistoryContract(() async => FileHistoryFixture(
          history: history(repo()),
          projectId: 'demo',
          committedPath: 'api/popoling.yaml',
          uncommittedPath: 'api/.env',
        ));
  });

  test('작성자·제목을 그대로 읽는다', () async {
    final c = (await history(repo()).lastCommit('demo', 'api/popoling.yaml'))!;
    expect((c.author, c.subject), ('민지', 'api 설정 추가'));
    expect(DateTime.now().difference(c.committedAt).inMinutes, lessThan(5));
  });

  test('Git 저장소가 아니면 null', () async {
    final dir = Directory.systemTemp.createTempSync('popoling_plain_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/popoling.yaml').writeAsStringSync('name: demo\n');
    expect(await history(dir.path).lastCommit('demo', 'popoling.yaml'), isNull);
  });

  test('폴더 밖을 가리키는 링크는 따라가지 않는다', () async {
    final folder = repo();
    Link('$folder/outside.yaml').createSync(Platform.isWindows ? r'C:\Windows\win.ini' : '/etc/hosts');
    expect(await history(folder).lastCommit('demo', 'outside.yaml'), isNull);
  }, skip: Platform.isWindows ? '링크를 만들 권한이 없을 수 있다' : false);
}
