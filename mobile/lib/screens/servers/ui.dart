part of '../servers_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ServersUi on ServersScreenState {
  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    final total = _totalServers;
    final online = _onlineServers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppPageHeader(
            padding: EdgeInsets.zero,
            title: 'Servers',
            subtitle: !isLoading && errorMessage == null && total > 0
                ? '$online of $total online'
                : null,
            trailing: widget.authManager.accountManager.accounts.isNotEmpty
                ? InstanceSwitcher(
                    authManager: widget.authManager,
                    onManageInstances: () => pushPage(
                      context,
                      (_) =>
                          ServerAccountsScreen(authManager: widget.authManager),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (f) => setState(() => _searchFocused = f),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search servers...',
                      prefixIcon: Icon(AppIcons.magnify, size: 22),
                      suffixIcon: _hasText
                          ? IconButton(
                              icon: Icon(AppIcons.close, size: 20),
                              tooltip: 'Clear search',
                              onPressed: _clearSearch,
                            )
                          : null,
                      filled: true,
                      fillColor: _searchFocused
                          ? cs.surfaceContainerHighest
                          : cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildTagFilterButton(cs),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _openTagFilter() async {
    if (_allTags.isEmpty) return;
    final selection = await showTagFilterSheet(
      context,
      tags: _allTags,
      selected: _selectedTags,
    );
    if (selection == null || !mounted) return;
    setState(() {
      _selectedTags
        ..clear()
        ..addAll(selection);
      _filterFolders();
    });
  }

  Widget _buildTagFilterButton(ColorScheme cs) {
    final active = _selectedTags.isNotEmpty;
    final enabled = _allTags.isNotEmpty;
    final background = active
        ? cs.primary
        : (enabled ? cs.surfaceContainerHigh : cs.surfaceContainerLow);
    final foreground = active
        ? cs.onPrimary
        : (enabled ? cs.onSurfaceVariant : cs.outline);
    final count = _selectedTags.length;

    return Tooltip(
      message: active
          ? 'Filter by tags ($count active)'
          : (enabled ? 'Filter by tags' : 'No tags available'),
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: active,
        label: 'Filter by tags',
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('tag-filter-button'),
            onTap: enabled ? _openTagFilter : null,
            child: SizedBox.square(
              dimension: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(AppIcons.filterVariant, size: 20, color: foreground),
                  if (active)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.onPrimary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(ColorScheme cs, TextTheme tt) =>
      AppErrorState(message: errorMessage!, onRetry: _loadData);

  Widget _buildEmpty(ColorScheme cs, TextTheme tt) => RefreshIndicator(
    onRefresh: _refreshData,
    child: LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: AppEmptyState(
              icon: AppIcons.serverOff,
              title: _hasActiveFilter ? 'No results' : 'No servers yet',
              message: _hasActiveFilter
                  ? 'Try a different search term or clear filters'
                  : 'Add servers with the + button',
              action: _hasActiveFilter
                  ? TextButton.icon(
                      onPressed: () {
                        _selectedTags.clear();
                        _clearSearch();
                      },
                      icon: const Icon(AppIcons.close, size: 16),
                      label: const Text('Clear filters'),
                    )
                  : null,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildList(ColorScheme cs) {
    final navInset = FloatingNavigationBarInset.of(context);
    if (!widget.serverViewSettings.isGrid) {
      return RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            bottom: 16 + navInset,
            top: 4,
          ),
          itemCount: filteredFolders.length,
          itemBuilder: (_, i) {
            final e = filteredFolders[i];
            if (e is ServerFolder) {
              return _buildFolder(
                e,
                0,
                key: ValueKey(
                  'folder:${e.id ?? e.name}:${e.type}:${e.position}',
                ),
              );
            }
            if (e is Server) {
              return _buildServer(
                e,
                0,
                key: ValueKey('server:${e.id ?? e.name}'),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      );
    }
    final topServers = filteredFolders.whereType<Server>().toList();
    final rest = filteredFolders.where((e) => e is! Server).toList();
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          bottom: 16 + navInset,
          top: 4,
        ),
        itemCount: (topServers.isNotEmpty ? 1 : 0) + rest.length,
        itemBuilder: (_, i) {
          if (topServers.isNotEmpty && i == 0) {
            return _buildServerGrid(topServers, 0);
          }
          final e = rest[topServers.isNotEmpty ? i - 1 : i];
          return _buildEntry(e, 0);
        },
      ),
    );
  }

  Widget _buildEntry(dynamic entry, int depth) {
    if (entry is ServerFolder) {
      return _buildFolder(
        entry,
        depth,
        key: ValueKey(
          'folder:${entry.id ?? entry.name}:${entry.type}:${entry.position}',
        ),
      );
    }
    if (entry is Server) {
      return _buildServer(
        entry,
        depth,
        key: ValueKey('server:${entry.id ?? entry.name}'),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFolder(ServerFolder folder, int depth, {Key? key}) {
    final cs = Theme.of(context).colorScheme;
    final hasEntries = folder.entries.isNotEmpty;
    final open = _expanded.contains(_folderKey(folder));
    final serverCount =
        folder.allServers.length +
        folder.allFolders.fold(0, (sum, f) => sum + _countServers(f));
    final cappedDepth = depth.clamp(0, 2);

    final (icon, color) = folder.isOrganization
        ? (open ? AppIcons.brandDomain : AppIcons.brandDomainOff, cs.primary)
        : folder.isPveNode
        ? (AppIcons.brandServer, cs.tertiary)
        : (open ? AppIcons.brandFolderOpen : AppIcons.brandFolder, cs.primary);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 12.0 + cappedDepth * 16,
            right: 12,
            top: depth == 0 ? 4 : 0,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: hasEntries ? () => _toggleFolder(folder) : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            folder.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (serverCount > 0)
                            Text(
                              '$serverCount server${serverCount == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 11, color: cs.outline),
                            ),
                        ],
                      ),
                    ),
                    if (hasEntries)
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          AppIcons.chevronDown,
                          color: cs.outline,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: open
              ? Column(
                  children: [
                    if (folder.allServers.isNotEmpty)
                      widget.serverViewSettings.isGrid
                          ? _buildServerGrid(folder.allServers, depth + 1)
                          : Column(
                              children: [
                                for (final s in folder.allServers)
                                  _buildServer(
                                    s,
                                    depth + 1,
                                    key: ValueKey('server:${s.id ?? s.name}'),
                                  ),
                              ],
                            ),
                    for (final f in folder.allFolders)
                      _buildFolder(
                        f,
                        depth + 1,
                        key: ValueKey(
                          'folder:${f.id ?? f.name}:${f.type}:${f.position}',
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
          crossFadeState: open
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }

  int _effectiveColumns(int wanted, double availableWidth) {
    final fit =
        ((availableWidth + ServersScreenState._gridSpacing) /
                (ServersScreenState._minGridCardWidth +
                    ServersScreenState._gridSpacing))
            .floor();
    return math.min(
      wanted,
      math.max(2, math.min(fit, ServerViewSettings.maxColumns)),
    );
  }

  Widget _buildServerGrid(List<Server> servers, int depth) {
    final cappedDepth = depth.clamp(0, 2);
    return Padding(
      padding: EdgeInsets.only(
        left: 12.0 + cappedDepth * 16,
        right: 12,
        top: 4,
        bottom: 4,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _effectiveColumns(
            widget.serverViewSettings.gridColumns,
            constraints.maxWidth,
          );
          final dense = columns >= 3;
          final rows = <Widget>[];
          for (var start = 0; start < servers.length; start += columns) {
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0)
                        const SizedBox(width: ServersScreenState._gridSpacing),
                      Expanded(
                        child: start + column < servers.length
                            ? ServerGridCard(
                                key: ValueKey(
                                  'grid:${servers[start + column].id ?? servers[start + column].name}',
                                ),
                                server: servers[start + column],
                                icon: _serverIcon(servers[start + column]),
                                dense: dense,
                                onTap: () =>
                                    _connectToServer(servers[start + column]),
                                onLongPress: () =>
                                    _showServerMenu(servers[start + column]),
                                onTagTap: (tag) => setState(() {
                                  _selectedTags.contains(tag.id)
                                      ? _selectedTags.remove(tag.id)
                                      : _selectedTags.add(tag.id);
                                  _filterFolders();
                                }),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
            if (start + columns < servers.length) {
              rows.add(const SizedBox(height: ServersScreenState._gridSpacing));
            }
          }
          return Column(children: rows);
        },
      ),
    );
  }

  Widget _buildServer(Server server, int depth, {Key? key}) {
    final cs = Theme.of(context).colorScheme;
    final offline = !server.isRunning || server.disabled;
    final pve = server.isPve;
    final icon = _serverIcon(server);

    final bg = offline
        ? mutedTileBackground(cs)
        : pve
        ? cs.tertiaryContainer
        : cs.primaryContainer;
    final fg = offline
        ? mutedTileForeground(cs)
        : pve
        ? cs.onTertiaryContainer
        : cs.onPrimaryContainer;

    String? sub;
    final ip = server.ip.trim();
    if (server.disabled) {
      sub = ip.isNotEmpty && ip != 'N/A' ? 'Disabled · $ip' : 'Disabled';
    } else if (pve && server.status != null) {
      sub = ip.isNotEmpty && ip != 'N/A'
          ? '${server.status} · $ip'
          : server.status;
    } else if (ip.isNotEmpty && ip != 'N/A') {
      sub = ip;
    }
    final tags = server.tags ?? const <Tag>[];
    final shownTags = tags.take(3).toList();
    final extraTags = tags.length - shownTags.length;
    final cappedDepth = depth.clamp(0, 2);
    final statusLabel = server.disabled
        ? 'Disabled'
        : (offline ? 'Offline' : 'Online');

    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: '${server.name}, $statusLabel${sub != null ? ', $sub' : ''}',
        child: Padding(
          key: key,
          padding: EdgeInsets.only(
            left: 12.0 + cappedDepth * 16,
            right: 12,
            top: 3,
            bottom: 3,
          ),
          child: AppCard(
            key: ValueKey('server-tile-${server.id ?? server.name}'),
            onTap: () => _connectToServer(server),
            onLongPress: () => _showServerMenu(server),
            radius: AppRadii.control,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Icon(icon, color: fg, size: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        server.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: offline ? mutedServerText(cs) : cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sub != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            sub,
                            style: TextStyle(
                              fontSize: 12,
                              color: offline ? mutedServerText(cs) : cs.outline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final t in shownTags)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: _parseColor(t.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (extraTags > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              '+$extraTags',
                              style: TextStyle(fontSize: 10, color: cs.outline),
                            ),
                          ),
                      ],
                    ),
                  ),
                Icon(AppIcons.chevronRight, color: cs.outlineVariant, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
