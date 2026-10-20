import 'package:flutter/material.dart';

import '../../../utils/app_icons.dart';

enum StepVisual { pending, loading, progress, success, error, skip }

/// Bottom-anchored progress overlay, a faithful port of the web
/// `ScriptOverlay.jsx`: top progress bar, main row (status icon, script name,
/// current step, step dots, cancel), expandable step list.
///
/// Purely presentational — all state comes in via the constructor, which keeps
/// it widget-testable.
class ScriptOverlay extends StatefulWidget {
  final String scriptName;
  final List<String?> steps;
  final int? failedStep;
  final bool isCompleted;
  final int currentStep;
  final int? currentProgress;
  final StepVisual Function(int index) visualForStep;
  final VoidCallback onCancel;
  final VoidCallback? onClose;

  const ScriptOverlay({
    super.key,
    required this.scriptName,
    required this.steps,
    required this.failedStep,
    required this.isCompleted,
    required this.currentStep,
    required this.currentProgress,
    required this.visualForStep,
    required this.onCancel,
    this.onClose,
  });

  @override
  State<ScriptOverlay> createState() => _ScriptOverlayState();
}

class _ScriptOverlayState extends State<ScriptOverlay> {
  bool _isExpanded = false;

  Color _colorFor(ColorScheme cs, StepVisual visual) => switch (visual) {
        StepVisual.success => Colors.green,
        StepVisual.error => cs.error,
        StepVisual.loading || StepVisual.progress || StepVisual.pending => cs.primary,
        StepVisual.skip => cs.outline,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final failed = widget.failedStep != null;
    final completed = widget.isCompleted;

    final Color statusColor = failed ? cs.error : (completed ? Colors.green : cs.primary);
    final IconData statusIcon = failed
        ? AppIcons.alertCircle
        : (completed ? AppIcons.checkCircle : AppIcons.informationOutline);

    final currentStepIndex = widget.currentStep - 1;
    final currentStepText = (currentStepIndex >= 0 && currentStepIndex < widget.steps.length
            ? widget.steps[currentStepIndex]
            : null) ??
        (widget.steps.isNotEmpty ? widget.steps.last : null) ??
        'Running...';

    final overallProgress = completed
        ? 100
        : ((currentStepIndex / (widget.steps.isEmpty ? 1 : widget.steps.length)) * 100).round().clamp(0, 100);
    final progressValue = widget.currentProgress ?? overallProgress;

    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: LinearProgressIndicator(
            value: progressValue / 100,
            minHeight: 3,
            backgroundColor: cs.outlineVariant.withValues(alpha: 0.4),
            color: failed ? cs.error : (completed ? Colors.green : cs.primary),
          ),
        ),
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(children: [
              failed || completed
                  ? Icon(statusIcon, size: 22, color: statusColor)
                  : SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: statusColor)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.scriptName,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(failed ? 'Error' : (completed ? 'Completed' : currentStepText),
                    style: tt.bodySmall?.copyWith(color: cs.outline),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              ..._stepDots(cs),
              if (!completed && !failed) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(AppIcons.stop, size: 18),
                  tooltip: 'Cancel script',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  color: cs.error,
                  onPressed: widget.onCancel,
                ),
              ] else if (widget.onClose != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(AppIcons.close, size: 18),
                  tooltip: 'Close session',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  color: cs.outline,
                  onPressed: widget.onClose,
                ),
              ],
              Icon(
                _isExpanded ? AppIcons.chevronDown : AppIcons.chevronUp,
                size: 18, color: cs.outline,
              ),
            ]),
          ),
        ),
        if (_isExpanded) ...[
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(children: [
              Text('Steps',
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.outline)),
              const Spacer(),
              Text('$currentStepIndex / ${widget.steps.length}',
                  style: tt.labelMedium?.copyWith(color: cs.outline)),
            ]),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              itemCount: widget.steps.length,
              itemBuilder: (_, index) {
                final text = widget.steps[index];
                if (text == null) return const SizedBox.shrink();
                final visual = widget.visualForStep(index);
                final color = _colorFor(cs, visual);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    _stepIndicator(index, visual, color, cs),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text,
                        style: TextStyle(fontSize: 13, color: cs.onSurface, height: 1.3))),
                  ]),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }

  List<Widget> _stepDots(ColorScheme cs) {
    final visible = widget.steps.take(8).toList();
    final dots = <Widget>[
      for (var i = 0; i < visible.length; i++)
        Container(
          width: 9, height: 9,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (widget.visualForStep(i)) {
              StepVisual.success => Colors.green,
              StepVisual.error => cs.error,
              StepVisual.loading || StepVisual.progress => cs.primary,
              StepVisual.pending => cs.outlineVariant,
              StepVisual.skip => cs.outlineVariant.withValues(alpha: 0.5),
            },
          ),
        ),
    ];
    if (widget.steps.length > 8) {
      dots.add(Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text('+${widget.steps.length - 8}',
            style: TextStyle(fontSize: 10, color: cs.outline, fontWeight: FontWeight.w600)),
      ));
    }
    return dots;
  }

  Widget _stepIndicator(int index, StepVisual visual, Color color, ColorScheme cs) {
    switch (visual) {
      case StepVisual.success:
        return Icon(AppIcons.checkCircle, size: 18, color: color);
      case StepVisual.error:
        return Icon(AppIcons.cancel, size: 18, color: color);
      case StepVisual.loading:
        return SizedBox(width: 15, height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: color));
      case StepVisual.progress:
        return SizedBox(width: 15, height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: color,
              value: (widget.currentProgress ?? 0) / 100,
            ));
      case StepVisual.skip:
        return Icon(AppIcons.minus, size: 18, color: color);
      case StepVisual.pending:
        return Container(
          width: 17, height: 17,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.outlineVariant, width: 1.4)),
          child: Text('${index + 1}', style: TextStyle(fontSize: 9, color: cs.outline)),
        );
    }
  }
}
