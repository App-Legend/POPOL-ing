@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_core/contracts.dart';
import 'package:ppoling_core/fakes.dart';
import 'package:ppoling_core/testing.dart';
import 'package:ppoling_runner/src/log/log_store.dart';
import 'package:ppoling_runner/src/orchestrator/runner_orchestrator.dart';
import 'package:ppoling_runner/src/process/posix_process_launcher.dart';
import 'package:ppoling_runner/src/runtime/runner_runtime_query.dart';
import 'package:ppoling_runner/src/runtime/runtime_store.dart';

const _web = ItemRef(projectId: 'demo', serviceId: 'web');
const _db = ItemRef(projectId: 'demo', serviceId: 'db');

/// 포폴링과 무관하게 띄운 프로세스. 테스트가 끝나면 멈춘다.
Future<int> foreignProcess() async {
  final p = await Process.start('sleep', ['30']);
  addTearDown(p.kill);
  return p.pid;
}

/// web(프로세스, 포트 5173. `sh` 가 띄운 자식 `sleep` 이 포트를 잡았다고 친다)과 db(Compose, 포트 5432)를 띄운다.
/// 다른 프로젝트 shop 의 web 도 5173 을 쓰지만 띄우지 않는다. 오케스트레이터도 돌려받은 RuntimeQuery 로 포트 주인을 찾는다.
Future<(RunnerOrchestrator, RunnerRuntimeQuery, FakePortProbe)> setUpRunning() async {
  final tmp = Directory.systemTemp.createTempSync('ppoling_rq_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final repo = FakeProjectRepository(projects: [
    Project(
      id: 'demo',
      name: 'demo',
      folderPath: tmp.resolveSymbolicLinksSync(),
      registeredAt: DateTime(2026, 11, 18),
      config: const ProjectConfig(services: [
        ComposeService(id: 'db', file: './docker-compose.yml'),
        ProcessService(id: 'web', command: ['sh', '-c', 'sleep 30 & echo ready; wait'], ports: [5173], ready: LogReady(pattern: 'ready')),
      ]),
    ),
    Project(
      id: 'shop',
      name: 'shop',
      folderPath: tmp.resolveSymbolicLinksSync(),
      registeredAt: DateTime(2026, 11, 18),
      config: const ProjectConfig(services: [ProcessService(id: 'web', command: ['sleep', '30'], ports: [5173])]),
    ),
  ]);
  final launcher = FakeItemLauncher(repo, ports: {'db': [5432]});
  final ports = FakePortProbe();
  late final RunnerRuntimeQuery query;
  final o = RunnerOrchestrator(
    projects: () => repo,
    launcher: () => launcher,
    ports: () => ports,
    http: () => FakeHttpProbe(),
    runtime: () => query,
    processes: PosixProcessLauncher(searchPath: () async => '/usr/bin:/bin'),
    logs: LogStore(() async => Directory('${tmp.path}/logs')),
    store: RuntimeStore(() async => File('${tmp.path}/runtime.json')),
  );
  addTearDown(() => o.stopAll('demo'));
  expect((await o.runAll('demo')).succeeded, isTrue);
  query = RunnerRuntimeQuery(processes: () => o.liveProcesses, launcher: () => launcher);
  return (o, query, ports);
}

/// [pgid] 그룹에서 리더가 아닌 프로세스의 PID.
Future<int> childOf(int pgid) async {
  final r = await Process.run('ps', ['-A', '-o', 'pid=,pgid=']);
  return (r.stdout as String)
      .split('\n')
      .map((l) => l.trim().split(RegExp(r'\s+')))
      .where((c) => c.length == 2 && c[1] == '$pgid' && c[0] != '$pgid')
      .map((c) => int.parse(c[0]))
      .first;
}

void main() {
  group('약속 테스트', () {
    runtimeQueryContract(() async {
      final (o, query, _) = await setUpRunning();
      return RuntimeQueryFixture(
        query: query,
        processPort: 5173,
        processPid: await childOf(o.liveProcesses.single.process.pgid),
        processItem: _web,
        foreignPid: await foreignProcess(),
        composePort: 5432,
        composeItem: _db,
        unownedPort: 8080,
      );
    });
  });

  test('띄운 명령 자신의 PID 도 내 항목이다', () async {
    final (o, query, _) = await setUpRunning();
    expect(await query.ownerOf(PortInUse(5173, pid: o.liveProcesses.single.process.pid)), _web);
  });

  test('멈춘 뒤에는 같은 PID 여도 내 항목이 아니다', () async {
    final (o, query, _) = await setUpRunning();
    final pid = o.liveProcesses.single.process.pid;
    await o.stop(_web);
    expect(await query.ownerOf(PortInUse(5173, pid: pid)), isNull);
  });

  test('다른 프로젝트가 시작할 때 포트 주인이 내 항목이면 그 항목을 알리고, 멈춘 뒤에는 시작된다 (AT-17)', () async {
    final (o, _, ports) = await setUpRunning();
    const shopWeb = ItemRef(projectId: 'shop', serviceId: 'web');
    addTearDown(() => o.stop(shopWeb));
    ports.inUse[5173] = PortInUse(5173, pid: await childOf(o.liveProcesses.single.process.pgid), processName: 'sleep');

    final r = await o.start(shopWeb);
    expect(r.reason, '포트 5173 를 demo / web 항목이 쓰고 있어요.');
    expect(o.stateOf(shopWeb), ItemState.portBusy);

    await o.stop(_web);
    ports.inUse.remove(5173);
    expect((await o.start(shopWeb)).outcome, ItemOutcome.ok);
  });

  test('확인하다 예외가 나도 던지지 않고 null 이다', () async {
    final query = RunnerRuntimeQuery(processes: () => throw StateError('boom'), launcher: () => throw StateError('boom'));
    expect(await query.ownerOf(const PortInUse(5173, pid: 1)), isNull);
  });
}
