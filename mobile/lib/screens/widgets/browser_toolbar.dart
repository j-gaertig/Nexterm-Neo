import 'package:flutter/material.dart';

import '../../services/browser_controller.dart';
import '../../utils/app_icons.dart';
import '../../widgets/app_ui.dart';

/// Address bar and navigation buttons for a remote browser session.
class BrowserToolbar extends StatefulWidget {
  final BrowserController controller;

  const BrowserToolbar({super.key, required this.controller});

  @override
  State<BrowserToolbar> createState() => _BrowserToolbarState();
}

class _BrowserToolbarState extends State<BrowserToolbar> {
  final _address = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onState);
    _address.text = widget.controller.state.uri;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onState);
    _address.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    // Do not overwrite what the user is typing.
    if (!_focus.hasFocus) _address.text = widget.controller.state.uri;
    setState(() {});
  }

  void _submit(String value) {
    widget.controller.navigate(value);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = widget.controller.state;
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: state.canBack ? widget.controller.back : null,
                    icon: const Icon(AppIcons.arrowLeft, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Forward',
                    onPressed: state.canForward
                        ? widget.controller.forward
                        : null,
                    icon: const Icon(AppIcons.arrowRight, size: 20),
                  ),
                  IconButton(
                    tooltip: state.loading ? 'Stop' : 'Reload',
                    onPressed: widget.controller.reload,
                    icon: Icon(
                      state.loading ? AppIcons.close : AppIcons.refresh,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _address,
                      focusNode: _focus,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      onSubmitted: _submit,
                      onTap: () => _address.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _address.text.length,
                      ),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search or enter address',
                        isDense: true,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          borderSide: appBorderSide(cs),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          borderSide: appBorderSide(cs),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: state.loading
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
