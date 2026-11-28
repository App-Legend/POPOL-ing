import 'dart:convert';
import 'dart:io';

/// 홈 묶음(FR-14). 팀과 나누지 않는 개인 정리라 `popoling.yaml` 이 아니라 앱 데이터에 둔다.
enum HomeGroup {
  team('팀'),
  personal('개인'),
  company('회사');

  const HomeGroup(this.label);

  final String label;
}

/// 프로젝트 하나의 홈 정리: 묶음과 고정 여부.
class HomePlacement {
  const HomePlacement({this.group, this.pinned = false});

  static const none = HomePlacement();

  final HomeGroup? group;
  final bool pinned;

  bool get isEmpty => group == null && !pinned;
}

/// 홈 묶음·고정 저장소. 앱 데이터의 JSON 파일 하나(`home-layout.json`)에 프로젝트 ID → 정리를 둔다.
///
/// 정리는 덤이라 파일을 못 읽거나 못 써도 예외를 밖으로 내지 않는다. 그때도 이번 실행 동안은 메모리에 남는다.
class HomeLayoutStore {
  HomeLayoutStore(this._file);

  /// 파일에 쓰지 않는 저장소(테스트·데모용).
  HomeLayoutStore.memory() : _file = null;

  final Future<File> Function()? _file;
  Map<String, HomePlacement>? _cache;

  /// 앞선 쓰기가 끝난 뒤 다음 쓰기를 한다(서로 덮지 않게).
  Future<void> _writing = Future.value();

  Future<Map<String, HomePlacement>> load() async => Map.unmodifiable(_cache ??= await _read());

  Future<void> setGroup(String projectId, HomeGroup? group) =>
      _change(projectId, (p) => HomePlacement(group: group, pinned: p.pinned));

  Future<void> setPinned(String projectId, bool pinned) =>
      _change(projectId, (p) => HomePlacement(group: p.group, pinned: pinned));

  Future<void> _change(String projectId, HomePlacement Function(HomePlacement) update) async {
    final next = {...await load()};
    final placed = update(next[projectId] ?? HomePlacement.none);
    if (placed.isEmpty) {
      next.remove(projectId);
    } else {
      next[projectId] = placed;
    }
    _cache = next;
    _writing = _writing.then((_) => _save(next));
    await _writing;
  }

  Future<Map<String, HomePlacement>> _read() async {
    try {
      final f = _file;
      if (f == null) return {};
      final file = await f();
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && value is Map)
            key: HomePlacement(
              group: HomeGroup.values.where((g) => g.name == value['group']).firstOrNull,
              pinned: value['pinned'] == true,
            ),
      };
    } catch (_) {
      return {}; // 깨진 파일이면 정리 없이 시작한다. 다음 저장 때 새로 쓴다.
    }
  }

  Future<void> _save(Map<String, HomePlacement> placements) async {
    try {
      final f = _file;
      if (f == null) return;
      final file = await f();
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          for (final MapEntry(:key, :value) in placements.entries)
            key: {if (value.group != null) 'group': value.group!.name, if (value.pinned) 'pinned': true},
        }),
        flush: true,
      );
      await tmp.rename(file.path); // 쓰다가 꺼져도 파일이 반쯤 남지 않게
    } catch (_) {
      // 저장이 실패해도 이번 실행 동안은 메모리에 남아 보인다.
    }
  }
}
