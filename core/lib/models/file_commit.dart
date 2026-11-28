/// 파일 하나를 마지막으로 바꾼 커밋. `FileHistory.lastCommit` 의 결과.
class FileCommit {
  const FileCommit({required this.shortHash, required this.author, required this.committedAt, required this.subject});

  /// 짧은 커밋 해시. 예: `4d6153a`
  final String shortHash;

  /// 작성자 이름. 이메일은 담지 않는다.
  final String author;

  /// 커밋 시각.
  final DateTime committedAt;

  /// 커밋 메시지 첫 줄.
  final String subject;
}
