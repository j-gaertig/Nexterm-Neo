import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/app_icons.dart';
import '../../../utils/script_protocol.dart';
import '../../renderers/script_execution_controller.dart';

enum StepVisual {
  pending,
  loading,
  progress,
  success,
  error,
  cancelled,
  skip,
  waiting,
}

/// Mobile replacement for the web-style overlay: a bottom execution dock with
/// a compact collapsed state and an expandable step/notice detail view.
///
/// It lives inside the script renderer (not the root navigator), so it never
/// covers other tabs and the terminal remains reachable behind it.
class ScriptExecutionDock extends StatefulWidget {
  final ScriptExecutionController controller;
  final String serverName;
  final VoidCallback onStop;
  final VoidCallback onClose;
  final VoidCallback onReconnect;

  const ScriptExecutionDock({
    super.key,
    required this.controller,
    required this.serverName,
    required this.onStop,
    required this.onClose,
    required this.onReconnect,
  });

  @override
  State<ScriptExecutionDock> createState() => _ScriptExecutionDockState();
}

class _ScriptExecutionDockState extends State<ScriptExecutionDock> {
  final _stepsScrollController = ScrollController();
  bool _expanded = false;
  int _lastStepNumber = 0;

  @override
  void initState() {
    super.initState();
    _lastStepNumber = widget.controller.currentStepNumber;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ScriptExecutionDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastStepNumber = widget.controller.currentStepNumber;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _stepsScrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final step = widget.controller.currentStepNumber;
    if (step != _lastStepNumber) {
      _lastStepNumber = step;
      if (_expanded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActiveStep();
        });
      }
    }
  }

  void _scrollToActiveStep() {
    if (!_stepsScrollController.hasClients) return;
    final index = math.max(0, widget.controller.currentStepNumber - 1);
    final target = (index * 52.0 - 32).clamp(
      0.0,
      _stepsScrollController.position.maxScrollExtent,
    );
    _stepsScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    setState(() => _expanded = expanded);
    if (expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveStep();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final screenHeight = MediaQuery.sizeOf(context).height;
        final maxHeight = math.min(screenHeight * 0.68, 560.0);
        return Material(
          color: cs.surfaceContainer,
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _expanded ? maxHeight : 132),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _grabber(cs),
                  _header(cs),
                  _progressBar(cs),
                  if (_expanded) ...[
                    Flexible(child: _expandedBody(cs)),
                    _actions(cs),
                  ] else if (widget.controller.notices.isNotEmpty)
                    _collapsedNotice(cs),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _grabber(ColorScheme cs) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _setExpanded(!_expanded),
    onVerticalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity < -150) {
        _setExpanded(true);
      } else if (velocity > 150) {
        _setExpanded(false);
      }
    },
    child: SizedBox(
      height: 18,
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );

  Widget _header(ColorScheme cs) {
    final controller = widget.controller;
    final visual = _statusVisual(cs);
    final subtitle = _subtitle();
    final progressLabel = _progressLabel();

    return InkWell(
      onTap: () => _setExpanded(!_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(child: visual.child),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.scriptName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11.5, color: cs.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (progressLabel != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: visual.color,
                  ),
                ),
              ),
            IconButton(
              onPressed: () => _setExpanded(!_expanded),
              tooltip: _expanded ? 'Collapse details' : 'Expand details',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _expanded ? AppIcons.chevronDown : AppIcons.chevronUp,
                size: 20,
                color: cs.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final controller = widget.controller;
    final phaseText = switch (controller.phase) {
      ScriptExecutionPhase.connecting => 'Connecting to script…',
      ScriptExecutionPhase.running =>
        controller.progressMessage.isNotEmpty
            ? controller.progressMessage
            : (controller.currentStepText ?? 'Running on ${widget.serverName}'),
      ScriptExecutionPhase.waitingForInput => 'Waiting for your input',
      ScriptExecutionPhase.cancelling => 'Stopping script…',
      ScriptExecutionPhase.cancelled => 'Stopped',
      ScriptExecutionPhase.completed => 'Completed successfully',
      ScriptExecutionPhase.failed => controller.errorMessage ?? 'Script failed',
      ScriptExecutionPhase.disconnected =>
        controller.errorMessage ?? 'Connection lost',
    };
    final stepCount = controller.stepCount;
    if (stepCount == 0) return phaseText;
    final step = controller.currentStepNumber.clamp(0, stepCount);
    return '$phaseText · Step $step of $stepCount';
  }

  String? _progressLabel() {
    final controller = widget.controller;
    final progress = controller.displayProgress;
    if (progress != null) return '$progress%';
    if (controller.stepCount > 0 && controller.currentStepNumber > 0) {
      return '${controller.currentStepNumber}/${controller.stepCount}';
    }
    return null;
  }

  Widget _progressBar(ColorScheme cs) {
    final controller = widget.controller;
    final progress = controller.displayProgress;
    final terminal = switch (controller.phase) {
      ScriptExecutionPhase.completed ||
      ScriptExecutionPhase.failed ||
      ScriptExecutionPhase.cancelled ||
      ScriptExecutionPhase.disconnected => true,
      _ => false,
    };
    final color = switch (controller.phase) {
      ScriptExecutionPhase.completed => cs.primary,
      ScriptExecutionPhase.failed ||
      ScriptExecutionPhase.disconnected => cs.error,
      ScriptExecutionPhase.cancelled => cs.tertiary,
      ScriptExecutionPhase.waitingForInput => cs.tertiary,
      _ => cs.primary,
    };
    // A terminal script must not keep an indeterminate animation alive. Use a
    // static full bar so the dock reflects that execution has stopped.
    final value = progress != null ? progress / 100 : (terminal ? 1.0 : null);
    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: cs.surfaceContainerHighest,
        color: color,
        minHeight: 3,
        semanticsLabel: 'Script progress',
      ),
    );
  }

  Widget _collapsedNotice(ColorScheme cs) {
    final notice = widget.controller.notices.last;
    final visual = _noticeVisual(notice.kind, cs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 9),
      child: Row(
        children: [
          Icon(visual.$1, size: 14, color: visual.$2),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              notice.message,
              style: TextStyle(fontSize: 11, color: cs.outline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedBody(ColorScheme cs) {
    final controller = widget.controller;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.alertCircle,
                    size: 16,
                    color: cs.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.errorMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          _stepsSection(cs),
          if (controller.notices.isNotEmpty) ...[
            const SizedBox(height: 12),
            _noticesSection(cs),
          ],
        ],
      ),
    );
  }

  Widget _stepsSection(ColorScheme cs) {
    final controller = widget.controller;
    if (controller.stepCount == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          controller.phase == ScriptExecutionPhase.connecting
              ? 'Waiting for the script to start…'
              : 'The script has not reported any steps.',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'STEPS',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: cs.outline,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Scrollbar(
            controller: _stepsScrollController,
            child: ListView.builder(
              controller: _stepsScrollController,
              shrinkWrap: true,
              itemCount: controller.stepCount,
              itemBuilder: (context, index) {
                final visual = _visualForStep(index);
                final isActive = index == controller.currentStepNumber - 1;
                return _stepRow(
                  context,
                  index,
                  controller.steps[index],
                  visual,
                  isActive,
                  cs,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  StepVisual _visualForStep(int index) {
    final controller = widget.controller;
    final failed = controller.failedStepIndex;
    if (failed != null) {
      if (index == failed) return StepVisual.error;
      if (index > failed) return StepVisual.skip;
    }
    final activeIndex = controller.currentStepNumber - 1;
    if (index < activeIndex) return StepVisual.success;
    if (index > activeIndex) return StepVisual.pending;
    if (controller.isCompleted) return StepVisual.success;
    if (controller.isCancelled) return StepVisual.cancelled;
    if (controller.isFailed) return StepVisual.error;
    if (controller.isDisconnected) return StepVisual.error;
    if (controller.isWaitingForInput) return StepVisual.waiting;
    return controller.progressPercent != null
        ? StepVisual.progress
        : StepVisual.loading;
  }

  Widget _stepRow(
    BuildContext context,
    int index,
    String description,
    StepVisual visual,
    bool isActive,
    ColorScheme cs,
  ) {
    final (icon, color) = switch (visual) {
      StepVisual.success => (AppIcons.check, cs.primary),
      StepVisual.error => (AppIcons.close, cs.error),
      StepVisual.cancelled => (AppIcons.stopCircleOutline, cs.tertiary),
      StepVisual.skip => (AppIcons.minus, cs.outline),
      StepVisual.pending => (AppIcons.checkboxBlankOutline, cs.outline),
      StepVisual.waiting => (AppIcons.alertCircle, cs.tertiary),
      StepVisual.progress ||
      StepVisual.loading => (AppIcons.chevronRight, cs.primary),
    };
    final showSpinner =
        isActive &&
        (visual == StepVisual.loading || visual == StepVisual.progress);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: isActive ? cs.primaryContainer.withValues(alpha: 0.55) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: showSpinner
                ? Padding(
                    padding: const EdgeInsets.all(3),
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: cs.primary,
                    ),
                  )
                : Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color:
                    visual == StepVisual.skip || visual == StepVisual.cancelled
                    ? cs.outline
                    : cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticesSection(ColorScheme cs) {
    final notices = widget.controller.notices.toList(growable: false);
    final visible = notices.length > 6
        ? notices.sublist(notices.length - 6)
        : notices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'NOTICES',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: cs.outline,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _noticeVisual(visible[i].kind, cs).$1,
                      size: 13,
                      color: _noticeVisual(visible[i].kind, cs).$2,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        visible[i].message,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (i != visible.length - 1) const SizedBox(height: 5),
              ],
            ],
          ),
        ),
      ],
    );
  }

  (IconData, Color) _noticeVisual(ScriptNoticeKind kind, ColorScheme cs) =>
      switch (kind) {
        ScriptNoticeKind.warning => (AppIcons.alertOutline, cs.tertiary),
        ScriptNoticeKind.info => (AppIcons.informationOutline, cs.primary),
        ScriptNoticeKind.success => (AppIcons.checkCircle, cs.primary),
      };

  Widget _actions(ColorScheme cs) {
    final controller = widget.controller;
    final buttons = <Widget>[];
    if (controller.isDisconnected) {
      buttons.add(
        FilledButton.icon(
          onPressed: widget.onReconnect,
          icon: const Icon(AppIcons.refresh, size: 16),
          label: const Text('Reconnect'),
        ),
      );
    }
    if (controller.canStop) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: widget.onStop,
          icon: const Icon(AppIcons.stopCircleOutline, size: 16),
          label: const Text('Stop script'),
          style: OutlinedButton.styleFrom(foregroundColor: cs.error),
        ),
      );
    }
    if (controller.isTerminal) {
      buttons.add(
        FilledButton.icon(
          onPressed: widget.onClose,
          icon: const Icon(AppIcons.close, size: 16),
          label: const Text('Close'),
        ),
      );
    }
    if (controller.canStop ||
        controller.phase == ScriptExecutionPhase.cancelling) {
      buttons.add(
        TextButton(
          onPressed: widget.onClose,
          child: const Text('Close session'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: buttons,
            ),
          ),
        ],
      ),
    );
  }

  ({IconData? icon, Widget? child, Color color}) _statusVisual(ColorScheme cs) {
    final phase = widget.controller.phase;
    if (phase == ScriptExecutionPhase.connecting ||
        phase == ScriptExecutionPhase.cancelling) {
      return (
        icon: null,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
        color: cs.primary,
      );
    }
    return switch (phase) {
      ScriptExecutionPhase.running => (
        icon: AppIcons.play,
        child: null,
        color: cs.primary,
      ),
      ScriptExecutionPhase.waitingForInput => (
        icon: AppIcons.alertCircle,
        child: null,
        color: cs.tertiary,
      ),
      ScriptExecutionPhase.cancelled => (
        icon: AppIcons.stopCircleOutline,
        child: null,
        color: cs.tertiary,
      ),
      ScriptExecutionPhase.completed => (
        icon: AppIcons.checkCircle,
        child: null,
        color: cs.primary,
      ),
      ScriptExecutionPhase.failed => (
        icon: AppIcons.alertCircle,
        child: null,
        color: cs.error,
      ),
      ScriptExecutionPhase.disconnected => (
        icon: AppIcons.wifiOff,
        child: null,
        color: cs.error,
      ),
      ScriptExecutionPhase.connecting || ScriptExecutionPhase.cancelling => (
        icon: null,
        child: null,
        color: cs.primary,
      ),
    };
  }
}
