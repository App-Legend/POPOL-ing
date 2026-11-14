import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppoling_project/src/about_defaults.dart';

void main() {
  group('readmeFirstParagraph', () {
    test('제목·배지·이미지를 건너뛰고 첫 문단을 한 줄로 만든다', () {
      const readme = '''
# My Team Project
[![CI](https://x/badge.svg)](https://x)
<p align="center"><img src="logo.png"></p>

동아리 행사 **예약** 웹서비스입니다.
[Spring Boot](https://spring.io)와 `React`로 만들었어요.

## 설치
npm install
''';
      expect(readmeFirstParagraph(readme), '동아리 행사 예약 웹서비스입니다. Spring Boot와 React로 만들었어요.');
    });

    test('밑줄 제목(===)과 코드 블록은 건너뛴다', () {
      const readme = 'Title\n=====\n\n```\ncode here\n```\n\n첫 문단\n';
      expect(readmeFirstParagraph(readme), '첫 문단');
    });

    test('본문이 없으면 null, 너무 길면 줄인다', () {
      expect(readmeFirstParagraph('# 제목만\n\n## 또 제목\n'), isNull);
      final long = readmeFirstParagraph('가' * 500)!;
      expect(long.length, 200);
      expect(long.endsWith('…'), isTrue);
    });
  });

  group('원격 주소', () {
    test('.git/config 에서 origin 의 url 만 찾는다', () {
      const config = '''
[core]
\turl = not-this
[remote "upstream"]
\turl = https://github.com/other/repo.git
[remote "origin"]
\turl = git@github.com:example/my-team-project.git
\tfetch = +refs/heads/*:refs/remotes/origin/*
''';
      expect(gitOriginUrl(config), 'git@github.com:example/my-team-project.git');
      expect(gitOriginUrl('[core]\n'), isNull);
    });

    test('브라우저 주소로 바꾸고 아이디·토큰은 지운다', () {
      expect(repoWebUrl('git@github.com:example/repo.git'), 'https://github.com/example/repo');
      expect(repoWebUrl('https://user:ghp_secret@github.com/example/repo.git'), 'https://github.com/example/repo');
      expect(repoWebUrl('ssh://git@gitlab.com:22/group/sub/repo.git'), 'https://gitlab.com/group/sub/repo');
      expect(repoWebUrl('https://github.com/example/repo/'), 'https://github.com/example/repo');
      expect(repoWebUrl('/Users/me/repos/local.git'), isNull);
      expect(repoWebUrl('file:///Users/me/repo'), isNull);
    });
  });

  group('suggestAbout', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('ppoling_about_test'));
    tearDown(() => dir.delete(recursive: true));

    test('README 와 Git 원격이 있으면 설명과 저장소 링크를 채운다 (AT-15)', () async {
      await File('${dir.path}/README.md').writeAsString('# 제목\n\n동아리 예약 서비스\n');
      await Directory('${dir.path}/.git').create();
      await File('${dir.path}/.git/config').writeAsString('[remote "origin"]\n\turl = git@github.com:ex/app.git\n');

      final about = await suggestAbout(dir.path);
      expect(about.summary, '동아리 예약 서비스');
      expect(about.links, {'repo': 'https://github.com/ex/app'});
    });

    test('워크트리처럼 .git 이 파일이면 가리키는 폴더의 config 를 읽는다', () async {
      final real = await Directory('${dir.path}/real-git').create();
      await File('${real.path}/config').writeAsString('[remote "origin"]\n\turl = https://github.com/ex/wt.git\n');
      final work = await Directory('${dir.path}/work').create();
      await File('${work.path}/.git').writeAsString('gitdir: ${real.path}\n');

      expect((await suggestAbout(work.path)).links, {'repo': 'https://github.com/ex/wt'});
    });

    test('README·Git 이 없거나 README 가 UTF-8 이 아니어도 빈 값으로 돌려준다', () async {
      final empty = await suggestAbout(dir.path);
      expect(empty.summary, isNull);
      expect(empty.links, isEmpty);

      await File('${dir.path}/readme').writeAsBytes([0xff, 0xfe, 0x00]);
      expect((await suggestAbout(dir.path)).summary, isNull);
    });
  });
}
