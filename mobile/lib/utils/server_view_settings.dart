import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ServerViewMode { list, grid }

class ServerViewSettings extends ChangeNotifier {
  static const String _modeKey = 'server_view_mode';
  static const String _columnsKey = 'server_view_columns';

  ServerViewMode _mode;
  int _gridColumns;

  ServerViewMode get mode => _mode;
  int get gridColumns => _gridColumns;
  bool get isGrid => _mode == ServerViewMode.grid;

  ServerViewSettings._({
    required ServerViewMode mode,
    required int gridColumns,
  })  : _mode = mode,
        _gridColumns = gridColumns;

  static Future<ServerViewSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMode = prefs.getString(_modeKey);
    final mode = rawMode == ServerViewMode.grid.name
        ? ServerViewMode.grid
        : ServerViewMode.list;
    final rawColumns = prefs.getInt(_columnsKey) ?? 2;
    final columns = rawColumns < 1 ? 1 : rawColumns > 5 ? 5 : rawColumns;
    return ServerViewSettings._(mode: mode, gridColumns: columns);
  }

  Future<void> setMode(ServerViewMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_modeKey, mode.name);
  }

  Future<void> setGridColumns(int value) async {
    final next = value < 1 ? 1 : value > 5 ? 5 : value;
    if (_gridColumns == next) return;
    _gridColumns = next;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_columnsKey, next);
  }
}
