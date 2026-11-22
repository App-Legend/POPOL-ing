import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_ai/src/redact.dart';

void main() {
  test('이름=값 꼴의 비밀값은 값만 가린다', () {
    final r = redactSecrets('VITE_API_KEY=abc123\nDB_PASSWORD: hunter2\nPORT=5173\nGITHUB_TOKEN="ghx-1"');
    expect(r.text, 'VITE_API_KEY=$mask\nDB_PASSWORD: $mask\nPORT=5173\nGITHUB_TOKEN=$mask');
    expect(r.count, 3);
  });

  test('Bearer 토큰은 이름이 있어도 없어도 가린다', () {
    expect(redactSecrets('Authorization: Bearer abcdefghijk.lmn').text, 'Authorization: Bearer $mask');
    expect(redactSecrets('curl -H "Bearer abcdefghijk"').text, 'curl -H "Bearer $mask"');
  });

  test('모양만으로 알 수 있는 키를 가린다', () {
    const google = 'AIzaSyA1234567890abcdefghijklmnopqrstuv';
    const googleNew = 'AQ.FakeFakeFakeFakeFakeFake0000';
    const github = 'ghp_abcdefghijklmnopqrstuvwxyz0123';
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcdefghijklmn';
    final r = redactSecrets('a $google b $googleNew c $github d $jwt');
    expect(r.text, 'a $mask b $mask c $mask d $mask');
    expect(r.count, 4);
  });

  test('주소 안의 사용자:비밀번호를 가린다', () {
    expect(redactSecrets('postgres://admin:s3cret@db.local:5432/app').text, 'postgres://$mask@db.local:5432/app');
  });

  test('개인 키 블록 전체를 가린다', () {
    const pem = '-----BEGIN RSA PRIVATE KEY-----\nMIIEow\nabc\n-----END RSA PRIVATE KEY-----';
    expect(redactSecrets('key:\n$pem\nend').text, 'key:\n$mask\nend');
  });

  test('꼭 가려야 하는 값(.env 값, 저장된 키)은 어디에 있든 가린다', () {
    final r = redactSecrets('connect to my-db-pass-77 failed (my-db-pass-77)', secrets: ['my-db-pass-77', 'ab', '']);
    expect(r.text, 'connect to $mask failed ($mask)');
    expect(r.count, 2);
  });

  test('이미 가린 값은 다시 세지 않는다', () {
    final r = redactSecrets('DB_PASSWORD=$mask (마스킹됨)');
    expect(r.text, 'DB_PASSWORD=$mask (마스킹됨)');
    expect(r.count, 0);
  });

  test('평범한 로그와 주소는 그대로 둔다', () {
    const log = '14:02:11  Starting Application using Java 17.0.9\nGET http://localhost:8080/actuator/health 200 84ms';
    expect(redactSecrets(log).text, log);
    expect(redactSecrets(log).count, 0);
  });
}
