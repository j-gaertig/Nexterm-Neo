part of '../sftp_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _SftpUi on _SftpRendererState {
  Widget _buildMainContent() {
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top),
        _buildHeader(),
        _buildPathBar(),
        if (_errorMessage != null) _buildErrorBanner(),
        if (_showProgress) const LinearProgressIndicator(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildWithSelectionBar() {
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top),
        _buildSelectionBar(),
        _buildPathBar(),
        if (_errorMessage != null) _buildErrorBanner(),
        if (_showProgress) const LinearProgressIndicator(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(AppIcons.folderOutline, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.session.server.name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_connected)
            IconButton(
              icon: Icon(AppIcons.refresh, size: 20),
              onPressed: _refresh,
              visualDensity: VisualDensity.compact,
              tooltip: 'Refresh',
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(icon: Icon(AppIcons.close), onPressed: _cancelSelection),
          Text(
            '${_selectedIndices.length} selected',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(AppIcons.downloadOutline),
            onPressed: _selectedIndices.isNotEmpty
                ? () {
                    final entries = _selectedEntries();
                    if (entries.isEmpty) return;
                    _downloadMultiple(entries);
                    _cancelSelection();
                  }
                : null,
            tooltip: 'Download',
          ),
          IconButton(
            icon: Icon(AppIcons.pencilOutline),
            onPressed: _selectedIndices.length == 1
                ? () {
                    final entries = _selectedEntries();
                    if (entries.isEmpty) return;
                    _showRenameDialog(entries.first, _currentPath, _sessionId);
                  }
                : null,
            tooltip: 'Rename',
          ),
          IconButton(
            icon: Icon(AppIcons.deleteOutline),
            onPressed: _selectedIndices.isNotEmpty ? _deleteSelected : null,
            tooltip: 'Delete',
            color: cs.error,
          ),
        ],
      ),
    );
  }

  Widget _buildPathBar() {
    final theme = Theme.of(context);
    final segments = _pathSegments();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(AppIcons.arrowLeft, size: 20),
            onPressed: _historyIndex > 0 ? _goBack : null,
            visualDensity: VisualDensity.compact,
            tooltip: 'Back',
          ),
          IconButton(
            icon: Icon(AppIcons.arrowUp, size: 20),
            onPressed: segments.isNotEmpty ? _goUp : null,
            visualDensity: VisualDensity.compact,
            tooltip: 'Up',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _buildBreadcrumb('/', _rootPath),
                  for (int i = 0; i < segments.length; i++) ...[
                    Icon(
                      AppIcons.chevronRight,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                    _buildBreadcrumb(
                      segments[i],
                      _joinPath(segments.sublist(0, i + 1)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(String label, String path) {
    final isActive = path == _currentPath;
    final theme = Theme.of(context);
    return InkWell(
      onTap: isActive ? null : () => _navigateTo(path),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            AppIcons.alertCircleOutline,
            color: Theme.of(context).colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: Icon(AppIcons.close, size: 18),
            onPressed: () => setState(() => _errorMessage = null),
            color: Theme.of(context).colorScheme.onErrorContainer,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_connected && _loading) {
      return ConnectionLoader(
        visible: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_entries.isEmpty) {
      return LayoutBuilder(
        builder: (_, constraints) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      AppIcons.folderOpen,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Empty directory',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView.builder(
        key: PageStorageKey<String>('sftp-list-$_sessionId-$_listedPath'),
        controller: _scrollController,
        itemCount: _entries.length,
        itemBuilder: (ctx, index) => _buildEntryTile(index),
      ),
    );
  }

  Widget _buildEntryTile(int index) {
    final entry = _entries[index];
    final theme = Theme.of(context);
    final isSelected = _selectedIndices.contains(index);
    final isDimmed =
        entry.name.startsWith('.') && widget.sftpSettings.dimHiddenFiles;

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _onEntryTap(entry, index),
        onLongPress: () => _onEntryLongPress(index),
        child: Opacity(
          opacity: isDimmed ? 0.55 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (_selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      isSelected
                          ? AppIcons.checkboxMarked
                          : AppIcons.checkboxBlankOutline,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      size: 22,
                    ),
                  ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getFileIconColor(
                      entry,
                      theme,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getFileIcon(entry),
                    color: _getFileIconColor(entry, theme),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (!entry.isDir) entry.formattedSize,
                          if (entry.mtime > 0) _formatDate(entry.modifiedDate),
                        ].join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_selectionMode)
                  IconButton(
                    icon: Icon(
                      AppIcons.dotsVertical,
                      color: theme.colorScheme.outline,
                      size: 20,
                    ),
                    onPressed: () => _showEntryActions(entry),
                    visualDensity: VisualDensity.compact,
                  ),
                if (!_selectionMode && entry.isDir)
                  Icon(
                    AppIcons.chevronRight,
                    color: theme.colorScheme.outline,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
