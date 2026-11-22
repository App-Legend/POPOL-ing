import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_runner/src/process/windows_command.dart';

void main() {
  const comSpec = r'C:\Windows\System32\cmd.exe';
  const pathExt = '.COM;.EXE;.BAT;.CMD;.VBS;.JS';

  WindowsCommand resolve(List<String> command, {String path = r'C:\node;C:\tools', Set<String> files = const {}}) =>
      resolveWindowsCommand(command,
          path: path, pathExt: pathExt, comSpec: comSpec, exists: (f) => files.contains(f.toLowerCase()));

  test('npm 은 npm.cmd 를 찾아 cmd 로 감싸 실행한다', () {
    final c = resolve(['npm', 'run', 'dev'], files: {r'c:\node\npm.cmd'});
    expect(c, isA<RunCommand>());
    c as RunCommand;
    expect(c.executable, comSpec);
    expect(c.arguments, ['/d', '/c', r'C:\node\npm.cmd', 'run', 'dev']);
  });

  test('.exe 는 cmd 없이 찾은 경로로 바로 실행한다', () {
    final c = resolve(['node', 'server.js'], files: {r'c:\node\node.exe'}) as RunCommand;
    expect(c.executable, r'C:\node\node.exe');
    expect(c.arguments, ['server.js']);
  });

  test('PATH 앞쪽 폴더, 같은 폴더에선 PATHEXT 앞쪽 확장자가 먼저다', () {
    final c = resolve(['x'], files: {r'c:\tools\x.exe', r'c:\node\x.cmd', r'c:\node\x.exe'}) as RunCommand;
    expect(c.executable, r'C:\node\x.exe');
  });

  test('확장자를 적었으면 그 파일을 찾는다', () {
    final c = resolve(['npm.cmd', 'test'], files: {r'c:\node\npm.cmd'}) as RunCommand;
    expect(c.arguments, ['/d', '/c', r'C:\node\npm.cmd', 'test']);
  });

  test('경로를 적었으면 PATH 에서 찾지 않는다', () {
    final c = resolve([r'.\bin\run'], files: {r'.\bin\run.bat', r'c:\node\run.exe'}) as RunCommand;
    expect(c.arguments, ['/d', '/c', r'.\bin\run.bat']);
  });

  test('./gradlew 처럼 / 로 적은 경로도 \\ 로 바꿔 찾는다 (cmd 는 / 를 옵션으로 읽는다)', () {
    final c = resolve(['./gradlew', 'bootRun'], files: {r'.\gradlew.bat'}) as RunCommand;
    expect(c.arguments, ['/d', '/c', r'.\gradlew.bat', 'bootRun']);
  });

  test('PATHEXT 에 있어도 .js 같은 스크립트는 실행 대상이 아니다', () {
    final c = resolve(['tool'], files: {r'c:\node\tool.js'});
    expect(c, isA<RefuseCommand>().having((r) => r.exitCode, 'exitCode', 127));
  });

  test('없는 명령은 127 과 안내 문구', () {
    final c = resolve(['nope']) as RefuseCommand;
    expect(c.exitCode, 127);
    expect(c.message, contains('nope'));
  });

  test('비어 있는 PATH 칸은 건너뛴다', () {
    final c = resolve(['node'], path: r';C:\node;', files: {r'c:\node\node.exe'}) as RunCommand;
    expect(c.executable, r'C:\node\node.exe');
  });

  test('공백이 있는 경로의 .cmd 도 실행한다', () {
    final c = resolve(['npm'], path: r'C:\Program Files\nodejs', files: {r'c:\program files\nodejs\npm.cmd'});
    expect((c as RunCommand).arguments, ['/d', '/c', r'C:\Program Files\nodejs\npm.cmd']);
  });

  group('cmd 를 거치는 .cmd·.bat 은 cmd 가 해석할 인자를 거절한다', () {
    for (final arg in ['a&b', 'a|b', '%PATH%', 'a b', '"x"', 'a^b', '!x!', '(x)', '<x', '']) {
      test('인자 "$arg"', () {
        final c = resolve(['npm', arg], files: {r'c:\node\npm.cmd'});
        expect(c, isA<RefuseCommand>().having((r) => r.exitCode, 'exitCode', 1));
      });
    }

    test('경로에 괄호가 있어도 거절한다', () {
      final c = resolve(['npm'], path: r'C:\Program Files (x86)\nodejs', files: {r'c:\program files (x86)\nodejs\npm.cmd'});
      expect(c, isA<RefuseCommand>());
    });

    test('npm 범위 패키지(@scope/pkg)·옵션(--port=3000)은 허용한다', () {
      final c = resolve(['npm', 'i', '@scope/pkg', '--port=3000'], files: {r'c:\node\npm.cmd'});
      expect(c, isA<RunCommand>());
    });
  });

  test('.exe 는 cmd 를 거치지 않으니 특수문자 인자도 그대로 넘긴다', () {
    final c = resolve(['node', '-e', 'a && b'], files: {r'c:\node\node.exe'}) as RunCommand;
    expect(c.arguments, ['-e', 'a && b']);
  });
}
