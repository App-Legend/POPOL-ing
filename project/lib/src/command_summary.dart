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
  final prefix = s.cwd == '.' ? '' : '${s.cwd}/';
  final cwdNote = s.cwd == '.' ? '' : ' (작업 폴더: ${s.cwd})';
  final envNote = s.env.isEmpty ? '' : ' (환경변수: ${s.env.keys.join(", ")})';
  // cwd가 있고 명령이 ./로 시작하면, cwd prefix와 중복되는 ./만 제거한다
  if (s.cwd != '.' && cmd.startsWith('./')) {
    cmd = cmd.substring(2);
  }
  return '$prefix$cmd$cwdNote$envNote';
}

/// 인자 하나를 사람이 읽을 수 있게 따옴표로 감싼다.
String _quoteArgument(String arg) {
  if (arg.contains(RegExp(r'[ "&;<>|()]')) || arg.contains(RegExp(r'[\\]'))) {
    return '"${arg.replaceAll('"', '\\"')}"';
  }
  return arg;
}
