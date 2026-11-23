import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:popoling_core/contracts.dart';

/// 프로젝트 폴더의 Git 상태.
class GitStatus {
  const GitStatus({required this.branch, required this.changed, this.upstream, this.ahead = 0, this.behind = 0});

  /// 지금 브랜치. 브랜치가 아니면(detached HEAD) null.
  final String? branch;

  /// 커밋하지 않은 변경 파일 수. 새로 만든 파일도 센다.
  final int changed;

  /// 비교하는 원격 브랜치(예: `origin/dev`). 없으면 null 이고 [ahead]·[behind] 는 뜻이 없다.
  final String? upstream;
  final int ahead;

  /// 원격보다 뒤처진 커밋 수. 마지막으로 원격을 확인한 때 기준.
  final int behind;
}

/// git 명령을 불러 상태를 읽고, 안전할 때만 최신 코드를 받는다(FR-19). 예외를 던지지 않는다.
///
/// - 커밋하지 않은 변경이나 로컬 커밋을 덮어쓰지 않는다. stash·reset·병합 커밋은 만들지 않는다.
/// - 로그인을 묻는 창을 띄우지 않고, 저장소에 든 Git 훅을 실행하지 않는다.
/// - git 의 오류 글은 주소에 든 토큰이 섞일 수 있어 화면에 옮기지 않는다.
class GitAdapter {
  GitAdapter({this.environment = _noEnvironment, this.timeout = const Duration(seconds: 30)});

  /// git 에 더 줄 환경 변수(PATH).
  final Future<Map<String, String>> Function() environment;

  /// 원격을 기다리는 시간.
  final Duration timeout;

  Future<Map<String, String>>? _env;

  /// 같은 폴더에서 fetch 가 겹치면 서로 잠금에 걸리니 차례로 한다.
  final _queue = <String, Future<void>>{};

  static Future<Map<String, String>> _noEnvironment() async => const {};

  /// Git 이 없거나 저장소가 아니면 null.
  Future<GitStatus?> status(String folder) async {
    try {
      if (!_inRepository(folder)) return null;
      final out = await _git(folder, ['status', '--porcelain=v2', '--branch']);
      return out == null ? null : _parseStatus(out);
    } on Object {
      return null;
    }
  }

  /// 원격을 한 번 확인한다. 작업 중인 파일은 바뀌지 않는다. 실패하면 false.
  Future<bool> fetch(String folder) => _inTurn(folder, () => _fetch(folder)).catchError((_) => false);

  /// 안전하게 받을 수 있으면 받는다. 저장소가 아니면 null.
  Future<PullResult?> pull(String folder) async {
    try {
      return await _inTurn(folder, () => _pull(folder));
    } on Object {
      return _skip('Git 을 실행하지 못했어요.');
    }
  }

  Future<PullResult?> _pull(String folder) async {
    final before = await status(folder);
    if (before == null) return null;
    if (before.branch == null) return _skip('브랜치가 아닌 커밋을 보고 있어요.');
    if (before.changed > 0) return _skip('커밋하지 않은 변경 ${before.changed}개가 있어요.');
    if (!await _hasUpstreamConfig(folder, before.branch!)) return _skip('이 브랜치에 연결된 원격 브랜치가 없어요.');
    if (!await _fetch(folder)) return _skip('원격 저장소에 접속할 수 없어요.');

    final now = await status(folder); // 기다리는 사이 바뀌었을 수 있다
    if (now == null || now.upstream == null) return _skip('연결된 원격 브랜치를 찾을 수 없어요.');
    if (now.branch != before.branch || now.changed > 0) return _skip('확인하는 사이 저장소가 바뀌었어요.');
    if (now.behind == 0) {
      // '최신'이라고 하지 않는다. 연결된 브랜치하고만 비교했고, 내가 앞서 있을 수도 있다.
      final mine = now.ahead > 0 ? ' 올리지 않은 내 커밋 ${now.ahead}개를 포함해 실행했어요.' : '';
      return PullResult(outcome: ItemOutcome.ok, message: '${now.upstream}에서 받을 새 커밋이 없어요.$mine');
    }
    if (now.ahead > 0) return _skip('원격에 없는 내 커밋 ${now.ahead}개가 있어 바로 합칠 수 없어요.');

    // 확인한 커밋과 받는 커밋이 같도록 번호로 고정한다. pull 을 다시 부르면 그사이 올라온 것이 섞인다.
    final target = (await _git(folder, ['rev-parse', '--verify', '@{upstream}^{commit}']))?.trim();
    if (target == null) return _skip('연결된 원격 브랜치를 찾을 수 없어요.');
    final config = await _git(folder, ['diff', '--no-ext-diff', '--no-renames', '--name-only', 'HEAD', target, '--', ':(icase)popoling.yaml']);
    if (config == null) return _skip('받을 내용을 확인하지 못했어요.');
    // shortcut: 설정을 다시 읽는 기능(#35)이 없어 바뀐 명령을 확인받을 수 없다. 생기면 확인 창으로 바꾼다.
    if (config.trim().isNotEmpty) return _skip('최신 코드에서 popoling.yaml 이 바뀌었어요. 실행 명령을 확인한 뒤 직접 받아 주세요.');
    // 파일을 바꾸는 도중에 멈추면 저장소가 깨지니 시간 제한을 두지 않는다.
    final merged = await _git(folder, ['merge', '--ff-only', '--no-autostash', '--quiet', target]);
    return merged == null
        ? _skip('최신 코드를 합치지 못했어요.')
        : PullResult(outcome: ItemOutcome.ok, message: '${now.upstream}에서 새 커밋 ${now.behind}개를 받았어요.');
  }

  static PullResult _skip(String reason) =>
      PullResult(outcome: ItemOutcome.skipped, message: '$reason 지금 코드로 실행했어요.');

  Future<bool> _fetch(String folder) async =>
      _inRepository(folder) &&
      await _git(folder, ['fetch', '--quiet', '--no-recurse-submodules'], limit: timeout) != null;

  Future<bool> _hasUpstreamConfig(String folder, String branch) async =>
      await _git(folder, ['config', '--get', 'branch.$branch.merge']) != null;

  Future<T> _inTurn<T>(String folder, Future<T> Function() action) {
    final result = (_queue[folder] ?? Future<void>.value()).then((_) => action());
    _queue[folder] = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// `.git` 이 없으면 git 을 부르지 않는다. 개발 도구가 없는 macOS 는 git 을 부르면 설치 창이 뜬다.
  static bool _inRepository(String folder) {
    for (var dir = Directory(folder).absolute;; dir = dir.parent) {
      if (FileSystemEntity.typeSync('${dir.path}${Platform.pathSeparator}.git') != FileSystemEntityType.notFound) return true;
      if (dir.parent.path == dir.path) return false;
    }
  }

  /// stdout. 실패하거나 [limit] 을 넘기면 null.
  Future<String?> _git(String folder, List<String> args, {Duration? limit}) async {
    final process = await Process.start(
      'git',
      ['--no-optional-locks', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', ...args],
      workingDirectory: folder,
      environment: {
        ...await (_env ??= environment()),
        'LC_ALL': 'C',
        'GIT_TERMINAL_PROMPT': '0',
        'GCM_INTERACTIVE': 'never',
        'GIT_ASKPASS': '',
        'SSH_ASKPASS_REQUIRE': 'never',
      },
    );
    process.stdin.close().ignore();
    process.stderr.drain<void>().ignore();
    final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    out.ignore();
    Future<String?> result() async => await process.exitCode == 0 ? await out : null;
    if (limit == null) return result();
    return result().timeout(limit, onTimeout: () {
      process.kill(); // 직접 띄운 git 이라 멈춰도 된다
      return null;
    });
  }

  static GitStatus _parseStatus(String out) {
    String? branch, upstreamName;
    var changed = 0, compared = false, ahead = 0, behind = 0;
    for (final line in const LineSplitter().convert(out)) {
      if (line.startsWith('# branch.head ')) {
        final head = line.substring('# branch.head '.length);
        branch = head == '(detached)' ? null : head;
      } else if (line.startsWith('# branch.upstream ')) {
        upstreamName = line.substring('# branch.upstream '.length);
      } else if (RegExp(r'^# branch\.ab \+(\d+) -(\d+)$').firstMatch(line) case final m?) {
        compared = true; // 원격 브랜치가 지워졌으면 이 줄이 없다
        ahead = int.parse(m[1]!);
        behind = int.parse(m[2]!);
      } else if (line.isNotEmpty && !line.startsWith('#')) {
        changed++;
      }
    }
    return GitStatus(branch: branch, changed: changed, upstream: compared ? upstreamName : null, ahead: ahead, behind: behind);
  }
}
