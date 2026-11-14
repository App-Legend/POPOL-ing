import '../models/config_issue.dart';

/// 설정 Map 에서 값을 꺼내면서, 잘못된 곳을 경로와 함께 모은다.
///
/// 사용자가 한 번에 다 고칠 수 있도록 첫 문제에서 멈추지 않고 끝까지 읽는다.
/// 패키지 안에서만 쓴다.
class MapReader {
  final List<ConfigIssue> issues = [];

  void report(String path, String message) => issues.add(ConfigIssue(path: path, message: message));

  static String child(String parent, String key) => parent.isEmpty ? key : '$parent.$key';

  static String item(String parent, int index) => '$parent[$index]';

  /// 글자 키 Map 으로 바꾼다. YAML 라이브러리는 키 타입이 dynamic 인 Map 을 주기 때문이다.
  Map<String, Object?>? asMap(Object? value, String path) {
    if (value is Map) {
      return {for (final e in value.entries) '${e.key}': e.value};
    }
    report(path, '항목 묶음으로 적어 주세요. 예: { key: value }');
    return null;
  }

  /// [allowed] 에 없는 키를 알린다. 이름 오타를 잡기 위해서다.
  void onlyKeys(Map<String, Object?> map, String path, Set<String> allowed) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        report(child(path, key), '알 수 없는 항목이에요. 이름에 오타가 없는지 확인해 주세요.');
      }
    }
  }

  String? string(Map<String, Object?> map, String key, String parent, {bool required = false}) {
    final path = child(parent, key);
    final value = _get(map, key, path, required);
    if (value == null) {
      return null;
    }
    final text = scalarText(value);
    if (text == null) {
      report(path, '글자로 적어 주세요.');
      return null;
    }
    if (required && text.trim().isEmpty) {
      report(path, '비워 둘 수 없어요.');
      return null;
    }
    return text;
  }

  int? integer(Map<String, Object?> map, String key, String parent, {bool required = false, int? min, int? max}) {
    final path = child(parent, key);
    final value = _get(map, key, path, required);
    if (value == null) {
      return null;
    }
    return _intAt(value, path, min: min, max: max);
  }

  /// true/false 를 읽는다. YAML 의 "yes" 같은 글자는 받지 않는다.
  bool? boolean(Map<String, Object?> map, String key, String parent) {
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! bool) {
      report(child(parent, key), 'true 또는 false 로 적어 주세요.');
      return null;
    }
    return value;
  }

  /// 초 단위 숫자를 읽는다. 소수도 된다. 예: `timeout: 90`, `interval: 0.5`
  Duration? seconds(Map<String, Object?> map, String key, String parent) {
    final path = child(parent, key);
    final value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! num || value <= 0) {
      report(path, '0보다 큰 초 단위 숫자로 적어 주세요. 예: 60');
      return null;
    }
    return Duration(milliseconds: (value * 1000).round());
  }

  List<Object?>? list(Map<String, Object?> map, String key, String parent, {bool required = false}) {
    final path = child(parent, key);
    final value = _get(map, key, path, required);
    if (value == null) {
      return null;
    }
    if (value is List) {
      return value;
    }
    report(path, '목록으로 적어 주세요. 예: [a, b]');
    return null;
  }

  List<String> strings(Map<String, Object?> map, String key, String parent, {bool required = false}) {
    final path = child(parent, key);
    final values = list(map, key, parent, required: required);
    if (values == null) {
      return const [];
    }
    final result = <String>[];
    for (final (i, value) in values.indexed) {
      final text = scalarText(value);
      if (text == null || text.isEmpty) {
        report(item(path, i), '글자로 적어 주세요.');
      } else {
        result.add(text);
      }
    }
    return result;
  }

  List<int> ints(Map<String, Object?> map, String key, String parent, {int? min, int? max}) {
    final path = child(parent, key);
    final values = list(map, key, parent);
    if (values == null) {
      return const [];
    }
    final result = <int>[];
    for (final (i, value) in values.indexed) {
      final number = _intAt(value, item(path, i), min: min, max: max);
      if (number != null) {
        result.add(number);
      }
    }
    return result;
  }

  /// 키·값이 모두 글자인 묶음을 읽는다. 예: `env`, `links`
  Map<String, String> stringMap(Map<String, Object?> map, String key, String parent) {
    final path = child(parent, key);
    final value = map[key];
    if (value == null) {
      return const {};
    }
    final entries = asMap(value, path);
    if (entries == null) {
      return const {};
    }
    final result = <String, String>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      final text = scalarText(value);
      if (text == null) {
        report(child(path, key), '글자로 적어 주세요.');
      } else {
        result[key] = text;
      }
    }
    return result;
  }

  /// 글자·숫자·참거짓은 글자로 받는다(YAML 은 `PORT: 8080` 의 값을 숫자로 읽는다). 나머지는 null.
  static String? scalarText(Object? value) => switch (value) {
        String s => s,
        num n => '$n',
        bool b => '$b',
        _ => null,
      };

  Object? _get(Map<String, Object?> map, String key, String path, bool required) {
    final value = map[key];
    if (value == null && required) {
      report(path, '꼭 적어야 하는 항목이에요.');
    }
    return value;
  }

  int? _intAt(Object? value, String path, {int? min, int? max}) {
    if (value is! int) {
      report(path, '정수로 적어 주세요.');
      return null;
    }
    if ((min != null && value < min) || (max != null && value > max)) {
      report(path, '${min ?? ''}~${max ?? ''} 사이의 숫자로 적어 주세요.');
      return null;
    }
    return value;
  }
}
