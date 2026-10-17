import 'package:flutter/material.dart';
import 'zivo_logo.dart';

/// One opening reveal per app mount. The router stays mounted underneath,
/// so restoring a session or following a deep link is never delayed.
class ZivoLaunch extends StatefulWidget {
  const ZivoLaunch({super.key, required this.child});
  final Widget child;

  @override
  State<ZivoLaunch> createState() => _ZivoLaunchState();
}

class _ZivoLaunchState extends State<ZivoLaunch>
    with SingleTickerProviderStateMixin {
  /// Survives widget remounts (e.g. old locale-driven MaterialApp rebuilds)
  /// so a white splash overlay never traps the UI again mid-session.
  static bool _sessionReady = false;

  late final AnimationController _controller;
  bool _started = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _finished = _sessionReady;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
      value: _sessionReady ? 1 : 0,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _sessionReady = true;
          setState(() => _finished = true);
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_finished || _sessionReady) {
      _finished = true;
      _sessionReady = true;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _finished = true;
      _sessionReady = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep this tree stable across completion to preserve router state.
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: !_finished,
          child: ExcludeSemantics(
            excluding: !_finished,
            child: IgnorePointer(ignoring: !_finished, child: widget.child),
          ),
        ),
        if (!_finished)
          Positioned.fill(
            child: Semantics(
              label: 'Zivo',
              image: true,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final enter = const Interval(0, 0.42,
                      curve: Curves.easeOutCubic).transform(_controller.value);
                  final exit = const Interval(0.70, 1,
                      curve: Curves.easeInOutCubic).transform(_controller.value);
                  return Opacity(
                    opacity: 1 - exit,
                    child: ColoredBox(
                      key: const ValueKey('zivo-launch-overlay'),
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: ExcludeSemantics(
                          child: Opacity(
                            opacity: enter,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - enter)),
                              child: Transform.scale(
                                scale: 0.96 + 0.04 * enter,
                                child: ZivoLogo(
                                  size: 80,
                                  showWordmark: true,
                                  wordmarkColor:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
