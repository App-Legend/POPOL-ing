import '../contracts/env_checker.dart';
import '../models/env_check.dart';
import '../models/requirement.dart';

/// [EnvChecker] 의 가짜 구현. 실제로 명령을 실행하지 않는다.
///
/// [installed] 에 넣은 도구만 설치된 것으로 보고, 버전 범위는 [EnvChecker] 에 적힌 규칙대로 비교한다.
/// Docker 는 [dockerRunning] 을 따른다. 모두 테스트 중에 바꿔도 된다.
/// ```dart
/// final env = FakeEnvChecker(installed: {'node': '22.3.0', 'java': '17.0.9'});
/// await env.check([CliRequirement('node', version: '>=20'), DockerRequirement()]);   // 통과 2
/// ```
class FakeEnvChecker implements EnvChecker {
  FakeEnvChecker({Map<String, String> installed = const {}, this.dockerRunning = true, this.dockerVersion = '27.1.1'})
      : installed = {...installed};

  /// 명령 이름 → 설치된 버전.
  final Map<String, String> installed;

  bool dockerRunning;
  String dockerVersion;

  @override
  Future<List<EnvCheckResult>> check(List<Requirement> requires) async =>
      List.unmodifiable([for (final r in requires) _check(r)]);

  EnvCheckResult _check(Requirement requirement) {
    switch (requirement) {
      case DockerRequirement():
        return dockerRunning
            ? EnvCheckResult(requirement: requirement, status: EnvStatus.passed, foundVersion: dockerVersion)
            : EnvCheckResult(
                requirement: requirement,
                status: EnvStatus.daemonNotRunning,
                message: 'Docker 가 꺼져 있어요. Docker Desktop 을 실행해 주세요.',
              );
      case CliRequirement(:final cli, :final version):
        final found = installed[cli];
        if (found == null) {
          return EnvCheckResult(requirement: requirement, status: EnvStatus.notInstalled, message: '$cli 명령을 찾을 수 없어요.');
        }
        if (version == null) return EnvCheckResult(requirement: requirement, status: EnvStatus.passed, foundVersion: found);
        final allowed = _allows(version, found);
        if (allowed == null) {
          return EnvCheckResult(
            requirement: requirement,
            status: EnvStatus.checkFailed,
            foundVersion: found,
            message: '버전 조건을 읽을 수 없어요: $version',
          );
        }
        return EnvCheckResult(
          requirement: requirement,
          status: allowed ? EnvStatus.passed : EnvStatus.versionMismatch,
          foundVersion: found,
          message: allowed ? null : '$version 이 필요한데 지금은 $found 이에요.',
        );
    }
  }

  static final _condition = RegExp(r'^(>=|<=|>|<|=)?(\d+(?:\.\d+)*)$');

  /// [range] 를 [version] 이 만족하는지. 범위를 해석할 수 없으면 null.
  static bool? _allows(String range, String version) {
    final have = _parts(version);
    final conditions = range.trim().split(RegExp(r'\s+'));
    if (have == null || conditions.isEmpty) return null;
    for (final c in conditions) {
      final m = _condition.firstMatch(c);
      if (m == null) return null;
      final op = m[1] ?? '=';
      final want = _parts(m[2]!)!;
      if (op == '=') {
        for (var i = 0; i < want.length; i++) {
          if ((i < have.length ? have[i] : 0) != want[i]) return false;
        }
        continue;
      }
      final cmp = _compare(have, want);
      final ok = switch (op) { '>=' => cmp >= 0, '>' => cmp > 0, '<=' => cmp <= 0, _ => cmp < 0 };
      if (!ok) return false;
    }
    return true;
  }

  static List<int>? _parts(String v) {
    final m = RegExp(r'^v?(\d+(?:\.\d+)*)').firstMatch(v.trim());
    return m?[1]!.split('.').map(int.parse).toList();
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < a.length || i < b.length; i++) {
      final d = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }
}
