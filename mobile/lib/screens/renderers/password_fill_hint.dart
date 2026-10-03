import 'package:flutter/material.dart';
import '../../utils/app_icons.dart';
import '../../utils/password_prompt.dart';
import '../../utils/password_prompt_localizations.dart';

/// Material counterpart of the web `PasswordFillHint` component
/// (`client/.../PasswordFillHint/PasswordFillHint.jsx`).
///
/// Same behaviour: shows the currently selected identity
/// (`paste {{username}} password` or `paste password`), tapping fills the
/// password, a cycle button switches identities when more than one is
/// attached (`selectedIndex+1/items.length` counter, tooltip = `cycle`
/// string), and a close button dismisses the hint (like web `Escape`).
///
/// Unlike the web overlay — which is absolutely positioned at the terminal
/// cursor — this renders as a bottom-anchored card above the keyboard
/// toolbar. On small touch screens a cursor-anchored popup would be covered
/// by the finger/keyboard; the content and interactions are identical.
class PasswordFillHint extends StatelessWidget {
  final List<PasswordIdentity> items;
  final int selectedIndex;
  final ValueChanged<dynamic> onFill;
  final VoidCallback onCycle;
  final VoidCallback onDismiss;

  const PasswordFillHint({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onFill,
    required this.onCycle,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final index = selectedIndex >= 0 && selectedIndex < items.length
        ? selectedIndex
        : 0;
    final item = items[index];
    final strings = PasswordPromptLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      // Announces appearance/disappearance. No container label: the fill
      // button carries its own label and would otherwise be read twice.
      liveRegion: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        // No SafeArea here: the caller wraps this in a SafeArea and disables
        // the bottom padding while the keyboard toolbar below already pads.
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => onFill(item.id),
                    icon: Icon(AppIcons.keyboard, size: 18),
                    label: Text(
                      strings.pasteFor(item.username.isNotEmpty
                          ? item.username
                          : null),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                if (items.length > 1) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: strings.cycle,
                    child: OutlinedButton(
                      onPressed: onCycle,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        minimumSize: const Size(0, 0),
                        tapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.chevronUp, size: 14),
                          Icon(AppIcons.chevronDown, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${index + 1}/${items.length}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(AppIcons.close, size: 18),
                  tooltip: MaterialLocalizations.of(context)
                      .closeButtonTooltip,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
