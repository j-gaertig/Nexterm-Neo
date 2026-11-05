import '../widgets/app_ui.dart';
import 'monitoring/detail_view.dart';
import '../utils/api_exception.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_icons.dart';
import '../models/monitoring.dart';
import '../services/monitoring_service.dart';
import '../utils/auth_manager.dart';
import '../utils/muted_colors.dart';
import '../widgets/floating_navigation_bar.dart';

class MonitoringScreen extends StatefulWidget {
  final AuthManager authManager;

  /// Scroll controller of the root list, owned by the navigation shell so the
  /// active navigation destination can scroll back to the top.
  final ScrollController? scrollController;

  const MonitoringScreen({
    super.key,
    required this.authManager,
    this.scrollController,
  });
  @override
  State<MonitoringScreen> createState() => MonitoringScreenState();
}

class MonitoringScreenState extends State<MonitoringScreen> {
  List<M> _servers = [];
  M? _selected;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  // Inactive tabs stay alive but their tickers are muted; pause polling there.
  bool _visible = true;
  String? _activeAccountId;
  int _loadGeneration = 0;

  bool goBack() {
    if (_selected != null) {
      setState(() {
        _selected = null;
      });
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _activeAccountId = widget.authManager.accountManager.activeAccount?.id;
    widget.authManager.addListener(_onAuthChanged);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_visible) _load(silent: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    // Refresh once when the tab becomes visible again.
    if (visible && !_visible && !_loading) _load(silent: true);
    _visible = visible;
  }

  @override
  void dispose() {
    widget.authManager.removeListener(_onAuthChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onAuthChanged() {
    final accountId = widget.authManager.accountManager.activeAccount?.id;
    if (accountId == _activeAccountId) return;
    _activeAccountId = accountId;
    if (!mounted) return;
    setState(() {
      _servers = [];
      _selected = null;
      _error = null;
      _loading = true;
    });
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    if (!silent) setState(() => _loading = true);
    try {
      final token =
          widget.authManager.sessionToken ??
          (throw Exception('Not authenticated'));
      final servers = await MonitoringService.getAll(token);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _servers = servers;
        _loading = false;
        _error = null;
        final selected = _selected;
        if (selected != null) {
          _selected = servers.firstWhere(
            (s) => s['id'] == selected['id'],
            orElse: () => selected,
          );
        }
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = friendlyApiError(
            e,
            fallback: 'Failed to load monitoring data.',
          );
          _loading = false;
        });
      }
    }
  }

  void _loadDetails(M server) => setState(() => _selected = server);

  int get _onlineCount =>
      _servers.where((s) => s.hasData && s.error == null).length;

  IconData _monitorIcon(M s) {
    if (s.isPVE) return AppIcons.serverNetwork;
    final icon = s['icon']?.toString();
    if (icon != null && icon.startsWith('mdi') && icon.length > 3) {
      final camel = icon.substring(3, 4).toLowerCase() + icon.substring(4);
      final hit = AppIcons.resolveBackendIcon(camel);
      if (hit != null) return hit;
    }
    return AppIcons.server;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _selected != null ? _detailsView() : _mainView(),
        ),
      ),
    );
  }

  Widget _mainView() => Column(
    key: const ValueKey('list'),
    children: [
      _buildHeader(),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _errView()
            : _servers.isEmpty
            ? _emptyView()
            : _listView(),
      ),
    ],
  );

  Widget _buildHeader() => AppPageHeader(
    title: 'Monitoring',
    subtitle: !_loading && _error == null && _servers.isNotEmpty
        ? '$_onlineCount of ${_servers.length} reporting'
        : null,
  );

  Widget _errView() => AppErrorState(message: _error!, onRetry: _load);

  Widget _emptyView() => RefreshIndicator(
    onRefresh: () => _load(silent: true),
    child: LayoutBuilder(
      builder: (context, constraints) => ListView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: const AppEmptyState(
              icon: AppIcons.chartBoxOutline,
              title: 'No monitoring data',
              message: 'Enable monitoring from the web dashboard',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _listView() => RefreshIndicator(
    onRefresh: () => _load(silent: true),
    child: ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: 16 + FloatingNavigationBarInset.of(context),
        top: 4,
      ),
      itemCount: _servers.length,
      itemBuilder: (_, i) => _serverCard(_servers[i]),
    ),
  );

  Widget _serverCard(M s) {
    final cs = Theme.of(context).colorScheme;
    final pve = s.isPVE;
    final hasErr = s.error != null && !s.hasData;

    final bg = hasErr
        ? mutedTileBackground(cs)
        : pve
        ? cs.tertiaryContainer
        : cs.primaryContainer;
    final fg = hasErr
        ? mutedTileForeground(cs)
        : pve
        ? cs.onTertiaryContainer
        : cs.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: appBorderSide(cs),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _loadDetails(s),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(_monitorIcon(s), color: fg, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.str('name', 'Unknown'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (s['ip'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                s.str('ip'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(AppIcons.chevronRight, color: cs.outline, size: 18),
                  ],
                ),
                if (s.hasData) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _miniGauge('CPU', s.cpu ?? 0, cs)),
                      const SizedBox(width: 10),
                      Expanded(child: _miniGauge('MEM', s.mem ?? 0, cs)),
                    ],
                  ),
                ] else if (s.error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(AppIcons.alertOutline, size: 14, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.error!,
                            style: TextStyle(fontSize: 11, color: cs.error),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniGauge(String label, double v, ColorScheme cs) {
    final color = v > 80
        ? cs.error
        : v > 60
        ? Colors.orange
        : cs.primary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: appBorderColor(cs)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.outline,
                ),
              ),
              Text(
                '${v.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (v / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHigh,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsView() {
    final s = _selected!;
    return MonitoringDetailView(
      key: ValueKey('detail-${s['id']}'),
      server: s,
      icon: _monitorIcon(s),
      tokenProvider: () => widget.authManager.sessionToken,
      onBack: goBack,
    );
  }
}
