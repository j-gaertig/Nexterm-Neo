import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    if (!mounted || !_stepsScrollController.hasClients) return;
    final index = math.max(0, widget.controller.currentStepNumber - 1);
    final target = (index * 48.0 - 32).clamp(
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
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _expanded ? maxHeight : screenHeight,
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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

  Widget _header(ColorScheme cs) {
    final controller = widget.controller;
    final subtitle = _subtitle();
    final progressLabel = _progressLabel();
    final phaseColor = _phaseColor(cs);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -150) {
          _setExpanded(true);
        } else if (velocity > 150) {
          _setExpanded(false);
        }
      },
      child: Semantics(
        button: true,
        label: _expanded ? 'Collapse script details' : 'Expand script details',
        child: InkWell(
          onTap: () => _setExpanded(!_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
            child: Row(
              children: [
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
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11.5, color: cs.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (progressLabel != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    progressLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: phaseColor,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  _expanded ? 'Less' : 'Details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
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

  Color _phaseColor(ColorScheme cs) => switch (widget.controller.phase) {
    ScriptExecutionPhase.failed ||
    ScriptExecutionPhase.disconnected => cs.error,
    ScriptExecutionPhase.cancelled ||
    ScriptExecutionPhase.waitingForInput => cs.tertiary,
    _ => cs.primary,
  };

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
    final color = _phaseColor(cs);
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
    final color = _noticeColor(notice.kind, cs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                controller.errorMessage!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _stepsSection(cs),
          if (controller.notices.isNotEmpty) ...[
            const SizedBox(height: 14),
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
        const SizedBox(height: 7),
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
    int index,
    String description,
    StepVisual visual,
    bool isActive,
    ColorScheme cs,
  ) {
    final color = switch (visual) {
      StepVisual.success ||
      StepVisual.progress ||
      StepVisual.loading => cs.primary,
      StepVisual.error => cs.error,
      StepVisual.cancelled || StepVisual.waiting => cs.tertiary,
      StepVisual.skip || StepVisual.pending => cs.outline,
    };
    final muted = visual == StepVisual.skip || visual == StepVisual.cancelled;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? cs.primaryContainer.withValues(alpha: 0.55) : null,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: muted ? cs.outline : cs.onSurface,
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
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 3,
                      height: 13,
                      decoration: BoxDecoration(
                        color: _noticeColor(visible[i].kind, cs),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                if (i != visible.length - 1) const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _noticeColor(ScriptNoticeKind kind, ColorScheme cs) => switch (kind) {
    ScriptNoticeKind.warning => cs.tertiary,
    ScriptNoticeKind.info => cs.primary,
    ScriptNoticeKind.success => cs.primary,
  };

  Widget _actions(ColorScheme cs) {
    final controller = widget.controller;
    final buttons = <Widget>[];
    if (controller.isDisconnected) {
      buttons.add(
        FilledButton(
          onPressed: widget.onReconnect,
          style: _dockPrimaryStyle(),
          child: const Text('Reconnect'),
        ),
      );
    }
    if (controller.canStop) {
      buttons.add(
        OutlinedButton(
          onPressed: widget.onStop,
          style: _dockSecondaryStyle(
            cs,
          ).copyWith(foregroundColor: WidgetStatePropertyAll(cs.error)),
          child: const Text('Stop script'),
        ),
      );
    }
    if (controller.isTerminal) {
      buttons.add(
        FilledButton(
          onPressed: widget.onClose,
          style: _dockPrimaryStyle(),
          child: const Text('Close'),
        ),
      );
    }
    if (controller.canStop ||
        controller.phase == ScriptExecutionPhase.cancelling) {
      buttons.add(
        TextButton(
          onPressed: widget.onClose,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Close session'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            buttons[i],
          ],
        ],
      ),
    );
  }

  ButtonStyle _dockPrimaryStyle() => FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  ButtonStyle _dockSecondaryStyle(ColorScheme cs) => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
    side: BorderSide(color: cs.outlineVariant),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}
