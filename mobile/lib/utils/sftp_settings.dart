import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SftpSettings extends ChangeNotifier {
  static const String _showHiddenFilesKey = 'sftp_showHiddenFiles';
  static const String _confirmBeforeDeleteKey = 'sftp_confirmBeforeDelete';
  static const String _sortFoldersFirstKey = 'sftp_sortFoldersFirst';
  static const String _exposeToFilesAppKey = 'sftp_exposeToFilesApp';
  static const String _warnBeforeDiscardEditKey = 'sftp_warnBeforeDiscardEdit';

  bool _showHiddenFiles;
  bool _confirmBeforeDelete;
  bool _sortFoldersFirst;
  bool _exposeToFilesApp;
  bool _warnBeforeDiscardEdit;

  bool get showHiddenFiles => _showHiddenFiles;
  bool get confirmBeforeDelete => _confirmBeforeDelete;
  bool get sortFoldersFirst => _sortFoldersFirst;
  bool get exposeToFilesApp => _exposeToFilesApp;
  bool get warnBeforeDiscardEdit => _warnBeforeDiscardEdit;

  SftpSettings._({
    required this._showHiddenFiles,
    required this._confirmBeforeDelete,
    required this._sortFoldersFirst,
    required this._exposeToFilesApp,
    required this._warnBeforeDiscardEdit,
  });

  static Future<SftpSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SftpSettings._(
      showHiddenFiles: prefs.getBool(_showHiddenFilesKey) ?? false,
      confirmBeforeDelete: prefs.getBool(_confirmBeforeDeleteKey) ?? true,
      sortFoldersFirst: prefs.getBool(_sortFoldersFirstKey) ?? true,
      exposeToFilesApp: prefs.getBool(_exposeToFilesAppKey) ?? false,
      warnBeforeDiscardEdit: prefs.getBool(_warnBeforeDiscardEditKey) ?? true,
    );
  }

  Future<void> setShowHiddenFiles(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setBool(_showHiddenFilesKey, value);
    if (stored) {
      _showHiddenFiles = value;
      notifyListeners();
    }
  }

  Future<void> setConfirmBeforeDelete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setBool(_confirmBeforeDeleteKey, value);
    if (stored) {
      _confirmBeforeDelete = value;
      notifyListeners();
    }
  }

  Future<void> setSortFoldersFirst(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setBool(_sortFoldersFirstKey, value);
    if (stored) {
      _sortFoldersFirst = value;
      notifyListeners();
    }
  }

  Future<void> setExposeToFilesApp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setBool(_exposeToFilesAppKey, value);
    if (stored) {
      _exposeToFilesApp = value;
      notifyListeners();
    }
  }

  Future<void> setWarnBeforeDiscardEdit(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = await prefs.setBool(_warnBeforeDiscardEditKey, value);
    if (stored) {
      _warnBeforeDiscardEdit = value;
      notifyListeners();
    }
  }
}
