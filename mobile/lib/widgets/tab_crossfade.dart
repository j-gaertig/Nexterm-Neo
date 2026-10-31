import 'package:flutter/material.dart';

/// Crossfades between a fixed list of tab pages while keeping every page alive.
///
/// Unlike a fade-to-transparent transition, the outgoing page stays fully
/// visible underneath the incoming page. The incoming page fades in on top,
/// so there is never a blank frame in the middle of a tab change.
class TabCrossfade extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const TabCrossfade({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 240),
  });

  @override
  State<TabCrossfade> createState() => _TabCrossfadeState();
}

class _TabCrossfadeState extends State<TabCrossfade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  int _currentIndex = 0;
  int? _previousIndex;
  int _direction = 1;
  bool _reduceMotion = false;

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

  /// Prefer the page's own [ValueKey] so state follows a page when a
  /// destination is inserted or removed before it. Fall back to the index for
  /// pages without a key.
  Key _layerKey(int index) {
    final key = widget.children[index].key;
    return key is ValueKey ? key : ValueKey('tab-page-$index');
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();

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
  final Widget child;

  const _TabPageLayer({
    super.key,
    required this.index,
    required this.current,
    required this.visible,
    required this.fade,
    required this.slide,
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
    );
  }
}
