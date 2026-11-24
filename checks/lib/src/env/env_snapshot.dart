import 'dart:convert';
import 'dart:io';

/// 한 시점의 실행 환경(FR-16). 이름 → 값.
///
/// - 키가 있고 값이 null: 그때 없었다(미설치).
/// - 키가 없음: 그때 확인하지 못했다(점검 실패·Docker 꺼짐). 비교에서 뺀다.
///
/// 이름 규칙: `requires` 의 명령 이름(`node`), Docker 는 `docker`,
/// compose 이미지는 `image:<이미지 이름>`(값은 태그), Git 커밋은 `commit`.
class EnvSnapshot {
  EnvSnapshot({required this.takenAt, required Map<String, String?> values}) : values = Map.unmodifiable(values);

  final DateTime takenAt;
  final Map<String, String?> values;

  Map<String, Object?> toJson() => {'takenAt': takenAt.toUtc().toIso8601String(), 'values': values};

  static EnvSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final takenAt = DateTime.tryParse('${json['takenAt']}');
    final values = json['values'];
    if (takenAt == null || values is! Map) return null;
    return EnvSnapshot(
      takenAt: takenAt,
      values: {
        for (final MapEntry(:key, :value) in values.entries)
          if (key is String && (value == null || value is String)) key: value as String?,
      },
    );
  }
}

/// 프로젝트마다 "마지막 성공 환경" 하나를 JSON 파일에 둔다. 이력은 쌓지 않는다.
class EnvSnapshotStore {
  /// [file] 은 처음 쓸 때 정한다(앱 데이터 폴더는 비동기로 알아낸다).
  EnvSnapshotStore(this._file);

  final Future<File> Function() _file;

  /// 쓰기를 한 줄로 세운다. 동시에 두 번 쓰면 한쪽이 사라지므로.
  Future<void> _writing = Future.value();

  Future<EnvSnapshot?> read(String projectId) async => EnvSnapshot.fromJson((await _readAll())[projectId]);

  Future<void> write(String projectId, EnvSnapshot snapshot) {
    final next = _writing.then((_) async {
      final all = await _readAll();
      all[projectId] = snapshot.toJson();
      final file = await _file();
      await file.parent.create(recursive: true);
      // 임시 파일에 다 쓴 뒤 바꿔 끼운다. 쓰다가 앱이 꺼져도 이전 기록은 남는다.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(all), flush: true);
      await temp.rename(file.path);
    });
    _writing = next.catchError((_) {});
    return next;
  }

  Future<Map<String, Object?>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, Object?> ? json : {};
    } on FormatException {
      return {}; // 깨진 파일은 기록이 없는 것으로 본다. 다음 성공 때 새로 쓴다.
    }
  }
}
