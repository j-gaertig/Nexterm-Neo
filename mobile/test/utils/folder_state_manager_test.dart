import 'package:flutter_test/flutter_test.dart';
import 'package:nexterm/utils/folder_state_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('expanded state is isolated per server instance', () async {
    final first = await FolderStateManager.create(
      scope: 'https://first.example/api',
    );
    final second = await FolderStateManager.create(
      scope: 'https://second.example/api',
    );

    await first.setFolderExpanded(1, true);

    expect(first.isFolderExpanded(1), isTrue);
    expect(second.isFolderExpanded(1), isFalse);
    expect(first.getAllExpandedFolderIds(), {'1'});
    expect(second.getAllExpandedFolderIds(), isEmpty);
  });

  test('scopes differing only by a trailing slash share state', () async {
    final plain = await FolderStateManager.create(
      scope: 'https://a.example/api',
    );
    final trailing = await FolderStateManager.create(
      scope: 'https://a.example/api/',
    );

    await plain.setFolderExpanded('folder-a', true);

    expect(trailing.isFolderExpanded('folder-a'), isTrue);
    expect(trailing.getAllExpandedFolderIds(), {'folder-a'});
  });

  test('missing scope keeps the legacy unscoped keys separate', () async {
    final unscoped = await FolderStateManager.create();
    final blank = await FolderStateManager.create(scope: '   ');
    final scoped = await FolderStateManager.create(scope: 'https://a.example');

    await unscoped.setFolderExpanded(7, true);

    expect(blank.isFolderExpanded(7), isTrue);
    expect(scoped.isFolderExpanded(7), isFalse);
  });
}
