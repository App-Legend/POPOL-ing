import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gemini API 키를 이 컴퓨터에만 보관하는 곳.
///
/// 키는 저장소·`popoling.yaml`·로그에 남기지 않는다. 사용자가 앱에서 직접 넣고, 앱 빌드에는 넣지 않는다.
abstract interface class ApiKeyStore {
  /// 저장된 키. 없으면 null.
  Future<String?> read();

  /// 키를 저장한다. 앞뒤 공백은 뺀다.
  Future<void> write(String key);

  /// 키를 지운다. 없어도 괜찮다.
  Future<void> delete();
}

/// OS 보안 저장소(macOS 키체인, Windows 자격 증명)에 둔다.
class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // macOS 의 "데이터 보호 키체인"은 키체인 공유 권한과 서명(프로비저닝)이 있어야 한다.
              // 발표용 빌드는 서명하지 않으므로, 권한이 필요 없는 로그인 키체인을 쓴다.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  static const _name = 'gemini_api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _name);
    return value == null || value.trim().isEmpty ? null : value;
  }

  @override
  Future<void> write(String key) => _storage.write(key: _name, value: key.trim());

  @override
  Future<void> delete() => _storage.delete(key: _name);
}

/// 메모리에만 두는 [ApiKeyStore]. 테스트와 시안 화면에 쓴다.
class MemoryApiKeyStore implements ApiKeyStore {
  MemoryApiKeyStore([this._key]);

  String? _key;

  @override
  Future<String?> read() async => _key == null || _key!.trim().isEmpty ? null : _key;

  @override
  Future<void> write(String key) async => _key = key.trim();

  @override
  Future<void> delete() async => _key = null;
}
