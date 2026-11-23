import 'dart:convert';

/// 앱이 중계(`popoling-relay`) stdin 에 한 줄로 넘기는 요청. 비밀값을 명령 인자로 넘기지 않으려고 stdin 을 쓴다.
class RelayRequest {
  RelayRequest({
    required this.command,
    required this.logFile,
    required this.secrets,
    this.jobName,
    this.maxBytes = 10 * 1024 * 1024,
    this.keep = 3,
  });

  /// 띄울 명령. 첫 칸은 PATH 에서 찾는다(Windows 는 앱이 미리 찾아 둔 실행 파일).
  final List<String> command;

  final String logFile;

  /// 로그에서 가릴 `.env` 값.
  final List<String> secrets;

  /// Windows: 앱이 만든 이름 붙은 Job. 중계가 핸들을 쥐고 있어야 앱이 꺼진 뒤에도 이름으로 다시 열린다.
  final String? jobName;

  final int maxBytes;
  final int keep;

  String encode() => jsonEncode({
        'command': command,
        'logFile': logFile,
        'secrets': secrets,
        if (jobName != null) 'jobName': jobName,
        'maxBytes': maxBytes,
        'keep': keep,
      });

  static RelayRequest decode(String line) {
    final j = jsonDecode(line) as Map<String, dynamic>;
    return RelayRequest(
      command: (j['command'] as List).cast<String>(),
      logFile: j['logFile'] as String,
      secrets: (j['secrets'] as List).cast<String>(),
      jobName: j['jobName'] as String?,
      maxBytes: j['maxBytes'] as int,
      keep: j['keep'] as int,
    );
  }
}
