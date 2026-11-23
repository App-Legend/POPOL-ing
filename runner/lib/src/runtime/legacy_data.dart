import 'dart:io';

/// 앱 이름을 ppoling 에서 popoling 으로 바꾸기(2026-11-22) 전의 앱 데이터 폴더.
/// 이름은 마지막 두 칸(macOS 번들 ID, Windows 회사\제품)에만 들어 있으니 거기서만 바꾼다.
Directory legacyDataDir(Directory now) {
  final parts = now.path.split(Platform.pathSeparator);
  for (var i = parts.length - 2; i < parts.length; i++) {
    if (i >= 0) parts[i] = parts[i].replaceAll('popoling', 'ppoling');
  }
  return Directory(parts.join(Platform.pathSeparator));
}

/// 옛 앱 데이터 폴더(등록한 프로젝트·실행 기록·로그)를 [now] 로 옮긴다. [now] 가 이미 있으면 두고, 실패해도 앱은 시작한다.
Future<void> moveLegacyDataDir(Directory now) async {
  try {
    final legacy = legacyDataDir(now);
    if (now.existsSync() || !legacy.existsSync()) return;
    await now.parent.create(recursive: true);
    await legacy.rename(now.path);
  } on FileSystemException {
    // 옮기지 못하면 빈 폴더로 시작한다. 옛 폴더는 그대로 남아 있다
  }
}
