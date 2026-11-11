/// 설정 파일(ppoling.yaml)에서 고쳐야 할 곳 하나.
class ConfigIssue {
  const ConfigIssue({required this.path, required this.message, this.line});

  /// 문제가 있는 위치. 예: `services[1].dependsOn[0]`. 파일 전체에 대한 문제면 빈 글자.
  final String path;

  /// 화면에 그대로 보여줄 안내 문장.
  final String message;

  /// ppoling.yaml 의 줄 번호(1부터). 알 수 없으면 null.
  final int? line;

  @override
  String toString() {
    final where = path.isEmpty ? '(파일 전체)' : path;
    return line == null ? '$where: $message' : '$where ($line번째 줄): $message';
  }
}
