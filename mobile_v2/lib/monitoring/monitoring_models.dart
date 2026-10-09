import 'dart:math';

/// Monitoring models for the monitoring page (UI-only shapes).
///
/// NOTE: these are NOT the API shapes. When wiring the API
/// (TODO below), map `GET /api/monitoring` items
/// (`{id, name, ip, status, port, icon, type, monitoring: {...}}`) and
/// `GET /api/monitoring/:serverId?timeRange=` detail
/// (`{server, data, latest}`) — see `mobile_v2/API.md` §15.

/// A monitored server card (subset of `GET /api/monitoring` items).
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

/// Extended detail (web "ServerDetails" equivalent).
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

/// Demo servers for UI iteration (TODO: API wiring).
List<MonitoredServer> demoMonitoredServers() {
  final now = DateTime.now();
  return [
    MonitoredServer(
      id: '1',
      name: 'Webserver',
      ip: '192.168.1.10',
      port: 22,
      status: 'online',
      cpu: 23.5,
      mem: 61.2,
      load: 0.87,
      processes: 132,
      uptimeSeconds: 2 * 86400 + 4 * 3600 + 12 * 60,
    ),
    MonitoredServer(
      id: '3',
      name: 'NAS',
      ip: '192.168.1.30',
      port: 2222,
      status: 'online',
      cpu: 8.1,
      mem: 34.7,
      load: 0.21,
      processes: 87,
      uptimeSeconds: 14 * 86400 + 2 * 3600,
    ),
    MonitoredServer(
      id: '2',
      name: 'Windows Box',
      ip: '192.168.1.20',
      status: 'offline',
      lastSeen: now.subtract(const Duration(hours: 3, minutes: 22)),
    ),
  ];
}

/// Demo detail for UI iteration (TODO: API wiring).
ServerDetail demoServerDetail(String id) {
  if (id == '3') {
    return const ServerDetail(
      hostname: 'nas',
      os: 'Debian GNU/Linux',
      version: '12 (bookworm)',
      arch: 'x86_64',
      kernel: '6.1.0-18-amd64',
      uptimeSeconds: 14 * 86400 + 2 * 3600,
      cpu: 8.1,
      mem: 34.7,
      memTotalGb: 16,
      load: [0.21, 0.18, 0.15],
      processes: 87,
      disks: [
        DiskInfo(name: 'sda', model: 'WDC WD40EFRX', sizeGb: 3726, partitions: [
          DiskPartition(
              name: 'sda1',
              mount: '/mnt/data',
              usagePercent: 62,
              usedGb: 2310,
              totalGb: 3726),
        ]),
      ],
      network: [
        NetIface(
            name: 'eth0',
            mac: '02:42:ac:11:00:02',
            state: 'up',
            ipv4: ['192.168.1.30/24'],
            rxGb: 812.4,
            txGb: 203.1,
            speedMbps: 1000),
      ],
      procs: [
        ProcInfo(name: 'smbd', cpu: 2.1, mem: 1.2),
        ProcInfo(name: 'docker', cpu: 1.4, mem: 3.8),
        ProcInfo(name: 'snapraid', cpu: 0.6, mem: 0.4),
      ],
    );
  }
  return const ServerDetail(
    hostname: 'web-01',
    os: 'Ubuntu',
    version: '24.04 LTS',
    arch: 'x86_64',
    kernel: '6.8.0-41-generic',
    uptimeSeconds: 2 * 86400 + 4 * 3600 + 12 * 60,
    cpu: 23.5,
    mem: 61.2,
    memTotalGb: 32,
    load: [0.87, 0.72, 0.65],
    processes: 132,
    disks: [
      DiskInfo(name: 'sda', model: 'Samsung SSD 970', sizeGb: 512, partitions: [
        DiskPartition(
            name: 'sda1',
            mount: '/',
            usagePercent: 44,
            usedGb: 225,
            totalGb: 512),
        DiskPartition(
            name: 'sda2',
            mount: '/var/lib/docker',
            usagePercent: 71,
            usedGb: 142,
            totalGb: 200),
      ]),
    ],
    network: [
      NetIface(
          name: 'eth0',
          mac: '02:42:ac:11:00:05',
          state: 'up',
          ipv4: ['192.168.1.10/24'],
          rxGb: 128.7,
          txGb: 342.9,
          speedMbps: 1000),
      NetIface(
          name: 'docker0',
          state: 'up',
          ipv4: ['172.17.0.1/16'],
          rxGb: 12.3,
          txGb: 11.8),
    ],
    procs: [
      ProcInfo(name: 'nginx', cpu: 4.2, mem: 2.1),
      ProcInfo(name: 'node', cpu: 11.8, mem: 8.4),
      ProcInfo(name: 'postgres', cpu: 3.3, mem: 12.6),
      ProcInfo(name: 'dockerd', cpu: 1.1, mem: 1.9),
    ],
  );
}

/// Demo history: seeded random walk (TODO: API wiring with timeRange).
ServerHistory demoHistory(String id, String range) {
  final points = switch (range) {
    '6h' => 72,
    '24h' => 96,
    '7d' => 84,
    _ => 60,
  };
  final seed = id.hashCode ^ range.hashCode;
  List<MetricPoint> walk(double base, double amp, double max) {
    final rnd = Random(seed ^ base.toInt());
    var v = base;
    final now = DateTime.now();
    return List.generate(points, (i) {
      v = (v + (rnd.nextDouble() - 0.5) * amp).clamp(1.0, max);
      return MetricPoint(
          now.subtract(Duration(minutes: (points - i) * 2)), v);
    });
  }

  return ServerHistory(
    cpu: walk(24, 9, 96),
    mem: walk(60, 3, 94),
    processes: walk(130, 12, 220),
  );
}

/// Available history ranges (API supports 1h/6h/24h/7d).
const List<String> historyRanges = ['1h', '6h', '24h', '7d'];
