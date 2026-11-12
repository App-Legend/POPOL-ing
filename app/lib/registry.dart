import 'package:flutter/widgets.dart';
import 'package:ppoling_core/contracts.dart';

/// [AppRegistry] 의 구현. 같은 경로·같은 타입은 나중에 등록한 것으로 덮어쓴다.
class Registry implements AppRegistry {
  final Map<String, WidgetBuilder> routes = {};
  final Map<Type, Object> _services = {};

  @override
  void route(String path, WidgetBuilder builder) => routes[path] = builder;

  @override
  void provide<T extends Object>(T service) => _services[T] = service;

  @override
  T read<T extends Object>() {
    final service = _services[T];
    if (service == null) {
      throw StateError('$T 구현이 등록되지 않았습니다. app/lib/main.dart 의 등록 순서를 확인하세요.');
    }
    return service as T;
  }
}
