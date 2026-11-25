import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_checks/src/env/env_snapshot.dart';
import 'package:popoling_checks/src/env/system_env_diff.dart';
import 'package:popoling_core/events.dart';
import 'package:popoling_core/fakes.dart';
import 'package:popoling_core/models.dart';
import 'package:popoling_core/testing.dart';

void main() {
  late Directory temp;
  late EnvSnapshotStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('env_diff_test');
    store = EnvSnapshotStore(() async => File('${temp.path}${Platform.pathSeparator}env-history.json'));
  });
  tearDown(() => temp.delete(recursive: true));

  /// 명령마다 정한 출력을 돌려주는 가짜 실행. 정하지 않은 명령은 실패(종료 코드 1)로 답한다.
  _Run fakeRun(Map<String, String> outputs) {
    final run = _Run();
    run.handler = (exe, args) async {
      run.calls.add([exe, ...args]);
      final key = outputs.keys.where((k) => [exe, ...args].join(' ').startsWith(k)).firstOrNull;
      return key == null ? ProcessResult(0, 1, '', 'not found') : ProcessResult(0, 0, outputs[key], '');
    };
    return run;
  }

  SystemEnvDiff diffWith(_Run run, {FakeProjectRepository? projects}) {
    final repo = projects ?? FakeProjectRepository.withSamples();
    return SystemEnvDiff(projects: () => repo, store: store, run: run.handler, resolve: (cli, args) => [cli, ...args]);
  }

  EnvSnapshot snap(Map<String, String?> values) => EnvSnapshot(takenAt: DateTime(2026, 11, 20), values: values);

  group('계약', () {
    envDiffContract(() async {
      await store.write('weather-bot', snap({'node': '18.19.0'}));
      return EnvDiffFixture(
        diff: diffWith(fakeRun({'node --version': 'v22.1.0\n'})),
        changedProjectId: 'weather-bot',
        changedNames: {'node'},
        noRecordProjectId: 'popoling',
      );
    });
  });

  group('비교', () {
    test('둘 다 확인한 것 중 값이 다른 것만, 미설치는 after 가 null', () {
      final changes = SystemEnvDiff.compare(
        snap({'node': '20.1.0', 'docker': '27.0.0', 'commit': 'abc', 'java': '17.0.9'}),
        snap({'node': '20.1.0', 'docker': '28.1.0', 'java': null}), // commit 은 이번에 확인 못 함
      );
      expect([for (final c in changes) (c.name, c.before, c.after)], [('docker', '27.0.0', '28.1.0'), ('java', '17.0.9', null)]);
    });
  });

  group('지금 환경 읽기', () {
    test('requires 버전, compose 이미지 태그, Git 커밋을 읽는다', () async {
      final run = fakeRun({
        'node --version': 'v20.11.1\n',
        'docker version': '27.1.1\n',
        'docker compose': 'postgres:16\nredis\nghcr.io/team/api:1.2@sha256:abc\n',
        'git -C': '1a2b3c4d5e6f\n',
      });
      final project = SampleProjects.shopClone;
      final s = await diffWith(run).snapshot(project);

      expect(s.values, {
        'node': '20.11.1',
        'docker': '27.1.1',
        'image:postgres': '16',
        'image:redis': 'latest',
        'image:ghcr.io/team/api': '1.2',
        'commit': '1a2b3c4d5e6f',
      });
      final compose = run.calls.singleWhere((c) => c.take(2).join(' ') == 'docker compose');
      expect(compose.sublist(2, 4), ['-p', 'popoling-shop-clone']);
      expect(compose[5], endsWith('docker-compose.yml'));
      expect(compose.sublist(6), ['config', '--images']);
    });

    test('확인하지 못한 것(점검 실패·Git 저장소 아님)은 이름째 뺀다', () async {
      final s = await diffWith(fakeRun({})).snapshot(SampleProjects.shopClone);
      expect(s.values.keys, isNot(contains('commit')));
      expect(s.values.keys, isNot(contains('docker')));
    });

    test('프로젝트 폴더 밖의 compose 파일은 읽지 않는다', () async {
      final run = fakeRun({'docker compose': 'postgres:16\n'});
      final project = Project(
        id: 'outside',
        name: 'outside',
        folderPath: temp.path,
        registeredAt: DateTime(2026),
        config: const ProjectConfig(services: [
          ComposeService(id: 'a', file: '../other/docker-compose.yml'),
          ComposeService(id: 'b', file: '/etc/docker-compose.yml'),
        ]),
      );
      await diffWith(run).snapshot(project);
      expect(run.calls.where((c) => c.contains('compose')), isEmpty);
    });

    test('cmd.exe 를 거쳐야 하는 명령에는 폴더 경로를 넘기지 않는다', () async {
      final run = fakeRun({'git': 'abc\n'});
      final diff = SystemEnvDiff(
        projects: FakeProjectRepository.withSamples,
        store: store,
        run: run.handler,
        resolve: (cli, args) => [r'C:\Windows\System32\cmd.exe', '/d', '/c', '$cli.cmd', ...args],
      );
      final s = await diff.snapshot(SampleProjects.shopClone);
      expect(s.values.keys, isNot(contains('commit')));
      expect(run.calls.where((c) => c.contains('rev-parse')), isEmpty);
    });
  });

  group('성공 기록', () {
    test('RunSucceeded 를 받으면 그때 환경을 남기고, 그대로면 차이가 없다', () async {
      final diff = diffWith(fakeRun({'node --version': 'v22.1.0\n'}));
      final events = StreamController<RunEvent>();
      final sub = diff.listenTo(events.stream);
      expect(await diff.sinceLastSuccess('weather-bot'), isNull);

      events.add(RunSucceeded(RunSummary(projectId: 'weather-bot', startedAt: DateTime(2026), finishedAt: DateTime(2026), items: const [])));
      // 기록은 실제 파일 쓰기라 이벤트 큐만 비워서는 끝을 기다릴 수 없다.
      for (var i = 0; i < 200 && await store.read('weather-bot') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect((await store.read('weather-bot'))!.values, {'node': '22.1.0'});
      expect(await diff.sinceLastSuccess('weather-bot'), isEmpty);
      await sub.cancel();
      await events.close();
    });

    test('다른 프로젝트 기록은 지우지 않고, 깨진 파일은 기록 없음으로 본다', () async {
      await store.write('a', snap({'node': '1.0.0'}));
      await store.write('b', snap({'node': '2.0.0'}));
      expect((await store.read('a'))!.values, {'node': '1.0.0'});

      await File('${temp.path}${Platform.pathSeparator}env-history.json').writeAsString('{깨짐');
      expect(await store.read('a'), isNull);
    });
  });
}

class _Run {
  final calls = <List<String>>[];
  late Future<ProcessResult> Function(String exe, List<String> args) handler;
}
