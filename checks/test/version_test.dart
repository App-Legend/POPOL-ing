import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_checks/src/env/version.dart';

void main() {
  group('readVersion: 버전 출력에서 처음 나오는 숫자 버전', () {
    test('도구마다 다른 출력 모양', () {
      expect(readVersion('v22.3.0\n'), '22.3.0');
      expect(readVersion('git version 2.45.1.windows.1'), '2.45.1');
      expect(readVersion('openjdk version "17.0.9" 2023-10-17\nOpenJDK Runtime'), '17.0.9');
      expect(readVersion('Python 3.12.4'), '3.12.4');
      expect(readVersion('go version go1.22.5 windows/amd64'), '1.22.5');
      expect(readVersion('Docker version 27.1.1, build 6312585'), '27.1.1');
      expect(readVersion('10.8.1'), '10.8.1');
    });

    test('자리 하나짜리 숫자는 버전으로 보지 않는다', () {
      expect(readVersion('java version "1.8.0_402"'), '1.8.0');
      expect(readVersion('build 7 of something 3.1'), '3.1');
    });

    test('버전이 없으면 null', () {
      expect(readVersion(''), isNull);
      expect(readVersion('command not found'), isNull);
    });
  });

  group('versionAllows: 계약(EnvChecker)에 적힌 범위 규칙', () {
    test('연산자 비교', () {
      expect(versionAllows('>=20', '22.3.0'), isTrue);
      expect(versionAllows('>=20', '18.19.0'), isFalse);
      expect(versionAllows('>20', '20.0.0'), isFalse);
      expect(versionAllows('<=17', '17.0.9'), isFalse);
      expect(versionAllows('<22', '21.9'), isTrue);
    });

    test('공백으로 이은 조건은 모두 만족해야 한다', () {
      expect(versionAllows('>=17 <22', '17.0.9'), isTrue);
      expect(versionAllows('>=17 <22', '22.0.0'), isFalse);
    });

    test('연산자가 없거나 = 면 적은 자리까지만 비교한다', () {
      expect(versionAllows('20', '20.11.1'), isTrue);
      expect(versionAllows('20', '21.0.0'), isFalse);
      expect(versionAllows('=20.11.1', '20.11.1'), isTrue);
      expect(versionAllows('=20.11.1', '20.11.2'), isFalse);
    });

    test('범위를 읽을 수 없으면 null', () {
      expect(versionAllows('최신', '22.3.0'), isNull);
      expect(versionAllows('^20', '22.3.0'), isNull);
      expect(versionAllows('', '22.3.0'), isNull);
    });
  });
}
