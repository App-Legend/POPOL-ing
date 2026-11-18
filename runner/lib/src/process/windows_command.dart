/// Windows 에서 실행할 명령을 정한다. `npm` 처럼 확장자 없이 적은 이름을 PATH·PATHEXT 로 찾는다.
///
/// `Process.start` 는 `.exe` 만 찾아서 `npm`(실제로는 `npm.cmd`)을 못 띄운다.
/// `.cmd`·`.bat` 은 `cmd.exe` 를 거쳐야 실행되는데, 그러면 cmd 가 인자의 `&`·`%` 등을 해석해
/// 다른 명령이 끼어들 수 있다. 그래서 cmd 가 해석할 글자가 든 인자는 실행하지 않고 거절한다.
library;

/// [resolveWindowsCommand] 의 결과.
sealed class WindowsCommand {}

/// [executable] 을 [arguments] 로 띄운다.
class RunCommand implements WindowsCommand {
  const RunCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

/// 띄우지 않는다. 띄운 것처럼 [message] 를 stderr 로, [exitCode] 를 종료 코드로 알린다.
class RefuseCommand implements WindowsCommand {
  const RefuseCommand(this.message, this.exitCode);

  final String message;
  final int exitCode;
}

const _runnable = {'.com', '.exe', '.bat', '.cmd'};

/// cmd 가 따옴표 안에서도 특별하게 보는 글자. 경로에 있으면 cmd 가 따옴표를 벗겨 버린다.
final _unsafePath = RegExp(r'["&<>()@^|%!]');

/// 따옴표 없이 넘기는 인자에서 cmd 가 해석하는 글자와 공백(공백이 있으면 따옴표가 붙어 경로 따옴표가 깨진다).
final _unsafeArg = RegExp(r'[\s"&<>()^|%!]');

/// [command] 의 첫 칸을 [path](`;` 로 나눈 폴더들)·[pathExt] 로 찾는다. 경로를 적었으면 그 경로에서만 찾는다.
///
/// 확장자를 적지 않았으면 PATHEXT 순서로 붙여 본다. 실행 대상은 `.com`·`.exe`·`.bat`·`.cmd` 뿐이다.
// shortcut: cmd 와 달리 작업 폴더를 PATH 보다 먼저 찾지 않는다. 필요하면 `.\이름` 으로 적게 안내한다.
WindowsCommand resolveWindowsCommand(
  List<String> command, {
  required String path,
  required String pathExt,
  required String comSpec,
  required bool Function(String file) exists,
}) {
  final name = command.first.replaceAll('/', r'\'); // cmd 는 경로 속 / 를 옵션 시작으로 읽는다
  final found = _find(name, path: path, pathExt: pathExt, exists: exists);
  if (found == null) return RefuseCommand('명령을 찾을 수 없어요: $name', 127);

  final args = command.sublist(1);
  if (!_isBatch(found)) return RunCommand(found, args);
  if (_unsafePath.hasMatch(found)) {
    return RefuseCommand('이 위치의 .cmd·.bat 은 실행할 수 없어요(경로에 괄호 같은 특수문자가 있어요): $found', 1);
  }
  for (final a in args) {
    if (a.isEmpty || _unsafeArg.hasMatch(a)) {
      return RefuseCommand('.cmd·.bat 명령에는 빈 값이나 공백, & | % ! ^ ( ) < > " 가 든 값을 넘길 수 없어요: "$a"', 1);
    }
  }
  // /d: 자동 실행(AutoRun) 레지스트리 명령을 끼우지 않는다.
  return RunCommand(comSpec, ['/d', '/c', found, ...args]);
}

String? _find(String name, {required String path, required String pathExt, required bool Function(String) exists}) {
  final hasDir = name.contains(RegExp(r'[\\:]'));
  final dirs = hasDir ? [''] : path.split(';').where((d) => d.isNotEmpty).map((d) => d.endsWith(r'\') ? d : '$d\\');
  final ext = _ext(name);
  final exts = _runnable.contains(ext)
      ? ['']
      : pathExt.split(';').map((e) => e.toLowerCase()).where(_runnable.contains).toList();
  for (final dir in dirs) {
    for (final e in exts) {
      final file = '$dir$name$e';
      if (exists(file)) return file;
    }
  }
  return null;
}

String _ext(String name) {
  final base = name.split(r'\').last;
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? '' : base.substring(dot).toLowerCase();
}

bool _isBatch(String file) => const {'.bat', '.cmd'}.contains(_ext(file));
