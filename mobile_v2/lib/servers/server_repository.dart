import '../api/nexterm_api.dart';
import 'server_models.dart';

/// Loads servers for the servers page.
abstract class ServerRepository {
  Future<List<ServerEntry>> fetchServers();
}

/// Live repository: `GET /api/entries/list`, flattened to server leaves.
class ApiServerRepository implements ServerRepository {
  ApiServerRepository({required this.api, required this.token});

  final NextermApi api;
  final String token;

  @override
  Future<List<ServerEntry>> fetchServers() async {
    final tree = await api.fetchEntries(token);
    return flattenServerEntries(tree);
  }
}
