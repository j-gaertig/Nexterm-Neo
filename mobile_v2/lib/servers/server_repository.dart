import '../api/nexterm_api.dart';
import 'server_models.dart';

/// Loads servers for the servers page.
abstract class ServerRepository {
  Future<List<EntryNode>> fetchNodes();
}

/// Live repository: `GET /api/entries/list` as folder tree.
class ApiServerRepository implements ServerRepository {
  ApiServerRepository({required this.api, required this.token});

  final NextermApi api;
  final String token;

  @override
  Future<List<EntryNode>> fetchNodes() async {
    final tree = await api.fetchEntries(token);
    return parseEntryTree(tree);
  }
}

/// Entry mutations (`PUT/PATCH/DELETE/duplicate/wake`).
class EntryMutations {
  EntryMutations({required this.api, required this.token});

  final NextermApi api;
  final String token;

  Future<Map<String, dynamic>> fetchDetail(int entryId) =>
      api.fetchEntry(token, entryId);

  Future<int> create(Map<String, dynamic> payload) =>
      api.createEntry(token, payload);

  Future<void> update(int entryId, Map<String, dynamic> payload) =>
      api.updateEntry(token, entryId, payload);

  Future<void> remove(int entryId) => api.deleteEntry(token, entryId);

  Future<void> duplicate(int entryId) =>
      api.duplicateEntry(token, entryId);

  Future<void> wake(int entryId) => api.wakeEntry(token, entryId);
}
