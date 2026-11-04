import 'package:shared_preferences/shared_preferences.dart';

/// Persists which folders are expanded. The preference keys are scoped to the
/// server instance so two accounts cannot overwrite each other's state when
/// their folder ids overlap.
class FolderStateManager {
  static const String _prefix = 'folder_expanded_';
  final SharedPreferences _prefs;
  final String _keyPrefix;

  FolderStateManager._(this._prefs, String? scope)
    : _keyPrefix = '$_prefix${_normalizeScope(scope)}';

  static String _normalizeScope(String? scope) {
    final value = scope?.trim();
    if (value == null || value.isEmpty) return '';
    return '${value.replaceAll(RegExp(r'/+$'), '')}_';
  }

  static Future<FolderStateManager> create({String? scope}) async =>
      FolderStateManager._(await SharedPreferences.getInstance(), scope);

  bool isFolderExpanded(dynamic folderId) =>
      folderId != null && (_prefs.getBool('$_keyPrefix$folderId') ?? false);

  Future<void> setFolderExpanded(dynamic folderId, bool isExpanded) async {
    if (folderId != null) {
      await _prefs.setBool('$_keyPrefix$folderId', isExpanded);
    }
  }

  Set<String> getAllExpandedFolderIds() => _prefs
      .getKeys()
      .where((k) => k.startsWith(_keyPrefix) && (_prefs.getBool(k) ?? false))
      .map((k) => k.substring(_keyPrefix.length))
      .toSet();
}
