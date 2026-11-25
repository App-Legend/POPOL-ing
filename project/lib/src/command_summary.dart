import 'package:popoling_core/models.dart';

/// 실행할 명령 목록을 사람이 읽을 수 있는 문자열로 요약한다.
///
/// 사용자가 처음 열 때 '어떤 명령이 실행될지' 확인받기 위해 쓴다(FR-13).
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
    return 'Docker Compose 시작${s.services.isNotEmpty ? ' (${s.services.join(", ")})' : ''}';
  }
  if (s is RemoteService) {
    return '원격 연결 확인';
  }
  return '실행 준비 중';
}

String _processOneLine(ProcessService s) {
  final cmd = s.command.join(' ');
  final prefix = s.cwd == '.' ? '' : '${s.cwd}/';
  final cwdNote = s.cwd == '.' ? '' : ' (작업 폴더: ${s.cwd})';
  return '$prefix$cmd$cwdNote';
}
