import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/monitoring.dart';
import '../models/script.dart';
import '../models/server.dart';
import 'monitoring_service.dart';
import 'script_service.dart';

typedef ScriptListFetcher = Future<List<Script>> Function(String token);
typedef MonitoringDetailsFetcher = Future<M> Function(String token, dynamic id);

/// Scripts that may be executed on a server.
///
/// Web parity (`ScriptsMenu` / `ScriptContext`):
/// - personal scripts (`organizationId == null`) are available everywhere,
/// - organization scripts only inside their organization,
/// - source-synced scripts are global,
/// - OS-specific scripts are only offered when the server OS matches,
///   unless the caller explicitly asks for all scripts.
List<Script> filterScriptsForServer({
  required Iterable<Script> scripts,
  required Iterable<Script> sourceScripts,
  int? organizationId,
  String? serverOsName,
  bool includeIncompatible = false,
  String query = '',
}) {
  final normalizedOs = normalizeOsName(serverOsName);
  final byId = <int, Script>{};
  for (final script in [...scripts, ...sourceScripts]) {
    byId[script.id] = script;
  }

  final result = <Script>[];
  for (final script in byId.values) {
    if (!script.matchesSearch(query)) continue;
    if (script.isSecret) continue;

    if (!script.isSource) {
      final scriptOrganization = script.organizationId;
      final belongs =
          scriptOrganization == null ||
          (organizationId != null && scriptOrganization == organizationId);
      if (!belongs) continue;
    }

    if (!includeIncompatible && normalizedOs != null) {
      if (!matchesOsFilter(script.osFilter, normalizedOs, isPveEntry: false)) {
        continue;
      }
    }
    result.add(script);
  }

  result.sort((a, b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    if (bySort != 0) return bySort;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return result;
}

/// Caches the script catalogue, server OS lookups, favorites, and recently
/// used scripts for the lifetime of the servers screen.
class ScriptManager extends ChangeNotifier {
  ScriptManager({
    ScriptListFetcher? scriptsFetcher,
    ScriptListFetcher? sourceScriptsFetcher,
    MonitoringDetailsFetcher? monitoringFetcher,
  }) : _scriptsFetcher = scriptsFetcher ?? ScriptService.getScripts,
       _sourceScriptsFetcher =
           sourceScriptsFetcher ?? ScriptService.getSourceScripts,
       _monitoringFetcher = monitoringFetcher ?? MonitoringService.getDetails;

  static const String _favoritesKey = 'script_favorites';
  static const String _recentKey = 'script_recent';
  static const Duration _cacheLifetime = Duration(minutes: 2);
  static const Duration _osCacheLifetime = Duration(minutes: 5);

  final ScriptListFetcher _scriptsFetcher;
  final ScriptListFetcher _sourceScriptsFetcher;
  final MonitoringDetailsFetcher _monitoringFetcher;

  List<Script> _scripts = const [];
  List<Script> _sourceScripts = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  DateTime? _loadedAt;
  Future<void>? _loadOperation;

  final Map<String, _CachedOs> _osCache = {};
  final Set<int> _favoriteIds = {};
  List<int> _recentIds = [];
  bool _preferencesLoaded = false;
  Future<void>? _preferencesOperation;

  List<Script> get scripts => UnmodifiableListView(_scripts);
  List<Script> get sourceScripts => UnmodifiableListView(_sourceScripts);
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get error => _error;
  bool get hasFreshData =>
      _loaded &&
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < _cacheLifetime;

  Set<int> get favoriteIds => UnmodifiableSetView(_favoriteIds);
  List<int> get recentIds => UnmodifiableListView(_recentIds);

  bool isFavorite(int id) => _favoriteIds.contains(id);

  Future<void> ensureLoaded(String token, {bool refresh = false}) {
    if (_loaded && !refresh && hasFreshData) return Future.value();
    if (_loading) return _loadOperation ?? Future.value();

    final operation = _load(token);
    _loadOperation = operation;
    return operation;
  }

  Future<void> _load(String token) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final base = await _scriptsFetcher(token);
      var sources = const <Script>[];
      try {
        sources = await _sourceScriptsFetcher(token);
      } catch (_) {
        // Source scripts are optional; the base catalogue remains usable.
      }
      _scripts = _sort(base);
      _sourceScripts = _sort(sources);
      _loaded = true;
      _loadedAt = DateTime.now();
      _error = null;
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _loading = false;
      _loadOperation = null;
      notifyListeners();
    }
  }

  List<Script> _sort(Iterable<Script> scripts) {
    final sorted = List<Script>.of(scripts);
    sorted.sort((a, b) {
      final bySort = a.sortOrder.compareTo(b.sortOrder);
      if (bySort != 0) return bySort;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  List<Script> scriptsForServer({
    int? organizationId,
    String? serverOsName,
    bool includeIncompatible = false,
    String query = '',
  }) {
    return filterScriptsForServer(
      scripts: _scripts,
      sourceScripts: _sourceScripts,
      organizationId: organizationId,
      serverOsName: serverOsName,
      includeIncompatible: includeIncompatible,
      query: query,
    );
  }

  Script? scriptById(int id) {
    for (final script in _scripts) {
      if (script.id == id) return script;
    }
    for (final script in _sourceScripts) {
      if (script.id == id) return script;
    }
    return null;
  }

  /// OS name from monitoring with the server icon as fallback. Returns `null`
  /// when neither source knows the OS; the picker then shows every script and
  /// tells the user compatibility could not be determined.
  Future<String?> serverOsName(
    Server server,
    String token, {
    bool refresh = false,
  }) async {
    final key = server.id?.toString() ?? server.name;
    final cached = _osCache[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.loadedAt) < _osCacheLifetime) {
      return cached.name;
    }

    final fallback = normalizeOsNameFromIcon(server.icon);
    String? detected;
    if (server.id != null) {
      try {
        final details = await _monitoringFetcher(token, server.id);
        final raw = details.sub('latest').sub('osInfo').str('name').trim();
        if (raw.isNotEmpty) detected = normalizeOsName(raw);
      } catch (_) {
        // Monitoring is best-effort. The icon fallback is still useful.
      }
    }
    final name = detected ?? fallback;
    _osCache[key] = _CachedOs(name: name, loadedAt: DateTime.now());
    return name;
  }

  @visibleForTesting
  void setOsForTesting(dynamic serverId, String? osName) {
    _osCache[serverId.toString()] = _CachedOs(
      name: normalizeOsName(osName),
      loadedAt: DateTime.now(),
    );
  }

  @visibleForTesting
  void seedForTesting({List<Script>? scripts, List<Script>? sources}) {
    _scripts = _sort(scripts ?? const []);
    _sourceScripts = _sort(sources ?? const []);
    _loaded = true;
    _loadedAt = DateTime.now();
    _loading = false;
    _error = null;
    notifyListeners();
  }

  Future<void> loadPreferences() {
    if (_preferencesLoaded) return Future.value();
    if (_preferencesOperation != null) return _preferencesOperation!;
    final operation = _loadPreferences();
    _preferencesOperation = operation;
    return operation;
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _favoriteIds
        ..clear()
        ..addAll(_decodeIntList(prefs.getString(_favoritesKey)));
      _recentIds = _decodeIntList(prefs.getString(_recentKey)).toList();
    } catch (_) {
      // Favorites and recents are optional; never block the script picker.
    } finally {
      _preferencesLoaded = true;
      _preferencesOperation = null;
    }
  }

  Set<int> _decodeIntList(String? raw) {
    if (raw == null || raw.isEmpty) return <int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>{};
      return decoded.whereType<num>().map((value) => value.toInt()).toSet();
    } catch (_) {
      return <int>{};
    }
  }

  Future<void> toggleFavorite(int scriptId) async {
    await loadPreferences();
    if (!_favoriteIds.remove(scriptId)) _favoriteIds.add(scriptId);
    notifyListeners();
    await _persistIntSet(_favoritesKey, _favoriteIds);
  }

  Future<void> recordRecent(int scriptId) async {
    await loadPreferences();
    _recentIds.remove(scriptId);
    _recentIds.insert(0, scriptId);
    if (_recentIds.length > 5) _recentIds = _recentIds.take(5).toList();
    notifyListeners();
    await _persistIntList(_recentKey, _recentIds);
  }

  Future<void> _persistIntSet(String key, Set<int> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(values.toList()..sort()));
    } catch (_) {
      // Preferences are a convenience; never block script execution.
    }
  }

  Future<void> _persistIntList(String key, List<int> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(values));
    } catch (_) {
      // See above.
    }
  }
}

class _CachedOs {
  final String? name;
  final DateTime loadedAt;

  const _CachedOs({required this.name, required this.loadedAt});
}
