import 'package:popoling_core/models.dart';

/// 실행할 명령 목록을 사람이 읽을 수 있는 문자열로 요약한다.
///
/// 사용자가 처음 열 때 '어떤 명령이 실행될지' 확인받기 위해 쓴다(받은 설정 파일 실행 전 확인).
String summarizeCommands(List<ServiceConfig> services) {
  if (services.isEmpty) return '실행할 항목이 없어요.';
  final lines = <String>[];
  for (final s in services) {
    lines.add('${s.id}: ${_oneLine(s)}');
  }
  return lines.join('\n');
}

String _oneLine(ServiceConfig s) {
  if (s is ProcessService) {
    return _processOneLine(s);
  }
  if (s is ComposeService) {
    final serviceList = s.services.isNotEmpty ? ' (${s.services.join(", ")})' : '';
    return 'Docker Compose 시작$serviceList (${s.file})';
  }
  if (s is RemoteService) {
    return '원격 연결 확인';
  }
  return '실행 준비 중';
}

String _processOneLine(ProcessService s) {
  var cmd = s.command.map(_quoteArgument).join(' ');
  final cwdNote = s.cwd == '.' ? '' : ' (작업 폴더: ${s.cwd})';
  final envNote = s.env.isEmpty ? '' : ' (환경변수: ${s.env.keys.join(", ")})';
  // 실행할 명령만 보여주고, 작업 폴더는 괄호로만 알려준다(실행 명령과 혼동 방지).
  return '$cmd$cwdNote$envNote';
}

/// 인자 하나를 사람이 읽을 수 있게 따옴표로 감싼다.
/// 줄바꿈·탭은 `\n`·`\t` 글자로 보여 준다. 남이 만든 설정에서 인자 속 줄바꿈이 다른 명령 줄처럼 보이지 않게.
String _quoteArgument(String arg) {
  if (arg.isEmpty) return '""';
  if (arg.contains(RegExp(r'[ "&;<>|()\\\n\r\t]'))) {
    final shown = arg.replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', r'\r').replaceAll('\t', r'\t');
    return '"$shown"';
  }
  return arg;
}
