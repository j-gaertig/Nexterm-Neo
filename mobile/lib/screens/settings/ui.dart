import 'package:flutter/material.dart';

import '../../utils/app_icons.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/floating_navigation_bar.dart';

/// Page frame shared by every settings sub page: back header, scrollable body
/// with room for the floating navigation bar.
class SettingsPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? headerAction;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.headerAction,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        24 + FloatingNavigationBarInset.of(context),
      ),
      children: children,
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppSubPageHeader(
              title: title,
              subtitle: subtitle,
              trailing: headerAction,
            ),
            Expanded(
              child: onRefresh == null
                  ? list
                  : RefreshIndicator(onRefresh: onRefresh!, child: list),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titled card that groups related settings rows.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> children;

  const SettingsGroup({
    super.key,
    this.title,
    this.footer,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const AppDivider(indent: 62),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                footer!,
                style: TextStyle(fontSize: 12, color: cs.outline, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}

/// One row of a [SettingsGroup].
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool chevron;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.chevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AppIconBox(
              icon: icon,
              size: 36,
              background: destructive ? cs.errorContainer : null,
              foreground: destructive ? cs.onErrorContainer : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: destructive
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: color,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
            if (onTap != null && chevron && trailing == null)
              Icon(AppIcons.chevronRight, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

/// Switch row for a [SettingsGroup].
class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      chevron: false,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// Small coloured status label (for example "Enabled" or "Online").
class SettingsPill extends StatelessWidget {
  final String text;
  final Color? color;

  const SettingsPill(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

/// Filled form field that matches the app's input style.
InputDecoration settingsInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  Widget? suffix,
}) {
  final cs = Theme.of(context).colorScheme;
  OutlineInputBorder border([Color? color, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(
          color: color ?? appBorderColor(cs),
          width: width,
        ),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffix,
    filled: true,
    fillColor: cs.surfaceContainerHighest,
    isDense: true,
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(cs.primary, 1.5),
  );
}

/// Full-width primary button used by settings forms.
class SettingsButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;
  final bool outlined;

  const SettingsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.destructive = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    final child = busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    final action = busy ? null : onPressed;
    if (outlined) {
      return OutlinedButton(
        onPressed: action,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: shape,
          foregroundColor: destructive ? cs.error : null,
          side: BorderSide(
            color: destructive
                ? cs.error.withValues(alpha: 0.5)
                : appBorderColor(cs),
          ),
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: action,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: shape,
        backgroundColor: destructive ? cs.error : null,
        foregroundColor: destructive ? cs.onError : null,
      ),
      child: child,
    );
  }
}

/// Shows a short message above the floating navigation bar.
void settingsToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
