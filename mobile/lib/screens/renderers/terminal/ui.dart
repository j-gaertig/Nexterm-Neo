part of '../terminal_renderer.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TerminalUi on _TerminalRendererState {
  void _showAISheet() {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => AIAssistantSheet(
        token: widget.token,
        sessionId: widget.session.sessionId,
        serverName: widget.session.server.name,
      ),
    );
  }

  void _showSnippets() {
    if (!mounted) return;
    final sm = widget.snippetManager;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => ListenableBuilder(
          listenable: sm,
          builder: (ctx, _) {
            if (sm.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (sm.error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        AppIcons.alertCircleOutline,
                        size: 48,
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load snippets',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              );
            }
            if (sm.snippets.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        AppIcons.codeBracesBox,
                        size: 48,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No snippets available',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(ctx).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.codeBraces,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Snippets',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(AppIcons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: sm.snippets.length,
                    itemBuilder: (ctx, i) {
                      final s = sm.snippets[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            ctx,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            AppIcons.console,
                            color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          s.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: s.description != null
                            ? Text(
                                s.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: Icon(AppIcons.chevronRight, size: 16),
                        onTap: () {
                          Navigator.pop(ctx);
                          _channel?.sink.add(s.command);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _errorBanner() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      color: colors.errorContainer,
      child: Row(
        children: [
          Icon(AppIcons.alertCircleOutline, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          IconButton(
            icon: Icon(AppIcons.close),
            onPressed: () => setState(() => _errorMessage = null),
            color: colors.onErrorContainer,
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordHintOverlay() {
    final media = MediaQuery.of(context);
    final visible =
        _passwordPromptVisible &&
        _passwordIdentities.isNotEmpty &&
        widget.terminalSettings.passwordPromptDetection;
    return Positioned(
      right: 12 + media.viewPadding.right,
      // The keyboard toolbar already applies the bottom inset when visible;
      // avoid padding twice.
      bottom: 12 + (_showKeyboardToolbar ? 0 : media.viewPadding.bottom),
      child: ExcludeSemantics(
        // AnimatedSwitcher keeps the outgoing button mounted for the fade-out;
        // make sure it cannot be tapped or announced during that window.
        excluding: !visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.85, end: 1).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            ),
            child: visible
                ? PasswordFillHint(
                    items: _passwordIdentities,
                    selectedIndex: _passwordHintIndex,
                    onFill: (id) => _fillIdentityPassword(id),
                    onCycle: () => _cyclePasswordHint(1),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyboardToolbar() {
    final ts = widget.terminalSettings;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _toolbarBtn('ESC'),
                const SizedBox(width: 8),
                _toolbarBtn('TAB'),
                const SizedBox(width: 8),
                for (final group in ts.groupOrder)
                  if (ts.isGroupEnabled(group)) ..._buildGroupButtons(group),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupButtons(ToolbarGroup group) {
    switch (group) {
      case ToolbarGroup.modifiers:
        return [
          _toolbarBtn('CTRL', isToggle: true, isActive: _ctrlPressed),
          const SizedBox(width: 8),
          _toolbarBtn('ALT', isToggle: true, isActive: _altPressed),
          const SizedBox(width: 16),
        ];
      case ToolbarGroup.signals:
        return [
          _toolbarBtn(
            '^C',
            onPressed: () => _sendTerminalKey('c', forceCtrl: true),
            compact: true,
          ),
          const SizedBox(width: 8),
          _toolbarBtn(
            '^Z',
            onPressed: () => _sendTerminalKey('z', forceCtrl: true),
            compact: true,
          ),
          const SizedBox(width: 8),
          _toolbarBtn(
            '^D',
            onPressed: () => _sendTerminalKey('d', forceCtrl: true),
            compact: true,
          ),
          const SizedBox(width: 16),
        ];
      case ToolbarGroup.arrows:
        return [
          _toolbarBtn(
            'UP',
            icon: AppIcons.arrowUp,
            holdKey: 'UP',
            compact: true,
          ),
          const SizedBox(width: 8),
          _toolbarBtn(
            'DOWN',
            icon: AppIcons.arrowDown,
            holdKey: 'DOWN',
            compact: true,
          ),
          const SizedBox(width: 8),
          _toolbarBtn(
            'LEFT',
            icon: AppIcons.arrowLeft,
            holdKey: 'LEFT',
            compact: true,
          ),
          const SizedBox(width: 8),
          _toolbarBtn(
            'RIGHT',
            icon: AppIcons.arrowRight,
            holdKey: 'RIGHT',
            compact: true,
          ),
          const SizedBox(width: 16),
        ];
      case ToolbarGroup.navigation:
        return [
          _toolbarBtn('HOME', compact: true),
          const SizedBox(width: 8),
          _toolbarBtn('END', compact: true),
          const SizedBox(width: 8),
          _toolbarBtn('PGUP', compact: true),
          const SizedBox(width: 8),
          _toolbarBtn('PGDN', compact: true),
          const SizedBox(width: 16),
        ];
      case ToolbarGroup.functionKeys:
        return [
          for (int i = 1; i <= 12; i++) ...[
            _toolbarBtn(
              'F$i',
              onPressed: () => _sendFunctionKey(i),
              compact: true,
            ),
            if (i < 12) const SizedBox(width: 8),
          ],
        ];
    }
  }

  Widget _toolbarBtn(
    String label, {
    IconData? icon,
    VoidCallback? onPressed,
    String? holdKey,
    bool isToggle = false,
    bool isActive = false,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final bgColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final fgColor = isActive
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      elevation: isActive ? 2 : 0,
      child: InkWell(
        onTap: holdKey == null
            ? onPressed ?? () => _sendSpecialKey(label)
            : () {},
        onTapDown: holdKey == null ? null : (_) => _startArrowHold(holdKey),
        onTapUp: holdKey == null ? null : (_) => _stopArrowRepeat(holdKey),
        onTapCancel: holdKey == null ? null : () => _stopArrowRepeat(holdKey),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: BoxConstraints(
            minWidth: compact ? 44 : 56,
            minHeight: 44,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: 10,
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 18, color: fgColor, semanticLabel: label)
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: compact ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: fgColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
