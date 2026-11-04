import 'package:flutter/material.dart';

import '../../models/monitoring.dart';
import '../../utils/app_icons.dart';
import '../../widgets/app_ui.dart';
import 'format.dart';
import 'line_chart.dart';

Color _usageColor(ColorScheme cs, double? v, Color base) => v == null
    ? base
    : v > 80
    ? cs.error
    : v > 60
    ? Colors.orange
    : base;

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: cs.outline)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final double? percent;

  const _Metric({
    required this.label,
    required this.value,
    this.detail,
    this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12.5, color: cs.outline),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _usageColor(cs, percent, cs.onSurface),
                ),
              ),
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: 6),
            UsageBar(percent: percent!, height: 6),
          ],
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail!,
                style: TextStyle(fontSize: 11.5, color: cs.outline),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rounded progress bar that turns orange/red as usage rises.
class UsageBar extends StatelessWidget {
  final double percent;
  final double height;
  final Color? base;

  const UsageBar({
    super.key,
    required this.percent,
    this.height = 8,
    this.base,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: (percent / 100).clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: cs.surfaceContainerHighest,
        color: _usageColor(cs, percent, base ?? cs.primary),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard(this.text);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color? color;

  const _Pill(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

// --- Overview --------------------------------------------------------------

class OverviewTab extends StatelessWidget {
  final M latest;
  final bool isPve;

  const OverviewTab({super.key, required this.latest, required this.isPve});

  @override
  Widget build(BuildContext context) {
    return isPve ? _pve(context) : _server(context);
  }

  Widget _server(BuildContext context) {
    final os = latest.sub('osInfo');
    final isWindows = os.str('platform') == 'windows';
    final load = latest.doubles('loadAverage');
    final memTotal = latest.n('memoryTotal');
    String unknown(String v) => v.isEmpty ? 'Unknown' : v;
    return Column(
      children: [
        _Section(
          title: 'System',
          children: os.raw.isEmpty
              ? const [_InfoRow('Status', 'No data available')]
              : [
                  _InfoRow('Hostname', unknown(os.str('hostname'))),
                  _InfoRow('OS', unknown(os.str('name'))),
                  _InfoRow('Version', unknown(os.str('version'))),
                  if (!isWindows) _InfoRow('Kernel', unknown(os.str('kernel'))),
                  _InfoRow('Architecture', unknown(os.str('architecture'))),
                  _InfoRow('Uptime', formatUptime(latest.n('uptime'))),
                ],
        ),
        _Section(
          title: 'Performance',
          children: [
            _Metric(
              label: 'CPU usage',
              value: formatPercent(latest.d('cpuUsage')),
              percent: latest.d('cpuUsage'),
            ),
            _Metric(
              label: 'Memory usage',
              value: formatPercent(latest.d('memoryUsage')),
              percent: latest.d('memoryUsage'),
              detail: memTotal == null
                  ? null
                  : 'Total ${formatBytes(memTotal)}',
            ),
            if (!isWindows)
              _Metric(
                label: 'Load average',
                value: load.isEmpty ? 'N/A' : load.first.toStringAsFixed(2),
                detail: load.length >= 3
                    ? '5 min ${load[1].toStringAsFixed(2)} · 15 min ${load[2].toStringAsFixed(2)}'
                    : null,
              ),
            _Metric(
              label: 'Processes',
              value: latest.n('processes')?.toString() ?? 'N/A',
            ),
          ],
        ),
      ],
    );
  }

  Widget _pve(BuildContext context) {
    final p = latest.sub('osInfo');
    return Column(
      children: [
        _Section(
          title: 'Cluster',
          children: [
            _InfoRow('Nodes', '${p.n('totalNodes') ?? 0}'),
            _InfoRow('Online nodes', '${p.n('onlineNodes') ?? 0}'),
            _InfoRow('Total CPU', '${p.n('totalCpu') ?? 0} cores'),
            _InfoRow('Total memory', formatBytes(p.n('totalMemory'))),
            _InfoRow('Total storage', formatBytes(p.n('totalDisk'))),
            _InfoRow('Uptime', formatUptime(latest.n('uptime'))),
          ],
        ),
        _Section(
          title: 'Resources',
          children: [
            _Metric(
              label: 'CPU usage',
              value: formatPercent(latest.d('cpuUsage')),
              percent: latest.d('cpuUsage'),
            ),
            _Metric(
              label: 'Memory usage',
              value: formatPercent(latest.d('memoryUsage')),
              percent: latest.d('memoryUsage'),
              detail: latest.n('memoryTotal') == null
                  ? null
                  : 'Total ${formatBytes(latest.n('memoryTotal'))}',
            ),
            _Metric(
              label: 'Storage usage',
              value: formatPercent(p.d('diskUsage')),
              percent: p.d('diskUsage'),
              detail: p.n('totalDisk') == null
                  ? null
                  : 'Total ${formatBytes(p.n('totalDisk'))}',
            ),
          ],
        ),
        _Section(
          title: 'Virtual machines',
          children: [
            _InfoRow(
              'QEMU VMs',
              '${p.n('vmCount') ?? 0} (${p.n('runningVMs') ?? 0} running)',
            ),
            _InfoRow(
              'LXC containers',
              '${p.n('lxcCount') ?? 0} (${p.n('runningLXC') ?? 0} running)',
            ),
          ],
        ),
      ],
    );
  }
}

// --- Charts ----------------------------------------------------------------

class ChartsTab extends StatelessWidget {
  final List<M> data;
  final bool isPve;
  final String range;
  final ValueChanged<String> onRangeChanged;

  const ChartsTab({
    super.key,
    required this.data,
    required this.isPve,
    required this.range,
    required this.onRangeChanged,
  });

  static const ranges = ['1h', '6h', '24h'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = [...data]..sort((a, b) => _time(a).compareTo(_time(b)));
    final times = [for (final d in sorted) _time(d)];
    List<double?> series(String key) => [for (final d in sorted) d.d(key)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            children: [
              for (final r in ranges)
                ChoiceChip(
                  label: Text(r),
                  selected: range == r,
                  side: appBorderSide(cs),
                  onSelected: (_) => onRangeChanged(r),
                ),
            ],
          ),
        ),
        MonitoringLineChart(
          title: 'CPU usage',
          times: times,
          values: series('cpuUsage'),
          color: const Color(0xFF4C6EF5),
          unit: '%',
          yMax: 100,
        ),
        const SizedBox(height: 12),
        MonitoringLineChart(
          title: 'Memory usage',
          times: times,
          values: series('memoryUsage'),
          color: const Color(0xFF29C16A),
          unit: '%',
          yMax: 100,
        ),
        const SizedBox(height: 12),
        MonitoringLineChart(
          title: isPve ? 'VMs and containers' : 'Processes',
          times: times,
          values: series('processes'),
          color: const Color(0xFFDC5600),
        ),
      ],
    );
  }

  static DateTime _time(M m) =>
      DateTime.tryParse(m.str('timestamp')) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

// --- Storage ---------------------------------------------------------------

class StorageTab extends StatelessWidget {
  final List<M> disks;
  final bool isWindows;

  const StorageTab({super.key, required this.disks, required this.isWindows});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (disks.isEmpty) return const _EmptyCard('No storage data available');
    return Column(
      children: [
        for (final d in disks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AppIconBox(
                        icon: AppIcons.databaseOutline,
                        size: 34,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isWindows
                                  ? d.str('name')
                                  : '/dev/${d.str('name')}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (d.str('model').isNotEmpty)
                              Text(
                                d.str('model'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      if (d['rotational'] != null)
                        _Pill(d.flag('rotational') ? 'HDD' : 'SSD'),
                      const SizedBox(width: 8),
                      Text(
                        formatBytes(d.n('size')),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (d.list('partitions').isEmpty)
                    Text(
                      'No partitions',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    )
                  else
                    for (final p in d.list('partitions'))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p.str('name'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (p.str('mountPoint').isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _Pill(p.str('mountPoint')),
                                ],
                                if (p.str('type').isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  _Pill(p.str('type')),
                                ],
                                const Spacer(),
                                Text(
                                  formatPercent(p.d('usagePercent')),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            UsageBar(
                              percent: p.d('usagePercent') ?? 0,
                              height: 6,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Used ${formatBytes(p.n('used'))} · '
                              'Free ${formatBytes(p.n('available'))} · '
                              'Total ${formatBytes(p.n('size'))}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: cs.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// --- Network ---------------------------------------------------------------

class NetworkTab extends StatelessWidget {
  final List<M> interfaces;

  const NetworkTab({super.key, required this.interfaces});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (interfaces.isEmpty) {
      return const _EmptyCard('No network data available');
    }
    return Column(
      children: [
        for (final i in interfaces)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AppIconBox(icon: AppIcons.serverNetwork, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              i.str('name'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (i.str('mac').isNotEmpty)
                              Text(
                                i.str('mac'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (i.str('state').isNotEmpty)
                        _Pill(
                          i.str('state'),
                          color: i.str('state') == 'up'
                              ? const Color(0xFF4CAF50)
                              : cs.outline,
                        ),
                    ],
                  ),
                  if (_strings(i, 'ipv4').isNotEmpty ||
                      _strings(i, 'ipv6').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final ip in _strings(i, 'ipv4')) _Pill(ip),
                        for (final ip in _strings(i, 'ipv6')) _Pill(ip),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  _InfoRow('Received', formatBytes(i.n('rxBytes'))),
                  _InfoRow('Sent', formatBytes(i.n('txBytes'))),
                  if (i.n('speed') != null)
                    _InfoRow('Speed', '${i.n('speed')} Mbps'),
                  if (i.n('mtu') != null) _InfoRow('MTU', '${i.n('mtu')}'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static List<String> _strings(M m, String key) =>
      (m[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
}

// --- Nodes (Proxmox) -------------------------------------------------------

class NodesTab extends StatelessWidget {
  final List<M> nodes;

  const NodesTab({super.key, required this.nodes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (nodes.isEmpty) return const _EmptyCard('No nodes found');
    return Column(
      children: [
        for (final n in nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIconBox(
                        icon: AppIcons.serverNetwork,
                        size: 34,
                        background: n.isOnline
                            ? cs.primaryContainer
                            : cs.errorContainer,
                        foreground: n.isOnline
                            ? cs.onPrimaryContainer
                            : cs.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          n.str('name'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _Pill(
                        n.str('status'),
                        color: n.isOnline ? const Color(0xFF4CAF50) : cs.error,
                      ),
                    ],
                  ),
                  if (!n.isOnline)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'This node is offline',
                        style: TextStyle(fontSize: 12.5, color: cs.outline),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 6),
                    _Metric(
                      label: 'CPU',
                      value: formatPercent(n.d('cpuUsage')),
                      percent: n.d('cpuUsage') ?? 0,
                    ),
                    _Metric(
                      label: 'Memory',
                      value: formatPercent(n.d('memoryUsage')),
                      percent: n.d('memoryUsage') ?? 0,
                      detail:
                          '${formatBytes(n.n('memoryUsed'))} / ${formatBytes(n.n('memory'))}',
                    ),
                    _Metric(
                      label: 'Storage',
                      value: formatPercent(n.d('diskUsage')),
                      percent: n.d('diskUsage') ?? 0,
                      detail:
                          '${formatBytes(n.n('diskUsed'))} / ${formatBytes(n.n('disk'))}',
                    ),
                    _InfoRow('Cores', '${n.n('cpu') ?? '-'}'),
                    _InfoRow('Uptime', formatUptime(n.n('uptime'))),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// --- Processes -------------------------------------------------------------

class ProcessesTab extends StatefulWidget {
  final List<M> processes;

  const ProcessesTab({super.key, required this.processes});

  @override
  State<ProcessesTab> createState() => _ProcessesTabState();
}

class _ProcessesTabState extends State<ProcessesTab> {
  String _query = '';
  String _sortBy = 'cpu';
  bool _descending = true;

  List<M> get _visible {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? [...widget.processes]
        : widget.processes
              .where(
                (p) =>
                    p.str('command').toLowerCase().contains(q) ||
                    p.str('user').toLowerCase().contains(q) ||
                    p.str('pid').contains(q),
              )
              .toList();
    list.sort((a, b) {
      final av = a.d(_sortBy) ?? 0;
      final bv = b.d(_sortBy) ?? 0;
      return _descending ? bv.compareTo(av) : av.compareTo(bv);
    });
    return list;
  }

  void _sort(String field) => setState(() {
    if (_sortBy == field) {
      _descending = !_descending;
    } else {
      _sortBy = field;
      _descending = true;
    }
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.processes.isEmpty) {
      return const _EmptyCard('No process data available');
    }
    final items = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search processes…',
            prefixIcon: const Icon(AppIcons.magnify, size: 20),
            isDense: true,
            filled: true,
            fillColor: cs.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
              borderSide: appBorderSide(cs),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
              borderSide: appBorderSide(cs),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final f in const ['cpu', 'mem', 'pid'])
              ChoiceChip(
                selected: _sortBy == f,
                side: appBorderSide(cs),
                label: Text(
                  f.toUpperCase() +
                      (_sortBy == f ? (_descending ? ' ↓' : ' ↑') : ''),
                ),
                onSelected: (_) => _sort(f),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const _EmptyCard('No processes match your search')
        else
          // Lazily built: process lists can have hundreds of entries.
          for (final p in items.take(200)) _processTile(cs, p),
        if (items.length > 200)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing the first 200 of ${items.length} processes. Use search to narrow down.',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ),
      ],
    );
  }

  Widget _processTile(ColorScheme cs, M p) {
    final cpu = p.d('cpu') ?? 0;
    final mem = p.d('mem') ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        radius: AppRadii.control,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.str('command'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${p.str('user')} · PID ${p.str('pid')}',
              style: TextStyle(fontSize: 11.5, color: cs.outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _statBar('CPU', cpu)),
                const SizedBox(width: 12),
                Expanded(child: _statBar('MEM', mem)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBar(String label, double value) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 10.5, color: cs.outline)),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 3),
        UsageBar(percent: value.clamp(0, 100).toDouble(), height: 4),
      ],
    );
  }
}
