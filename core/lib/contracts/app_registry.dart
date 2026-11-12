import 'package:flutter/widgets.dart';

/// 기능이 앱에 끼어드는 창구. 기능 패키지는 `void register(AppRegistry app)` 하나만 내보내고,
/// `app/` 이 그 함수를 불러 화면과 구현을 모은다.
///
/// - 진짜 구현: A (`app/`).
/// - 쓰는 곳: 모든 기능 패키지의 `register()`.
///
/// 지켜야 할 약속.
/// - `app/` 은 `core/fakes` 를 먼저 등록하고 기능을 나중에 등록한다. 같은 경로·같은 타입은 나중 것이 이긴다
///   (가짜 → 진짜 교체).
/// - [read] 는 등록이 다 끝난 뒤(화면을 그릴 때) 부른다. `register()` 안에서 바로 부르면 아직 교체 전일 수 있다.
abstract interface class AppRegistry {
  /// 화면 경로를 등록한다. 예: `app.route('/env', (_) => const EnvCheckScreen())`.
  void route(String path, WidgetBuilder builder);

  /// 계약 구현을 등록한다. 예: `app.provide<PortProbe>(RealPortProbe())`.
  void provide<T extends Object>(T service);

  /// 등록된 구현을 꺼낸다. 없으면 [StateError].
  T read<T extends Object>();
}
