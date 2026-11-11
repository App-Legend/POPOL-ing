import 'package:flutter_test/flutter_test.dart';

import '../contracts/env_checker.dart';
import '../models/env_check.dart';
import '../models/requirement.dart';

/// [envCheckerContract] 가 테스트마다 받는 준비물.
class EnvCheckerFixture {
  EnvCheckerFixture({
    required this.checker,
    required this.installedCli,
    required this.dockerRunning,
    this.missingCli = 'ppoling-no-such-cli',
  });

  final EnvChecker checker;

  /// 설치돼 있고 버전을 읽을 수 있는 명령. 진짜 구현 테스트에서는 `git` 처럼 CI 에 늘 있는 것.
  final String installedCli;

  /// 설치돼 있지 않은 명령.
  final String missingCli;

  /// 이 환경에서 Docker 데몬이 켜져 있는가. 진짜 구현 테스트에서는 CI 환경에 맞춰 넘긴다.
  final bool dockerRunning;
}

/// [EnvChecker] 구현이 계약을 지키는지 확인하는 테스트 묶음. [setUp] 은 테스트마다 불린다.
void envCheckerContract(Future<EnvCheckerFixture> Function() setUp) {
  test('결과는 받은 목록과 같은 순서·같은 개수이고, 요구 사항을 그대로 담는다', () async {
    final f = await setUp();
    final requires = [CliRequirement(f.missingCli), CliRequirement(f.installedCli), const DockerRequirement()];
    final results = await f.checker.check(requires);
    expect([for (final r in results) r.requirement], requires);
  });

  test('빈 목록이면 빈 결과다', () async {
    final f = await setUp();
    expect(await f.checker.check(const []), isEmpty);
  });

  test('설치된 도구는 버전 조건이 없으면 통과이고, 찾은 버전이 있다', () async {
    final f = await setUp();
    final [result] = await f.checker.check([CliRequirement(f.installedCli)]);
    expect(result.status, EnvStatus.passed);
    expect(result.foundVersion, isNotNull);
  });

  test('버전 조건을 만족하면 통과, 아니면 버전 불일치와 찾은 버전', () async {
    final f = await setUp();
    final [ok, mismatch, range] = await f.checker.check([
      CliRequirement(f.installedCli, version: '>=0'),
      CliRequirement(f.installedCli, version: '>=9999'),
      CliRequirement(f.installedCli, version: '>=0 <9999'),
    ]);
    expect(ok.status, EnvStatus.passed);
    expect(mismatch.status, EnvStatus.versionMismatch);
    expect(mismatch.foundVersion, isNotNull);
    expect(mismatch.message, isNotNull);
    expect(range.status, EnvStatus.passed);
  });

  test('버전 조건을 읽을 수 없으면 점검 실패다', () async {
    final f = await setUp();
    final [result] = await f.checker.check([CliRequirement(f.installedCli, version: '최신')]);
    expect(result.status, EnvStatus.checkFailed);
    expect(result.message, isNotNull);
  });

  test('없는 도구는 미설치이고, 나머지는 계속 검사한다', () async {
    final f = await setUp();
    final [missing, installed] = await f.checker.check([CliRequirement(f.missingCli, version: '>=1'), CliRequirement(f.installedCli)]);
    expect(missing.status, EnvStatus.notInstalled);
    expect(missing.foundVersion, isNull);
    expect(installed.status, EnvStatus.passed);
  });

  test('Docker 는 켜져 있으면 통과와 버전, 꺼져 있으면 데몬 미실행', () async {
    final f = await setUp();
    final [result] = await f.checker.check([const DockerRequirement()]);
    if (f.dockerRunning) {
      expect(result.status, EnvStatus.passed);
      expect(result.foundVersion, isNotNull);
    } else {
      expect(result.status, EnvStatus.daemonNotRunning);
      expect(result.foundVersion, isNull);
    }
  });
}
