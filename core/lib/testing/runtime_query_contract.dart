import 'package:flutter_test/flutter_test.dart';

import '../contracts/runtime_query.dart';
import '../models/item_ref.dart';
import '../models/probe.dart';

/// [runtimeQueryContract] 가 테스트마다 받는 준비물.
class RuntimeQueryFixture {
  RuntimeQueryFixture({
    required this.query,
    required this.processPort,
    required this.processPid,
    required this.processItem,
    required this.foreignPid,
    required this.composePort,
    required this.composeItem,
    required this.unownedPort,
  });

  final RuntimeQuery query;

  /// 포폴링이 띄운 프로세스 항목 [processItem] 이 쓰는 포트와 그 PID.
  final int processPort;
  final int processPid;
  final ItemRef processItem;

  /// 포폴링과 무관한 프로세스의 PID. 진짜 구현 테스트에서는 테스트가 따로 띄운 프로세스의 PID 를 쓴다
  /// ([processPid] 의 자식 PID 와 겹치면 안 된다).
  final int foreignPid;

  /// 포폴링이 띄운 Compose 항목 [composeItem] 이 쓰는 포트.
  final int composePort;
  final ItemRef composeItem;

  /// 실행 기록에 없는 포트.
  final int unownedPort;
}

/// [RuntimeQuery] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
void runtimeQueryContract(Future<RuntimeQueryFixture> Function() setUp) {
  test('포트와 PID 가 실행 기록과 맞으면 그 항목이다', () async {
    final f = await setUp();
    expect(await f.query.ownerOf(PortInUse(f.processPort, pid: f.processPid)), f.processItem);
  });

  test('포트만 맞고 PID 가 다르면 null 이다(외부 프로그램)', () async {
    final f = await setUp();
    expect(await f.query.ownerOf(PortInUse(f.processPort, pid: f.foreignPid)), isNull);
  });

  test('프로세스 항목인데 PID 를 모르면 null 이다', () async {
    final f = await setUp();
    expect(await f.query.ownerOf(PortInUse(f.processPort)), isNull);
  });

  test('Compose 항목은 PID 와 상관없이 포트로 판단한다', () async {
    final f = await setUp();
    expect(await f.query.ownerOf(PortInUse(f.composePort)), f.composeItem);
    expect(await f.query.ownerOf(PortInUse(f.composePort, pid: 99999)), f.composeItem);
  });

  test('기록에 없는 포트는 null 이다', () async {
    final f = await setUp();
    expect(await f.query.ownerOf(PortInUse(f.unownedPort, pid: f.processPid)), isNull);
  });
}
