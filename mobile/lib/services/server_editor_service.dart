import 'dart:convert';
import '../models/managed_identity.dart';
import '../models/server_details.dart';
import '../utils/api_client.dart';

class ServerEditorService {
  static void _throwIfError(int statusCode, String body) {
    if (body.isEmpty) {
      if (statusCode >= 300) throw Exception('Request failed: $statusCode');
      return;
    }
    try {
      final data = json.decode(body);
      if (data is Map<String, dynamic>) {
        final code = data['code'];
        if (code is int && code >= 300) {
          throw Exception((data['message'] ?? 'Request failed').toString());
        }
        if (statusCode >= 300) {
          throw Exception((data['message'] ?? 'Request failed: $statusCode').toString());
        }
      } else if (statusCode >= 300) {
        throw Exception('Request failed: $statusCode');
      }
    } on FormatException {
      if (statusCode >= 300) throw Exception('Request failed: $statusCode');
    }
  }

  static Map<String, dynamic> _entryToMap(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    if (out['dataValues'] is Map) {
      final dv = Map<String, dynamic>.from(out['dataValues'] as Map);
      dv.addAll(out);
      dv.remove('dataValues');
      return dv;
    }
    final flat = <String, dynamic>{};
    for (final e in json.entries) {
      flat[e.key] = e.value;
    }
    if (flat['config'] is Map && flat['config'] is! Map<String, dynamic>) {
      flat['config'] = Map<String, dynamic>.from(flat['config'] as Map);
    }
    return flat;
  }

  static Future<ServerDetails> getEntry(String token, dynamic entryId) async {
    final response = await ApiClient.get('/entries/$entryId', token: token);
    _throwIfError(response.statusCode, response.body);
    if (response.body.isEmpty) throw Exception('Failed to load server');
    dynamic data;
    try {
      data = json.decode(response.body);
    } catch (_) {
      throw Exception('Failed to load server');
    }
    if (data is Map<String, dynamic>) {
      if (data['code'] is int && (data['code'] as int) >= 300) {
        throw Exception((data['message'] ?? 'Failed to load server').toString());
      }
      return ServerDetails.fromJson(_entryToMap(data));
    }
    throw Exception('Failed to load server');
  }

  static Future<int?> createEntry({
    required String token,
    required String name,
    String? icon,
    required Map<String, dynamic> config,
    dynamic folderId,
    dynamic organizationId,
    required List<int> identities,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'icon': icon,
      'config': config,
      'folderId': folderId,
      'organizationId': organizationId,
      'identities': identities,
      'type': 'server',
    };
    body.removeWhere((k, v) => v == null);
    final response = await ApiClient.put('/entries', body: body, token: token);
    _throwIfError(response.statusCode, response.body);
    if (response.body.isEmpty) throw Exception('Failed to create server');
    dynamic data;
    try {
      data = json.decode(response.body);
    } catch (_) {
      throw Exception('Failed to create server');
    }
    if (data is Map<String, dynamic>) {
      if (data['id'] is int) return data['id'] as int;
      final parsed = int.tryParse((data['id'] ?? '').toString());
      if (parsed != null) return parsed;
    }
    throw Exception('Failed to create server');
  }

  static Future<void> updateEntry({
    required String token,
    required dynamic entryId,
    required String name,
    String? icon,
    required Map<String, dynamic> config,
    required List<int> identities,
  }) async {
    final body = <String, dynamic>{'name': name, 'icon': icon, 'config': config, 'identities': identities};
    body.removeWhere((k, v) => v == null);
    final response = await ApiClient.patch(
      '/entries/$entryId',
      body: body,
      token: token,
    );
    _throwIfError(response.statusCode, response.body);
  }

  static Future<void> deleteEntry({required String token, required dynamic entryId}) async {
    final response = await ApiClient.delete('/entries/$entryId', token: token);
    _throwIfError(response.statusCode, response.body);
  }

  static Future<void> duplicateEntry({required String token, required dynamic entryId}) async {
    final response = await ApiClient.post('/entries/$entryId/duplicate', token: token);
    _throwIfError(response.statusCode, response.body);
  }

  static Future<List<EngineInfo>> getEngines(String token) async {
    try {
      final response = await ApiClient.get('/engines', token: token);
      if (response.body.isNotEmpty) {
        try {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic>) {
            final code = data['code'];
            if (code is int && code >= 300) return [];
          }
        } on FormatException {
          return [];
        }
      }
      if (response.statusCode != 200) return [];
      if (response.body.isEmpty) return [];
      final data = json.decode(response.body);
      if (data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(EngineInfo.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<ManagedIdentity>> getIdentities(String token) async {
    final response = await ApiClient.get('/identities/list', token: token);
    _throwIfError(response.statusCode, response.body);
    dynamic data;
    try {
      data = json.decode(response.body);
    } catch (_) {
      throw Exception('Failed to load identities');
    }
    if (data is! List) return [];
    return data.whereType<Map<String, dynamic>>().map(ManagedIdentity.fromJson).toList();
  }

  static Future<int> createIdentity({required String token, required Map<String, dynamic> payload}) async {
    final cleaned = Map<String, dynamic>.from(payload);
    cleaned.removeWhere((k, v) => v == null);
    final response = await ApiClient.put('/identities', body: cleaned, token: token);
    _throwIfError(response.statusCode, response.body);
    dynamic data;
    try {
      data = json.decode(response.body);
    } catch (_) {
      throw Exception('Failed to create identity');
    }
    if (data is Map<String, dynamic>) {
      if (data['id'] is int) return data['id'] as int;
      final parsed = int.tryParse((data['id'] ?? '').toString());
      if (parsed != null) return parsed;
    }
    throw Exception('Failed to create identity');
  }

  static Future<void> updateIdentity({
    required String token,
    required dynamic identityId,
    required Map<String, dynamic> payload,
  }) async {
    final cleaned = Map<String, dynamic>.from(payload);
    cleaned.removeWhere((k, v) => v == null);
    if (cleaned.isEmpty) return;
    final response = await ApiClient.patch('/identities/$identityId', body: cleaned, token: token);
    _throwIfError(response.statusCode, response.body);
  }

  static Future<List<int>> syncIdentities({
    required String token,
    required List<int> currentIds,
    required Map<String, IdentityDraft> drafts,
  }) async {
    final result = <int>{...currentIds};
    for (final entry in drafts.entries) {
      final key = entry.key;
      final draft = entry.value;
      if (key.startsWith('new-')) {
        final id = await createIdentity(token: token, payload: draft.toPayload());
        result.add(id);
      } else {
        final id = int.tryParse(key);
        if (id == null) continue;
        await updateIdentity(token: token, identityId: id, payload: draft.toPayload());
        result.add(id);
      }
    }
    return result.toList();
  }

  static Future<void> moveIdentityToOrganization({
    required String token,
    required dynamic identityId,
    required dynamic organizationId,
  }) async {
    final orgId = organizationId is int ? organizationId : int.tryParse(organizationId.toString());
    if (orgId == null) throw Exception('Invalid organization id');
    final response = await ApiClient.post(
      '/identities/$identityId/move',
      body: {'organizationId': orgId},
      token: token,
    );
    _throwIfError(response.statusCode, response.body);
  }
}
