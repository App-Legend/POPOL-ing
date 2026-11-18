import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _marker = '__PPOLING_PATH__';
const _fallbackDirs = ['/opt/homebrew/bin', '/usr/local/bin'];

/// 터미널에서 쓰는 것과 같은 PATH. macOS 에서 아이콘으로 켠 앱은 PATH 가 `/usr/bin:/bin` 정도라
/// Homebrew·nvm 으로 설치한 `npm`·`docker` 를 못 찾는다.
///
/// 로그인 셸(`$SHELL -ilc`)을 띄워 PATH 만 받아 앞에 두고, 지금 PATH 와 Homebrew 경로를 뒤에 붙인다.
/// 셸이 [timeout] 안에 답하지 않거나 실패하면 뒤의 것만 쓴다. 예외를 던지지 않는다.
Future<String> loginShellPath({Map<String, String>? environment, Duration timeout = const Duration(seconds: 5)}) async {
  final env = environment ?? Platform.environment;
  final current = (env['PATH'] ?? '').split(':');
  final fromShell = await _askShell(env['SHELL'] ?? '/bin/zsh', timeout);
  final seen = <String>{};
  return [...fromShell, ...current, ..._fallbackDirs].where((d) => d.isNotEmpty && seen.add(d)).join(':');
}

Future<List<String>> _askShell(String shell, Duration timeout) async {
  try {
    // .zshrc 가 무언가 출력해도 표시 사이의 PATH 만 꺼낸다.
    final process = await Process.start(shell, ['-ilc', 'printf "\\n$_marker%s$_marker\\n" "\$PATH"']);
    unawaited(process.stdin.close());
    unawaited(process.stderr.drain<void>());
    final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    final text = await out.timeout(timeout, onTimeout: () {
      process.kill(ProcessSignal.sigkill); // 직접 띄운 셸이라 PID 로 멈춰도 된다
      return '';
    });
    final match = RegExp('$_marker(.*)$_marker').firstMatch(text);
    return match == null ? const [] : match.group(1)!.split(':');
  } on ProcessException {
    return const [];
  }
}
