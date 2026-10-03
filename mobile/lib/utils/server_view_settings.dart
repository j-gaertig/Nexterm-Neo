import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ServerViewMode { list, grid }

class ServerViewSettings extends ChangeNotifier {
  static const String _modeKey = 'server_view_mode';
  static const String _columnsKey = 'server_view_columns';
  static const int minColumns = 2;
  static const int maxColumns = 4;
  static const int defaultColumns = 2;

  Future<void> _pending = Future.value();

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
    final rawColumns = prefs.getInt(_columnsKey) ?? defaultColumns;
    final columns = rawColumns.clamp(minColumns, maxColumns);
    return ServerViewSettings._(mode: mode, gridColumns: columns);
  }

  Future<void> setMode(ServerViewMode mode) async {
    if (_mode == mode) return;
    final task = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final stored = await prefs.setString(_modeKey, mode.name);
      if (stored) {
        _mode = mode;
        notifyListeners();
      }
    });
    _pending = task.catchError((_) {});
    await task;
  }

  Future<void> setGridColumns(int value) async {
    final next = value.clamp(minColumns, maxColumns);
    if (_gridColumns == next) return;
    final task = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final stored = await prefs.setInt(_columnsKey, next);
      if (stored) {
        _gridColumns = next;
        notifyListeners();
      }
    });
    _pending = task.catchError((_) {});
    await task;
  }
}
