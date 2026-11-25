/// Windows: 환경 점검할 명령을 PATH·PATHEXT 로 찾는다. OS별 코드는 이 파일에만 둔다.
///
/// `Process.run` 은 `.exe` 만 찾아서 `npm`(실제로는 `npm.cmd`)을 못 띄운다.
/// `.cmd`·`.bat` 은 `cmd.exe` 를 거쳐야 하는데, cmd 는 경로 속 `&`·`(` 등을 해석해 다른 명령이 끼어들 수 있다.
/// 그래서 그런 글자가 든 경로의 `.cmd`·`.bat` 은 실행하지 않는다(`runner/` 의 Windows 실행기와 같은 규칙).
library;

const _runnable = {'.com', '.exe', '.bat', '.cmd'};

/// cmd 가 따옴표 안에서도 특별하게 보는 글자.
final _unsafePath = RegExp(r'["&<>()@^|%!]');

/// [cli] 를 [path](`;` 로 나눈 폴더들)에서 [pathExt] 순서로 찾아 `[실행 파일, ...인자]` 를 돌려준다.
///
/// - 못 찾으면 null(미설치).
/// - 찾았지만 cmd 를 거쳐야 하고 경로가 안전하지 않으면 [FormatException](이유가 메시지).
///
/// [args] 는 점검기가 정한 고정 값(`--version` 등)만 넘긴다.
List<String>? resolveWindowsCli(
  String cli,
  List<String> args, {
  required String path,
  required String pathExt,
  required String comSpec,
  required bool Function(String file) exists,
}) {
  final exts = pathExt.split(';').map((e) => e.toLowerCase()).where(_runnable.contains).toList();
  for (final dir in path.split(';').where((d) => d.isNotEmpty)) {
    final base = dir.endsWith(r'\') ? dir : '$dir\\';
    for (final ext in exts) {
      final file = '$base$cli$ext';
      if (!exists(file)) continue;
      if (ext != '.bat' && ext != '.cmd') return [file, ...args];
      if (_unsafePath.hasMatch(file)) {
        throw FormatException('이 위치의 .cmd·.bat 은 점검할 수 없어요(경로에 괄호 같은 특수문자가 있어요): $file');
      }
      return [comSpec, '/d', '/c', file, ...args]; // /d: AutoRun 레지스트리 명령을 끼우지 않는다
    }
  }
  return null;
}
