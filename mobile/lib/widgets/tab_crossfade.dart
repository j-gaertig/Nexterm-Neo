import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Crossfades between a fixed list of tab pages while keeping every page alive.
///
/// Unlike a fade-to-transparent transition, the outgoing page stays fully
/// visible underneath the incoming page. The incoming page fades in on top,
/// so there is never a blank frame in the middle of a tab change.
///
/// When [swipeEnabled] is true the pages also follow a horizontal drag: the
/// current page moves with the finger and the neighbouring page slides in
/// beside it. Releasing past the threshold (or with a fling) reports the new
/// index through [onSwipeIndexChanged]; otherwise the pages settle back.
class TabCrossfade extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  /// Enables interactive horizontal swiping between the pages.
  final bool swipeEnabled;

  /// Called when a swipe commits to a different page.
  final ValueChanged<int>? onSwipeIndexChanged;

  const TabCrossfade({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 240),
    this.swipeEnabled = false,
    this.onSwipeIndexChanged,
  });

  @override
  State<TabCrossfade> createState() => _TabCrossfadeState();
}

class _TabCrossfadeState extends State<TabCrossfade>
    with TickerProviderStateMixin {
  static const double _swipeCommitFraction = 0.35;
  static const double _swipeCommitVelocity = 300;

  late final AnimationController _controller;
  late final AnimationController _drag;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Listenable _animations;

  int _currentIndex = 0;
  int? _previousIndex;
  int _direction = 1;
  bool _reduceMotion = false;

  bool _dragging = false;
  int? _dragTarget;
  int _dragDirection = 1;
  double _dragDistance = 0;
  bool _commitFromSwipe = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = _clampIndex(widget.index);
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1.0,
    )..addStatusListener(_handleAnimationStatus);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0.018, 0),
      end: Offset.zero,
    ).animate(_fade);
    _drag = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _animations = Listenable.merge([_controller, _drag]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && _previousIndex != null) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(TabCrossfade oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }

    final target = _clampIndex(widget.index);

    // A completed swipe already shows the target page full-screen. Snap to it
    // instead of starting the crossfade animation again.
    if (_commitFromSwipe &&
        _dragTarget != null &&
        target == _clampIndex(_dragTarget!)) {
      _commitFromSwipe = false;
      _drag.stop();
      _drag.value = 0.0;
      _dragTarget = null;
      _dragDirection = 1;
      _dragging = false;
      _previousIndex = null;
      _currentIndex = target;
      _controller.value = 1.0;
      return;
    }

    // Any other selection change cancels an in-flight drag.
    if (_dragTarget != null || _drag.value > 0) {
      _drag.stop();
      _drag.value = 0.0;
      _dragTarget = null;
      _dragDirection = 1;
      _dragging = false;
    }

    if (target == _currentIndex) {
      if (_previousIndex != null &&
          (_previousIndex! >= widget.children.length ||
              _previousIndex == _currentIndex)) {
        _previousIndex = null;
      }
      return;
    }

    if (target == _previousIndex) {
      // The user went back to the page that is still underneath the current
      // one. Bringing it back instantly avoids mounting the same page twice.
      _currentIndex = target;
      _previousIndex = null;
      _controller.value = 1.0;
      return;
    }

    _direction = target > _currentIndex ? 1 : -1;
    _previousIndex = _currentIndex;
    _currentIndex = target;

    if (_reduceMotion) {
      _previousIndex = null;
      _controller.value = 1.0;
    } else {
      _controller.forward(from: 0.0);
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _previousIndex != null) {
      setState(() => _previousIndex = null);
    }
  }

  int _clampIndex(int index) {
    if (widget.children.isEmpty) return 0;
    return index.clamp(0, widget.children.length - 1);
  }

  int get _pageIndex => _clampIndex(widget.index);

  /// Prefer the page's own [ValueKey] so state follows a page when a
  /// destination is inserted or removed before it. Fall back to the index for
  /// pages without a key.
  Key _layerKey(int index) {
    final key = widget.children[index].key;
    return key is ValueKey ? key : ValueKey('tab-page-$index');
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.swipeEnabled || widget.children.length < 2) return;

    _drag.stop();
    _drag.value = 0.0;
    _dragDistance = 0;
    _dragTarget = null;
    _dragging = true;
    if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
      _previousIndex = null;
    }
    setState(() {});
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;

    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;

    _dragDistance += details.delta.dx;
    final direction = _dragDistance < 0 ? 1 : -1;
    final target = _pageIndex + direction;
    final inRange = target >= 0 && target < widget.children.length;

    if (!inRange) {
      // Edge destinations only move inwards.
      if (_dragTarget != null || _drag.value != 0) {
        _drag.value = 0.0;
        setState(() => _dragTarget = null);
      }
      return;
    }

    final progress = (_dragDistance.abs() / width).clamp(0.0, 1.0);
    if (target != _dragTarget || direction != _dragDirection) {
      setState(() {
        _dragTarget = target;
        _dragDirection = direction;
        _drag.value = progress;
      });
    } else {
      _drag.value = progress;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;

    final target = _dragTarget;
    if (target == null) {
      _settleDrag(0.0);
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    final flungForward =
        velocity.abs() > _swipeCommitVelocity &&
        (velocity < 0) == (_dragDirection > 0);
    final commit = _drag.value >= _swipeCommitFraction || flungForward;

    if (!commit) {
      _settleDrag(0.0);
      return;
    }

    HapticFeedback.selectionClick();
    _commitFromSwipe = true;

    if (_reduceMotion) {
      _drag.value = 1.0;
      _completeSwipe(target);
      return;
    }

    final remaining = (1.0 - _drag.value).clamp(0.0, 1.0);
    _drag
        .animateTo(
          1.0,
          duration: Duration(milliseconds: 80 + (160 * remaining).round()),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          if (_drag.value >= 1.0) _completeSwipe(target);
        });
  }

  void _handleDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _settleDrag(0.0);
  }

  void _settleDrag(double to) {
    if (_reduceMotion) {
      _drag.stop();
      _drag.value = to;
      setState(() {
        if (to == 0) {
          _dragTarget = null;
          _dragDistance = 0;
        }
      });
      return;
    }

    _drag
        .animateTo(
          to,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          if (!mounted || _drag.value != 0) return;
          setState(() {
            _dragTarget = null;
            _dragDistance = 0;
          });
        });
  }

  void _completeSwipe(int target) {
    final callback = widget.onSwipeIndexChanged;
    if (callback == null) {
      _commitFromSwipe = false;
      _settleDrag(0.0);
      return;
    }

    callback(target);

    // If the parent ignores the callback, settle back instead of staying
    // between two pages. A successful parent rebuild clears the flag in
    // [didUpdateWidget] before this post-frame callback runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commitFromSwipe) return;
      _commitFromSwipe = false;
      _settleDrag(0.0);
    });
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Count the movement from the pointer-down position (including the drag
      // slop) so the pages follow the finger one-to-one from the first pixel.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: widget.swipeEnabled ? _handleDragStart : null,
      onHorizontalDragUpdate: widget.swipeEnabled ? _handleDragUpdate : null,
      onHorizontalDragEnd: widget.swipeEnabled ? _handleDragEnd : null,
      onHorizontalDragCancel: widget.swipeEnabled ? _handleDragCancel : null,
      child: AnimatedBuilder(
        animation: _animations,
        builder: (context, _) {
          final target = _dragTarget;
          if (target != null) return _buildDragLayout(target);
          return _buildCrossfadeLayout();
        },
      ),
    );
  }

  Widget _buildDragLayout(int dragTargetIndex) {
    final current = _clampIndex(_currentIndex);
    final target = _clampIndex(dragTargetIndex);
    final progress = _drag.value.clamp(0.0, 1.0);
    final width = MediaQuery.sizeOf(context).width;
    final currentOffset = _dragDirection > 0
        ? -progress * width
        : progress * width;
    final targetOffset = _dragDirection > 0
        ? (1.0 - progress) * width
        : -(1.0 - progress) * width;

    return Stack(
      fit: StackFit.expand,
      children: [
        _TabPageLayer(
          key: _layerKey(current),
          index: current,
          current: true,
          visible: true,
          fade: const AlwaysStoppedAnimation<double>(1.0),
          slide: const AlwaysStoppedAnimation<Offset>(Offset.zero),
          offsetX: currentOffset,
          child: widget.children[current],
        ),
        if (target != current)
          _TabPageLayer(
            key: _layerKey(target),
            index: target,
            current: false,
            visible: true,
            fade: const AlwaysStoppedAnimation<double>(1.0),
            slide: const AlwaysStoppedAnimation<Offset>(Offset.zero),
            offsetX: targetOffset,
            child: widget.children[target],
          ),
        for (var i = 0; i < widget.children.length; i++)
          if (i != current && i != target)
            _TabPageLayer(
              key: _layerKey(i),
              index: i,
              current: false,
              visible: false,
              fade: _fade,
              slide: _slide,
              child: widget.children[i],
            ),
      ],
    );
  }

  Widget _buildCrossfadeLayout() {
    final current = _clampIndex(_currentIndex);
    final previous = _previousIndex;
    final safePrevious =
        previous != null &&
            previous >= 0 &&
            previous < widget.children.length &&
            previous != current
        ? previous
        : null;

    final slide = _direction >= 0
        ? _slide
        : Tween<Offset>(
            begin: const Offset(-0.018, 0),
            end: Offset.zero,
          ).animate(_fade);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (safePrevious != null)
          _TabPageLayer(
            key: _layerKey(safePrevious),
            index: safePrevious,
            current: false,
            visible: true,
            fade: _fade,
            slide: slide,
            child: widget.children[safePrevious],
          ),
        _TabPageLayer(
          key: _layerKey(current),
          index: current,
          current: true,
          visible: true,
          fade: _fade,
          slide: slide,
          child: widget.children[current],
        ),
        for (var i = 0; i < widget.children.length; i++)
          if (i != current && i != safePrevious)
            _TabPageLayer(
              key: _layerKey(i),
              index: i,
              current: false,
              visible: false,
              fade: _fade,
              slide: slide,
              child: widget.children[i],
            ),
      ],
    );
  }
}

class _TabPageLayer extends StatelessWidget {
  final int index;
  final bool current;
  final bool visible;
  final Animation<double> fade;
  final Animation<Offset> slide;
  final double offsetX;
  final Widget child;

  const _TabPageLayer({
    super.key,
    required this.index,
    required this.current,
    required this.visible,
    required this.fade,
    required this.slide,
    this.offsetX = 0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Offstage(
        offstage: !visible,
        child: IgnorePointer(
          ignoring: !current,
          child: ExcludeSemantics(
            excluding: !current,
            child: TickerMode(
              enabled: current,
              child: Transform.translate(
                offset: Offset(offsetX, 0),
                child: FadeTransition(
                  opacity: current
                      ? fade
                      : const AlwaysStoppedAnimation<double>(1.0),
                  child: SlideTransition(
                    position: current
                        ? slide
                        : const AlwaysStoppedAnimation<Offset>(Offset.zero),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
