import 'dart:io';

import 'package:ppoling_core/models.dart';

/// 프로젝트를 등록할 때 채워 줄 소개 기본값(FR-15, AT-15).
///
/// README 첫 문단 → [About.summary], Git 원격 origin 주소 → `links['repo']`.
/// 찾지 못한 값은 비워 둔다. 프로젝트 추가 화면이 칸을 미리 채우는 데 쓰고, 사용자가 고칠 수 있다.
/// git 명령은 실행하지 않고 `.git/config` 파일만 읽는다.
Future<About> suggestAbout(String folderPath) async {
  final summary = await _readmeSummary(folderPath);
  final repo = await _originUrl(folderPath);
  return About(summary: summary, links: {'repo': ?repo});
}

const _summaryMaxLength = 200;

Future<String?> _readmeSummary(String folderPath) async {
  final File readme;
  try {
    final files = await Directory(folderPath).list().where((e) => e is File).cast<File>().toList();
    final found = [
      for (final name in const ['readme.md', 'readme.markdown', 'readme.txt', 'readme'])
        ...files.where((f) => _baseName(f.path).toLowerCase() == name),
    ];
    if (found.isEmpty) return null;
    readme = found.first;
  } on FileSystemException {
    return null;
  }
  final String text;
  try {
    text = await readme.readAsString();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null; // UTF-8 이 아닌 파일
  }
  return readmeFirstParagraph(text);
}

/// README 본문에서 제목·배지·이미지·HTML·코드 블록을 건너뛴 첫 문단을 한 줄로 돌려준다. 없으면 null.
String? readmeFirstParagraph(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final paragraph = <String>[];
  var inCode = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inCode = !inCode;
      if (paragraph.isNotEmpty) break;
      continue;
    }
    final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
    final setextHeading = line.isNotEmpty && RegExp(r'^(=+|-+)$').hasMatch(next);
    final skip = inCode ||
        line.startsWith('#') ||
        line.startsWith('<') ||
        line.startsWith('![') ||
        line.startsWith('[![') ||
        line.startsWith('>') ||
        RegExp(r'^(=+|-+|\*+|_+)$').hasMatch(line) ||
        setextHeading;
    if (line.isEmpty || skip) {
      if (paragraph.isNotEmpty) break;
      if (setextHeading) i++; // 밑줄 줄도 건너뛴다
      continue;
    }
    paragraph.add(line);
  }
  if (paragraph.isEmpty) return null;
  final plain = paragraph
      .join(' ')
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!) // [글자](주소) → 글자
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.isEmpty) return null;
  return plain.length <= _summaryMaxLength ? plain : '${plain.substring(0, _summaryMaxLength - 1)}…';
}

Future<String?> _originUrl(String folderPath) async {
  final sep = Platform.pathSeparator;
  var gitDir = '$folderPath$sep.git';
  try {
    // 워크트리·서브모듈은 .git 이 "gitdir: <경로>" 한 줄짜리 파일이다.
    final dotGit = File(gitDir);
    if (await dotGit.exists()) {
      final pointer = RegExp(r'^gitdir:\s*(.+)$', multiLine: true).firstMatch(await dotGit.readAsString());
      if (pointer == null) return null;
      final target = pointer[1]!.trim();
      gitDir = File(target).isAbsolute ? target : '$folderPath$sep$target';
    }
    final config = File('$gitDir${sep}config');
    if (!await config.exists()) return null;
    final url = gitOriginUrl(await config.readAsString());
    return url == null ? null : repoWebUrl(url);
  } on FileSystemException {
    return null;
  }
}

/// `.git/config` 내용에서 `[remote "origin"]` 의 url 을 찾는다. 없으면 null.
String? gitOriginUrl(String gitConfig) {
  var inOrigin = false;
  for (final raw in gitConfig.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inOrigin = RegExp(r'^\[remote\s+"origin"\]$').hasMatch(line);
      continue;
    }
    if (!inOrigin) continue;
    final m = RegExp(r'^url\s*=\s*(.+)$').firstMatch(line);
    if (m != null) return m[1]!.trim();
  }
  return null;
}

/// 원격 주소를 브라우저에서 열 수 있는 주소로 바꾼다. 주소에 든 아이디·토큰은 지운다(화면·ppoling.yaml 에 남지 않게).
///
/// `git@github.com:a/b.git` → `https://github.com/a/b`, `https://user:token@github.com/a/b.git` → `https://github.com/a/b`.
/// 로컬 경로처럼 웹 주소로 바꿀 수 없으면 null.
String? repoWebUrl(String remote) {
  final scp = RegExp(r'^(?:[^@/\s]+@)?([^:/\s]+):(?!//)(.+)$').firstMatch(remote);
  String host;
  String path;
  if (scp != null && !remote.contains('://')) {
    host = scp[1]!;
    path = scp[2]!;
  } else {
    final uri = Uri.tryParse(remote);
    if (uri == null || !const {'https', 'http', 'ssh', 'git'}.contains(uri.scheme) || uri.host.isEmpty) {
      return null;
    }
    host = uri.host;
    path = uri.path;
  }
  path = path.replaceAll(RegExp(r'^/+|/+$'), '').replaceAll(RegExp(r'\.git$'), '');
  if (path.isEmpty) return null;
  return 'https://$host/$path';
}

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;
