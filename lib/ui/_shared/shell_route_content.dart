import 'package:flutter/material.dart';

/// ShellRoute's navigator must stay mounted, including while Home is shown.
/// Never put the routed subtree in an AnimatedSwitcher: outgoing navigators
/// can outlive their inherited route scope during rapid route changes.
///
/// When [home] is provided, it stays mounted (Offstage when not on home) so
/// desktop chrome beside the shell (e.g. activity rail) is not torn down.
class ShellRouteContent extends StatelessWidget {
  const ShellRouteContent({
    super.key,
    required this.isHome,
    required this.routedChild,
    this.home,
  }) : assert(!isHome || home != null);

  final bool isHome;
  final Widget routedChild;
  final Widget? home;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          // Stable position preserves navigator/route element identity.
          Offstage(
            offstage: isHome,
            child: TickerMode(
              enabled: !isHome,
              child: ExcludeFocus(
                excluding: isHome,
                child: routedChild,
              ),
            ),
          ),
          if (home != null)
            Offstage(
              offstage: !isHome,
              child: TickerMode(
                enabled: isHome,
                child: ExcludeFocus(
                  excluding: !isHome,
                  child: home!,
                ),
              ),
            ),
        ],
      );
}
