import 'dart:convert';

import '../models/server.dart';
import '../utils/api_client.dart';
import '../utils/api_exception.dart';
import 'server_editor_service.dart';

/// API calls behind the server and folder context menus: notes, tags, folders
/// and Proxmox actions (mirrors the web `ServerList` menu).
class ServerActionsService {
  static void _check(dynamic response, String fallback) {
    if (response.statusCode >= 300) {
      throw ApiException.fromResponse(response, fallback: fallback);
    }
    if (response.body.isEmpty) return;
    try {
      final data = json.decode(response.body);
      if (data is Map && data['code'] is int && (data['code'] as int) >= 300) {
        throw ApiException(
          (data['message'] ?? fallback).toString(),
          statusCode: data['code'] as int,
        );
      }
    } on FormatException {
      // Non-JSON success body.
    }
  }

  // --- Notes ---------------------------------------------------------------

  /// Loads the note of [entryId] (stored in the entry configuration).
  static Future<({String notes, bool showInList})> getNotes(
    String token,
    dynamic entryId,
  ) async {
    final details = await ServerEditorService.getEntry(token, entryId);
    return (
      notes: (details.config['notes'] ?? '').toString(),
      showInList: details.config['showNoteInList'] == true,
    );
  }

  static Future<void> setNotes({
    required String token,
    required dynamic entryId,
    required String notes,
    required bool showInList,
  }) async {
    final details = await ServerEditorService.getEntry(token, entryId);
    final config = Map<String, dynamic>.from(details.config)
      ..['notes'] = notes
      ..['showNoteInList'] = showInList;
    final response = await ApiClient.patch(
      '/entries/$entryId',
      body: {'config': config},
      token: token,
    );
    _check(response, 'Could not save the note.');
  }

  // --- Tags ----------------------------------------------------------------

  static Future<List<Tag>> listTags(String token) async {
    final response = await ApiClient.get('/tags/list', token: token);
    _check(response, 'Could not load tags.');
    final data = json.decode(response.body);
    if (data is! List) return const [];
    return [
      for (final t in data)
        if (t is Map<String, dynamic>) Tag.fromJson(t),
    ];
  }

  static Future<void> assignTag(
    String token,
    int tagId,
    dynamic entryId,
  ) async {
    final response = await ApiClient.post(
      '/tags/$tagId/assign/$entryId',
      token: token,
    );
    _check(response, 'Could not assign the tag.');
  }

  static Future<void> removeTag(
    String token,
    int tagId,
    dynamic entryId,
  ) async {
    final response = await ApiClient.delete(
      '/tags/$tagId/assign/$entryId',
      token: token,
    );
    _check(response, 'Could not remove the tag.');
  }

  // --- Folders -------------------------------------------------------------

  static Future<int?> createFolder({
    required String token,
    required String name,
    int? parentId,
    int? organizationId,
  }) async {
    final response = await ApiClient.put(
      '/folders',
      body: {
        'name': name,
        'parentId': ?parentId,
        'organizationId': ?organizationId,
      },
      token: token,
    );
    _check(response, 'Could not create the folder.');
    final data = json.decode(response.body);
    if (data is Map && data['id'] is int) return data['id'] as int;
    return null;
  }

  static Future<void> renameFolder({
    required String token,
    required dynamic folderId,
    required String name,
  }) async {
    final response = await ApiClient.patch(
      '/folders/$folderId',
      body: {'name': name},
      token: token,
    );
    _check(response, 'Could not rename the folder.');
  }

  static Future<void> deleteFolder({
    required String token,
    required dynamic folderId,
  }) async {
    final response = await ApiClient.delete('/folders/$folderId', token: token);
    _check(response, 'Could not delete the folder.');
  }

  // --- Proxmox / integrations ----------------------------------------------

  /// `action` is one of `start`, `stop` or `shutdown`.
  static Future<void> pveAction({
    required String token,
    required dynamic entryId,
    required String action,
  }) async {
    final response = await ApiClient.post(
      '/integrations/entry/$entryId/$action',
      token: token,
    );
    _check(response, 'Could not $action the machine.');
  }

  static Future<void> syncIntegration(String token, int integrationId) async {
    final response = await ApiClient.post(
      '/integrations/$integrationId/sync',
      token: token,
    );
    _check(response, 'Could not sync the integration.');
  }

  static Future<void> removeIntegration(String token, int integrationId) async {
    final response = await ApiClient.delete(
      '/integrations/$integrationId',
      token: token,
    );
    _check(response, 'Could not remove the integration.');
  }
}
