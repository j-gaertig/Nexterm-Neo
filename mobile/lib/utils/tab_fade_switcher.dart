import 'package:flutter/animation.dart';

/// Fades a page out before changing the selected tab.
///
/// A regular `reverse().then(...)` never resolves when another callback resets
/// the controller mid-fade. That can leave a newly created session running in
/// the background because the pending tab change is silently dropped. This
/// helper finishes the change on completion *and* cancellation, while
/// [resetFadeIfIdle] keeps unrelated session updates from interrupting an
/// in-flight transition.
class TabFadeSwitcher {
  TabFadeSwitcher({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 200),
  }) : _controller = AnimationController(
         vsync: vsync,
         duration: duration,
         value: 1.0,
       );

  final AnimationController _controller;
  int _token = 0;
  bool _switching = false;

  Animation<double> get opacity => _controller;
  bool get isSwitching => _switching;

  void switchTab({required VoidCallback apply, bool Function()? canApply}) {
    final token = ++_token;
    _switching = true;
    _controller.reverse().whenCompleteOrCancel(() {
      if (token != _token) return;
      _switching = false;
      if (canApply != null && !canApply()) {
        _controller.value = 1.0;
        return;
      }
      apply();
      _controller.forward();
    });
  }

  /// Resets page opacity unless a tab change is already in flight.
  void resetFadeIfIdle() {
    if (!_switching) _controller.value = 1.0;
  }

  void dispose() {
    _token++;
    _controller.dispose();
  }
}
