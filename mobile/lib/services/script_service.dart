import 'dart:convert';

import '../models/script.dart';
import '../utils/api_client.dart';

/// Loads scripts for execution. Mirrors the web `ScriptContext`, which merges
/// `/scripts/all` (personal + organization memberships) with the source-synced
/// scripts from `/scripts/sources`.
class ScriptService {
  static Future<List<Script>> _fetch(String token, String endpoint) async {
    final response = await ApiClient.get(endpoint, token: token);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is! List) throw Exception('Unexpected response for $endpoint');
      return data
          .whereType<Map<String, dynamic>>()
          .map(Script.fromJson)
          .toList();
    }
    throw Exception('Failed to load scripts: ${response.statusCode}');
  }

  static Future<List<Script>> getScripts(String token) =>
      _fetch(token, '/scripts/all');

  static Future<List<Script>> getSourceScripts(String token) =>
      _fetch(token, '/scripts/sources');

  /// Personal + organization scripts, plus source-synced scripts. Source
  /// scripts are appended so both show up in the picker.
  static Future<List<Script>> getAllScripts(String token) async {
    final all = await getScripts(token);
    try {
      final sources = await getSourceScripts(token);
      final knownIds = all.map((s) => s.id).toSet();
      return [...all, ...sources.where((s) => !knownIds.contains(s.id))];
    } catch (_) {
      // Source scripts are optional — show the base list if the endpoint fails.
      return all;
    }
  }
}
