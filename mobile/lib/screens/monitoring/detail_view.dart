import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/monitoring.dart';
import '../../services/monitoring_service.dart';
import '../../utils/api_exception.dart';
import '../../utils/app_icons.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/floating_navigation_bar.dart';
import 'tabs.dart';

/// Detail pages of one monitored server, matching the web client:
/// Overview, Charts, Storage, Network and Processes (Overview, Charts and
/// Nodes for Proxmox clusters).
class MonitoringDetailView extends StatefulWidget {
  final M server;
  final String? Function() tokenProvider;
  final IconData icon;
  final VoidCallback onBack;

  const MonitoringDetailView({
    super.key,
    required this.server,
    required this.tokenProvider,
    required this.icon,
    required this.onBack,
  });

  @override
  State<MonitoringDetailView> createState() => _MonitoringDetailViewState();
}

class _MonitoringDetailViewState extends State<MonitoringDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  M? _detail;
  bool _loading = true;
  String? _error;
  String _range = '1h';
  Timer? _timer;
  int _generation = 0;
  bool _visible = true;

  bool get _isPve => widget.server.isPVE;

  List<(String, String)> get _tabDefs => _isPve
      ? const [
          ('overview', 'Overview'),
          ('charts', 'Charts'),
          ('nodes', 'Nodes'),
        ]
      : const [
          ('overview', 'Overview'),
          ('charts', 'Charts'),
          ('storage', 'Storage'),
          ('network', 'Network'),
          ('processes', 'Processes'),
        ];

  IconData _tabIcon(String id) => switch (id) {
    'charts' => AppIcons.chartBoxOutline,
    'storage' => AppIcons.databaseOutline,
    'network' => AppIcons.serverNetwork,
    'processes' => AppIcons.console,
    'nodes' => AppIcons.layers,
    _ => AppIcons.monitor,
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabDefs.length, vsync: this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_visible) _load(silent: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_generation;
    if (!silent && _detail == null) setState(() => _loading = true);
    try {
      final token = widget.tokenProvider();
      if (token == null) throw ApiException('Not authenticated');
      final detail = await MonitoringService.getDetails(
        token,
        widget.server['id'],
        range: _range,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        // Keep showing old data on a failed background refresh.
        if (_detail == null) {
          _error = friendlyApiError(e, fallback: 'Could not load details.');
        }
        _loading = false;
      });
    }
  }

  void _setRange(String range) {
    if (range == _range) return;
    setState(() => _range = range);
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.server;
    return Column(
      key: const ValueKey('detail'),
      children: [
        AppSubPageHeader(
          title: s.str('name', 'Unknown'),
          subtitle: s['ip'] != null ? s.str('ip') : null,
          onBack: widget.onBack,
          trailing: AppIconBox(
            icon: widget.icon,
            size: 36,
            background: _isPve ? cs.tertiaryContainer : cs.primaryContainer,
            foreground: _isPve ? cs.onTertiaryContainer : cs.onPrimaryContainer,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: appBorderColor(cs)),
            ),
            padding: const EdgeInsets.all(4),
            child: AppIconTabBar(
              controller: _tabs,
              scrollable: true,
              height: 36,
              tabs: [
                for (final t in _tabDefs)
                  AppTabItem(label: t.$2, icon: _tabIcon(t.$1)),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [for (final t in _tabDefs) _page(t.$1)],
                ),
        ),
      ],
    );
  }

  Widget _page(String id) {
    final detail = _detail ?? M();
    final latest = detail.sub('latest').raw.isNotEmpty
        ? detail.sub('latest')
        : (detail.list('data').isNotEmpty ? detail.list('data').first : M());
    final isWindows = latest.sub('osInfo').str('platform') == 'windows';

    final Widget body = switch (id) {
      'overview' => OverviewTab(latest: latest, isPve: _isPve),
      'charts' => ChartsTab(
        data: detail.list('data'),
        isPve: _isPve,
        range: _range,
        onRangeChanged: _setRange,
      ),
      'storage' => StorageTab(disks: latest.list('disk'), isWindows: isWindows),
      'network' => NetworkTab(interfaces: latest.list('network')),
      'nodes' => NodesTab(nodes: latest.sub('osInfo').list('nodes')),
      'processes' => ProcessesTab(processes: latest.list('processList')),
      _ => const SizedBox.shrink(),
    };

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + FloatingNavigationBarInset.of(context),
        ),
        children: [body],
      ),
    );
  }
}
