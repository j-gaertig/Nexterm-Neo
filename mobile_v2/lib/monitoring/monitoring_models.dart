/// Monitoring models with live-API parsing (`GET /api/monitoring[/:id]`).
///
/// Parsing is defensive: SQLite may stringify numbers and fields may be
/// missing — see `mobile_v2/API.md` §15 and
/// `server/controllers/monitoring.js`.
library;

double? _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('$v');

int? _int(dynamic v) =>
    v is num ? v.toInt() : int.tryParse('$v');

double _gb(dynamic bytes) => (_num(bytes) ?? 0) / 1073741824;

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// A monitored server card (`GET /api/monitoring/` item).
class MonitoredServer {
  const MonitoredServer({
    required this.id,
    required this.name,
    required this.ip,
    this.port,
    this.icon,
    this.type = 'server',
    this.status = 'unknown',
    this.cpu,
    this.mem,
    this.load,
    this.processes,
    this.uptimeSeconds,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String ip;
  final int? port;
  final String? icon;
  final String type;
  final String status;
  final double? cpu;
  final double? mem;
  final double? load;
  final int? processes;
  final int? uptimeSeconds;
  final DateTime? lastSeen;

  bool get isOnline => status == 'online';

  String get address => port == null ? ip : '$ip:$port';

  factory MonitoredServer.fromJson(Map<String, dynamic> json) {
    final mon = _map(json['monitoring']);
    final load = mon['loadAverage'];
    return MonitoredServer(
      id: '${json['id']}',
      name: json['name'] as String? ?? 'Server',
      ip: json['ip'] as String? ?? '',
      port: _int(json['port']),
      icon: json['icon'] as String?,
      type: json['type'] as String? ?? 'server',
      status: json['status'] as String? ??
          mon['status'] as String? ??
          'unknown',
      cpu: _num(mon['cpuUsage']),
      mem: _num(mon['memoryUsage']),
      load: load is List && load.isNotEmpty ? _num(load.first) : null,
      processes: _int(mon['processes']),
      uptimeSeconds: _int(mon['uptime']),
      lastSeen: DateTime.tryParse(
          '${mon['lastSeen'] ?? mon['timestamp'] ?? mon['updatedAt'] ?? ''}'),
    );
  }
}

/// One history sample for charts (`GET /api/monitoring/:id` `data`).
class MetricPoint {
  const MetricPoint(this.time, this.value);

  final DateTime time;
  final double value;
}

/// History series for the charts tab.
class ServerHistory {
  const ServerHistory(
      {required this.cpu, required this.mem, required this.processes});

  final List<MetricPoint> cpu;
  final List<MetricPoint> mem;
  final List<MetricPoint> processes;

  static const empty =
      ServerHistory(cpu: [], mem: [], processes: []);
}

/// Parse `data` rows (`{timestamp, cpuUsage, memoryUsage, processes}`),
/// oldest first for charts.
ServerHistory parseHistory(List<dynamic> data) {
  List<MetricPoint> series(String key) {
    final pts = <MetricPoint>[];
    for (final row in data) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final t = DateTime.tryParse(
          '${map['timestamp'] ?? map['createdAt'] ?? ''}');
      final v = _num(map[key]);
      if (t != null && v != null) pts.add(MetricPoint(t, v));
    }
    pts.sort((a, b) => a.time.compareTo(b.time));
    return pts;
  }

  return ServerHistory(
    cpu: series('cpuUsage'),
    mem: series('memoryUsage'),
    processes: series('processes'),
  );
}

class DiskPartition {
  const DiskPartition(
      {required this.name,
      this.mount,
      required this.usagePercent,
      required this.usedGb,
      required this.totalGb});

  final String name;
  final String? mount;
  final double usagePercent;
  final double usedGb;
  final double totalGb;
}

class DiskInfo {
  const DiskInfo(
      {required this.name,
      this.model,
      required this.sizeGb,
      this.partitions = const []});

  final String name;
  final String? model;
  final double sizeGb;
  final List<DiskPartition> partitions;
}

class NetIface {
  const NetIface(
      {required this.name,
      this.mac,
      this.state,
      this.ipv4 = const [],
      required this.rxGb,
      required this.txGb,
      this.speedMbps});

  final String name;
  final String? mac;
  final String? state;
  final List<String> ipv4;
  final double rxGb;
  final double txGb;
  final int? speedMbps;
}

class ProcInfo {
  const ProcInfo({required this.name, required this.cpu, required this.mem});

  final String name;
  final double cpu;
  final double mem;
}

/// Extended detail (web "ServerDetails" equivalent), parsed from
/// the `latest` object of `GET /api/monitoring/:serverId`.
class ServerDetail {
  const ServerDetail({
    required this.hostname,
    required this.os,
    required this.version,
    required this.arch,
    this.kernel,
    required this.uptimeSeconds,
    required this.cpu,
    required this.mem,
    required this.memTotalGb,
    required this.load,
    required this.processes,
    required this.disks,
    required this.network,
    required this.procs,
  });

  final String hostname;
  final String os;
  final String version;
  final String arch;
  final String? kernel;
  final int uptimeSeconds;
  final double cpu;
  final double mem;
  final double memTotalGb;
  final List<double> load;
  final int processes;
  final List<DiskInfo> disks;
  final List<NetIface> network;
  final List<ProcInfo> procs;

  factory ServerDetail.fromLatest(Map<String, dynamic> latest) {
    final os = _map(latest['osInfo']);
    final loadRaw = latest['loadAverage'];
    final disks = <DiskInfo>[];
    final diskRaw = latest['disk'];
    if (diskRaw is List) {
      for (final d in diskRaw) {
        if (d is! Map) continue;
        final dm = Map<String, dynamic>.from(d);
        final parts = <DiskPartition>[];
        final partRaw = dm['partitions'];
        if (partRaw is List) {
          for (final p in partRaw) {
            if (p is! Map) continue;
            final pm = Map<String, dynamic>.from(p);
            parts.add(DiskPartition(
              name: pm['name'] as String? ?? 'part',
              mount: pm['mountPoint'] as String? ?? pm['mount'] as String?,
              usagePercent:
                  _num(pm['usagePercent'] ?? pm['usage']) ?? 0,
              usedGb: _gb(pm['used']),
              totalGb: _gb(pm['size'] ?? pm['total']),
            ));
          }
        }
        disks.add(DiskInfo(
          name: dm['name'] as String? ?? 'disk',
          model: dm['model'] as String?,
          sizeGb: _gb(dm['size']),
          partitions: parts,
        ));
      }
    }
    final ifaces = <NetIface>[];
    final netRaw = latest['network'];
    if (netRaw is List) {
      for (final n in netRaw) {
        if (n is! Map) continue;
        final nm = Map<String, dynamic>.from(n);
        final v4 = <String>[];
        final rawV4 = nm['ipv4'];
        if (rawV4 is List) {
          for (final ip in rawV4) {
            v4.add('$ip');
          }
        }
        ifaces.add(NetIface(
          name: nm['name'] as String? ?? 'iface',
          mac: nm['mac'] as String?,
          state: nm['state'] as String?,
          ipv4: v4,
          rxGb: _gb(nm['rxBytes']),
          txGb: _gb(nm['txBytes']),
          speedMbps: _int(nm['speed']),
        ));
      }
    }
    final procs = <ProcInfo>[];
    final procRaw = latest['processList'];
    if (procRaw is List) {
      for (final p in procRaw) {
        if (p is! Map) continue;
        final pm = Map<String, dynamic>.from(p);
        procs.add(ProcInfo(
          name: pm['name'] as String? ??
              (pm['pid'] != null ? 'PID ${pm['pid']}' : 'process'),
          cpu: _num(pm['cpu'] ?? pm['cpuPercent']) ?? 0,
          mem: _num(pm['mem'] ?? pm['memoryPercent']) ?? 0,
        ));
      }
    }
    final loads = <double>[];
    if (loadRaw is List) {
      for (final v in loadRaw) {
        final n = _num(v);
        if (n != null) loads.add(n);
      }
    }
    return ServerDetail(
      hostname: os['hostname'] as String? ?? '',
      os: os['name'] as String? ?? os['platform'] as String? ?? '',
      version: os['version'] as String? ?? '',
      arch: os['architecture'] as String? ?? os['arch'] as String? ?? '',
      kernel: os['kernel'] as String?,
      uptimeSeconds: _int(latest['uptime']) ?? 0,
      cpu: _num(latest['cpuUsage']) ?? 0,
      mem: _num(latest['memoryUsage']) ?? 0,
      memTotalGb: _gb(latest['memoryTotal']),
      load: loads,
      processes: _int(latest['processes']) ?? procs.length,
      disks: disks,
      network: ifaces,
      procs: procs,
    );
  }
}

/// "2d 4h" / "3h 12m" / "8m" / "—" (mirrors the web grid).
String formatUptime(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String formatGb(double gb) =>
    gb >= 100 ? '${gb.toStringAsFixed(0)} GB' : '${gb.toStringAsFixed(1)} GB';

/// Available history ranges (server supports 1h/6h/24h).
const List<String> historyRanges = ['1h', '6h', '24h'];
