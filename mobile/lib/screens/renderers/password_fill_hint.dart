import 'package:flutter/material.dart';
import '../../utils/app_icons.dart';
import '../../utils/password_prompt.dart';
import '../../utils/password_prompt_localizations.dart';

/// Compact floating key button shown while a password prompt is detected.
///
/// This replaces the former full-width fill card above the keyboard toolbar.
/// It is a small, slightly translucent rounded button with only a key icon,
/// anchored to the bottom-right of the terminal directly above the toolbar.
/// Tapping fills the selected identity's password; long-pressing cycles
/// through identities when more than one is attached.
///
/// The detection and fill behaviour still mirror the web `PasswordFillHint`
/// (`client/.../PasswordFillHint/PasswordFillHint.jsx`), but the mobile
/// presentation stays out of the terminal's way.
class PasswordFillHint extends StatelessWidget {
  static const double size = 44;

  final List<PasswordIdentity> items;
  final int selectedIndex;
  final ValueChanged<dynamic> onFill;
  final VoidCallback onCycle;

  const PasswordFillHint({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onFill,
    required this.onCycle,
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
    final canCycle = items.length > 1;
    final radius = BorderRadius.circular(14);

    return Semantics(
      button: true,
      liveRegion: true,
      label: strings.pasteFor(item.username.isNotEmpty ? item.username : null),
      hint: canCycle ? strings.cycleLongPress : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (item.username.isNotEmpty) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 180),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                item.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              // Keep the terminal visible behind the translucent button.
              color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onFill(item.id),
                onLongPress: canCycle ? onCycle : null,
                // Keep the terminal focused so the keyboard stays open.
                canRequestFocus: false,
                borderRadius: radius,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    AppIcons.key,
                    size: 20,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
