import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_core/contracts.dart';
import 'package:popoling_runner/src/git/git_adapter.dart';

late Directory root;

String at(String name) => '${root.path}${Platform.pathSeparator}$name';

String git(String folder, List<String> args) {
  final r = Process.runSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false', ...args],
      workingDirectory: folder);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
  return (r.stdout as String).trim();
}

void write(String folder, String name, String text) => File('$folder${Platform.pathSeparator}$name').writeAsStringSync(text);
String read(String folder, String name) => File('$folder${Platform.pathSeparator}$name').readAsStringSync().trim();

void commit(String folder, String name, String text) {
  write(folder, name, text);
  git(folder, ['add', '.']);
  git(folder, ['commit', '-qm', text]);
}

/// 원격에 [name] 을 바꾼 커밋을 올린다(다른 팀원).
void teammate(String text, {String name = 'a.txt'}) {
  commit(at('other'), name, text);
  git(at('other'), ['push', '-q', 'origin', 'main']);
}

void main() {
  final adapter = GitAdapter();
  late String mine;

  setUp(() {
    root = Directory.systemTemp.createTempSync('popoling_git_');
    git(root.path, ['init', '-q', '--bare', '-b', 'main', 'remote.git']);
    git(root.path, ['clone', '-q', 'remote.git', 'other']);
    git(at('other'), ['checkout', '-q', '-B', 'main']);
    commit(at('other'), 'a.txt', '1');
    git(at('other'), ['push', '-q', '-u', 'origin', 'main']);
    git(root.path, ['clone', '-q', 'remote.git', 'mine']);
    mine = at('mine');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('저장소가 아니면 null', () async {
    final plain = Directory(at('plain'))..createSync();
    expect(await adapter.status(plain.path), isNull);
    expect(await adapter.pull(plain.path), isNull);
  });

  test('뒤처진 커밋 2개를 보여 주고, 받으면 사라진다 (AT-23)', () async {
    teammate('2');
    teammate('3');
    expect(await adapter.fetch(mine), isTrue);
    final s = (await adapter.status(mine))!;
    expect((s.branch, s.changed, s.ahead, s.behind), ('main', 0, 0, 2));

    final r = (await adapter.pull(mine))!;
    expect((r.outcome, r.message), (ItemOutcome.ok, 'origin/main에서 새 커밋 2개를 받았어요.'));
    expect((await adapter.status(mine))!.behind, 0);
    expect(read(mine, 'a.txt'), '3');
    expect((await adapter.pull(mine))!.message, 'origin/main에서 받을 새 커밋이 없어요.');
  });

  for (final (name, file) in [('고친 파일', 'a.txt'), ('새 파일', 'new.txt')]) {
    test('커밋하지 않은 변경($name)이 있으면 건너뛰고 파일은 그대로다 (AT-24)', () async {
      teammate('2');
      write(mine, file, 'mine');
      expect((await adapter.status(mine))!.changed, 1);
      final r = (await adapter.pull(mine))!;
      expect(r.outcome, ItemOutcome.skipped);
      expect(r.message, contains('커밋하지 않은 변경 1개'));
      expect(read(mine, file), 'mine');
      if (file != 'a.txt') expect(read(mine, 'a.txt'), '1');
    });
  }

  test('원격에 접속할 수 없으면 건너뛴다 (AT-24)', () async {
    git(mine, ['remote', 'set-url', 'origin', at('gone.git')]);
    expect(await adapter.fetch(mine), isFalse);
    final r = (await adapter.pull(mine))!;
    expect(r.outcome, ItemOutcome.skipped);
    expect(r.message, contains('접속할 수 없어요'));
    expect(read(mine, 'a.txt'), '1');
  });

  test('내 커밋과 갈라졌으면 병합하지 않고 건너뛴다', () async {
    teammate('2');
    commit(mine, 'b.txt', 'mine');
    final head = git(mine, ['rev-parse', 'HEAD']);
    final r = (await adapter.pull(mine))!;
    expect(r.message, contains('내 커밋 1개'));
    expect(git(mine, ['rev-parse', 'HEAD']), head);
  });

  test('내 커밋이 원격보다 앞서기만 하면 그대로 두고, 내 커밋을 포함해 실행한다고 알린다', () async {
    commit(mine, 'b.txt', 'mine');
    final head = git(mine, ['rev-parse', 'HEAD']);
    final r = (await adapter.pull(mine))!;
    expect((r.outcome, r.message), (ItemOutcome.ok, 'origin/main에서 받을 새 커밋이 없어요. 올리지 않은 내 커밋 1개를 포함해 실행했어요.'));
    final s = (await adapter.status(mine))!;
    expect((s.ahead, s.behind), (1, 0));
    expect(git(mine, ['rev-parse', 'HEAD']), head);
    expect(git(at('remote.git'), ['rev-parse', 'main']), isNot(head), reason: 'push 하지 않는다');
  });

  test('popoling.yaml 이 바뀌는 pull 은 건너뛴다', () async {
    teammate('version: 1', name: 'popoling.yaml');
    final r = (await adapter.pull(mine))!;
    expect(r.outcome, ItemOutcome.skipped);
    expect(r.message, contains('popoling.yaml'));
    expect(File('$mine${Platform.pathSeparator}popoling.yaml').existsSync(), isFalse);
  });

  test('하위 폴더 프로젝트도 자기 popoling.yaml 을 본다', () async {
    Directory('${at('other')}/app').createSync();
    teammate('x', name: 'app/x.txt');
    await adapter.pull(mine);
    teammate('version: 1', name: 'app/popoling.yaml');
    expect((await adapter.pull('$mine/app'))!.message, contains('popoling.yaml'));
  });

  test('연결된 원격 브랜치가 없거나 브랜치가 아니면 건너뛴다', () async {
    git(mine, ['checkout', '-q', '-b', 'local']);
    expect((await adapter.pull(mine))!.message, contains('원격 브랜치가 없어요'));
    git(mine, ['checkout', '-q', '--detach']);
    expect((await adapter.status(mine))!.branch, isNull);
    expect((await adapter.pull(mine))!.outcome, ItemOutcome.skipped);
  });

  test('저장소의 Git 훅을 실행하지 않는다', () async {
    final hook = File('$mine/.git/hooks/post-merge');
    hook.parent.createSync(recursive: true);
    hook.writeAsStringSync('#!/bin/sh\necho ran > hook-ran\n');
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', hook.path]);
    teammate('2');
    expect((await adapter.pull(mine))!.outcome, ItemOutcome.ok);
    expect(File('$mine/hook-ran').existsSync(), isFalse);
  });

  test('동시에 불러도 서로 방해하지 않는다', () async {
    teammate('2');
    final (fetched, pulled) = await (adapter.fetch(mine), adapter.pull(mine)).wait;
    expect(fetched, isTrue);
    expect(pulled!.outcome, ItemOutcome.ok);
  });
}
