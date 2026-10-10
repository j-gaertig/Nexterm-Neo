import 'package:flutter/material.dart';

import '../../api/nexterm_api.dart';
import '../../monitoring/monitoring_models.dart';
import '../../monitoring/monitoring_repository.dart';

/// Extended server detail (web "ServerDetails" equivalent):
/// Overview, Charts (with time range), Storage, Network, Processes.
class MonitoringDetailPage extends StatefulWidget {
  const MonitoringDetailPage(
      {super.key,
      required this.server,
      required this.repository,
      this.onSessionExpired});

  final MonitoredServer server;
  final MonitoringRepository repository;

  /// Called on HTTP 401 so expired sessions return to login.
  final VoidCallback? onSessionExpired;

  @override
  State<MonitoringDetailPage> createState() => _MonitoringDetailPageState();
}

class _MonitoringDetailPageState extends State<MonitoringDetailPage> {
  int _tab = 0;
  String _range = '1h';
  MonitoredDetail? _detail;
  String? _error;
  bool _loading = true;

  static const _tabs = [
    (Icons.info_outline, 'Overview'),
    (Icons.show_chart, 'Charts'),
    (Icons.storage_outlined, 'Storage'),
    (Icons.lan_outlined, 'Network'),
    (Icons.terminal, 'Processes'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail =
          await widget.repository.fetchDetail(widget.server.id, _range);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSessionExpired?.call();
      return;
    } on NextermApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load server details.';
        _loading = false;
      });
    }
  }

  void _selectRange(String range) {
    setState(() => _range = range);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(widget.server.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      body: Column(
        children: [
          _TabChips(
            tabs: _tabs,
            selected: _tab,
            onSelect: (i) => setState(() => _tab = i),
          ),
          if (_tab == 1)
            _RangeChips(
              selected: _range,
              onSelect: _selectRange,
            ),
          Expanded(
            child: _loading && _detail == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _detail == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                  onPressed: _load,
                                  child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : switch (_tab) {
                        0 => _OverviewTab(detail: _detail!.detail),
                        1 => _ChartsTab(history: _detail!.history),
                        2 => _StorageTab(detail: _detail!.detail),
                        3 => _NetworkTab(detail: _detail!.detail),
                        _ => _ProcessesTab(detail: _detail!.detail),
                      },
          ),
        ],
      ),
    );
  }
}

class _TabChips extends StatelessWidget {
  const _TabChips(
      {required this.tabs, required this.selected, required this.onSelect});

  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = i == selected;
          final (icon, label) = tabs[i];
          return ChoiceChip(
            label: Text(label),
            avatar: Icon(icon, size: 18),
            selected: active,
            onSelected: (_) => onSelect(i),
          );
        },
      ),
    );
  }
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          for (final r in historyRanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(r),
                selected: r == selected,
                onSelected: (_) => onSelect(r),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail});

  final ServerDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SectionCard(
          title: 'System',
          child: Column(
            children: [
              _infoRow(cs, 'Hostname', detail.hostname),
              _infoRow(cs, 'OS', '${detail.os} ${detail.version}'),
              if (detail.kernel != null)
                _infoRow(cs, 'Kernel', detail.kernel!),
              _infoRow(cs, 'Arch', detail.arch),
              _infoRow(cs, 'Uptime', formatUptime(detail.uptimeSeconds)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Performance',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metricTile(context, 'CPU', '${detail.cpu.toStringAsFixed(1)}%'),
              _metricTile(context, 'Memory',
                  '${detail.mem.toStringAsFixed(1)}% of ${formatGb(detail.memTotalGb)}'),
              _metricTile(context, 'Load',
                  detail.load.map((v) => v.toStringAsFixed(2)).join('  ')),
              _metricTile(
                  context, 'Processes', detail.processes.toString()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 90,
              child: Text('$label:',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _metricTile(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: (MediaQuery.sizeOf(context).width - 72) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ChartsTab extends StatelessWidget {
  const _ChartsTab({required this.history});

  final ServerHistory history;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SectionCard(
          title: 'CPU usage',
          child: MetricChart(
              points: history.cpu,
              color: cs.primary,
              unit: '%',
              max: 100),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Memory usage',
          child: MetricChart(
              points: history.mem,
              color: cs.tertiary,
              unit: '%',
              max: 100),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Processes',
          child: MetricChart(
              points: history.processes,
              color: cs.secondary,
              unit: '',
              max: null),
        ),
      ],
    );
  }
}

/// Line + area chart (no extra dependencies).
class MetricChart extends StatelessWidget {
  const MetricChart(
      {super.key,
      required this.points,
      required this.color,
      required this.unit,
      required this.max});

  final List<MetricPoint> points;
  final Color color;
  final String unit;
  final double? max;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = points.isEmpty ? 0.0 : points.last.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${last.toStringAsFixed(last >= 100 ? 0 : 1)}$unit',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(points: points, color: color, max: max,
                grid: cs.outlineVariant),
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(
      {required this.points, required this.color, required this.max, required this.grid});

  final List<MetricPoint> points;
  final Color color;
  final double? max;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var hi = max ?? points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    if (hi <= 0) hi = 1;
    final lo = 0.0;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Offset pos(int i) {
      final x = size.width * i / (points.length - 1);
      final y = size.height -
          (size.height * (points[i].value - lo) / (hi - lo));
      return Offset(x, y.clamp(0, size.height));
    }

    final line = Path()..moveTo(0, size.height);
    for (var i = 0; i < points.length; i++) {
      line.lineTo(pos(i).dx, pos(i).dy);
    }
    line.lineTo(size.width, size.height);
    line.close();
    canvas.drawPath(
        line, Paint()..color = color.withValues(alpha: 0.18));

    final stroke = Path()..moveTo(pos(0).dx, pos(0).dy);
    for (var i = 1; i < points.length; i++) {
      stroke.lineTo(pos(i).dx, pos(i).dy);
    }
    canvas.drawPath(
        stroke,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);

    final dot = pos(points.length - 1);
    canvas.drawCircle(dot, 3.5, Paint()..color = color);
    canvas.drawCircle(
        dot, 6, Paint()..color = color.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.points != points || old.color != color || old.max != max;
}

class _StorageTab extends StatelessWidget {
  const _StorageTab({required this.detail});

  final ServerDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final disk in detail.disks) ...[
          _SectionCard(
            title: '/dev/${disk.name}  •  ${formatGb(disk.sizeGb)}',
            child: Column(
              children: [
                if (disk.model != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(disk.model!,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                const SizedBox(height: 8),
                for (final p in disk.partitions)
                  _partitionBar(context, p),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _partitionBar(BuildContext context, DiskPartition p) {
    final cs = Theme.of(context).colorScheme;
    final barColor = p.usagePercent >= 90
        ? cs.error
        : p.usagePercent >= 75
            ? cs.tertiary
            : cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.mount != null
                      ? '${p.name}  →  ${p.mount}'
                      : p.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text('${p.usagePercent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (p.usagePercent / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatGb(p.usedGb)} used  •  ${formatGb(p.totalGb - p.usedGb)} free',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NetworkTab extends StatelessWidget {
  const _NetworkTab({required this.detail});

  final ServerDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final iface in detail.network) ...[
          _SectionCard(
            title: iface.name,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (iface.state != null)
                      _badge(context, iface.state!,
                          iface.state == 'up' ? cs.tertiary : cs.outline),
                    for (final ip in iface.ipv4)
                      _badge(context, ip, cs.primary),
                    if (iface.mac != null)
                      _badge(context, iface.mac!, cs.outline),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '↓ ${formatGb(iface.rxGb)}   ↑ ${formatGb(iface.txGb)}'
                  '${iface.speedMbps != null ? '   •   ${iface.speedMbps} Mbps' : ''}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _badge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _ProcessesTab extends StatelessWidget {
  const _ProcessesTab({required this.detail});

  final ServerDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final procs = [...detail.procs]..sort((a, b) => b.cpu.compareTo(a.cpu));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SectionCard(
          title: '${detail.processes} processes',
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Expanded(
                        child: Text('Process',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700))),
                    SizedBox(
                        width: 64,
                        child: Text('CPU %',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant))),
                    SizedBox(
                        width: 64,
                        child: Text('MEM %',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant))),
                  ],
                ),
              ),
              for (final p in procs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(p.name,
                              style: const TextStyle(fontSize: 13))),
                      SizedBox(
                          width: 64,
                          child: Text(p.cpu.toStringAsFixed(1),
                              textAlign: TextAlign.right,
                              style:
                                  const TextStyle(fontSize: 13))),
                      SizedBox(
                          width: 64,
                          child: Text(p.mem.toStringAsFixed(1),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
