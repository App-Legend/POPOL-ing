import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:popoling_catalog/src/home_layout.dart';

void main() {
  late Directory tmp;
  late File file;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('popoling_home_layout_');
    file = File('${tmp.path}/home-layout.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('AT-35: group and pin survive a restart', () async {
    final store = HomeLayoutStore(() async => file);
    await store.setGroup('shop-clone', HomeGroup.company);
    await store.setPinned('shop-clone', true);
    final again = await HomeLayoutStore(() async => file).load();
    expect(again['shop-clone']!.group, HomeGroup.company);
    expect(again['shop-clone']!.pinned, isTrue);
  });

  test('clearing both removes the entry', () async {
    final store = HomeLayoutStore(() async => file);
    await store.setPinned('a', true);
    await store.setPinned('a', false);
    expect(await HomeLayoutStore(() async => file).load(), isEmpty);
  });

  test('broken file starts empty and is replaced on the next save', () async {
    file.writeAsStringSync('not json');
    final store = HomeLayoutStore(() async => file);
    expect(await store.load(), isEmpty);
    await store.setGroup('a', HomeGroup.team);
    expect((await HomeLayoutStore(() async => file).load())['a']!.group, HomeGroup.team);
  });
}
