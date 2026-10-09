import '../api/nexterm_api.dart';
import 'monitoring_models.dart';

/// Live monitoring data source.
abstract class MonitoringRepository {
  Future<List<MonitoredServer>> fetchServers();
  Future<MonitoredDetail> fetchDetail(String serverId, String range);
}

/// Detail payload: parsed `latest` + history series.
class MonitoredDetail {
  const MonitoredDetail({required this.detail, required this.history});

  final ServerDetail detail;
  final ServerHistory history;
}

/// API implementation (`GET /api/monitoring[/:id]`).
class ApiMonitoringRepository implements MonitoringRepository {
  ApiMonitoringRepository({required this.api, required this.token});

  final NextermApi api;
  final String token;

  @override
  Future<List<MonitoredServer>> fetchServers() async {
    final raw = await api.fetchMonitoring(token);
    final out = <MonitoredServer>[];
    for (final m in raw) {
      try {
        out.add(MonitoredServer.fromJson(m));
      } catch (_) {
        // Skip corrupt items.
      }
    }
    return out;
  }

  @override
  Future<MonitoredDetail> fetchDetail(
      String serverId, String range) async {
    // Proxmox items (id `pve-<id>`) use the integration endpoint.
    final raw = serverId.startsWith('pve-')
        ? await api.fetchIntegrationMonitoring(
            token, serverId.substring(4), range)
        : await api.fetchServerMonitoring(token, serverId, range);
    final latest = raw['latest'];
    final data = raw['data'];
    return MonitoredDetail(
      detail: ServerDetail.fromLatest(
          latest is Map ? Map<String, dynamic>.from(latest) : {}),
      history: parseHistory(data is List ? data : const []),
    );
  }
}
