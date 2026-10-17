import 'package:flutter/material.dart';
import 'package:hyperlocal/ui/_shared/app_viewport.dart';

/// Horizontal chip/row scroller that stays inside page gutters.
///
/// Padding is applied *outside* the scroll viewport so chips never paint
/// flush against the screen edge (they clip at the margin instead).
class HorizontalInsetScroller extends StatelessWidget {
  const HorizontalInsetScroller({
    super.key,
    required this.children,
    this.gutter = kPageGutter,
    this.gap = 8,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
  });

  final List<Widget> children;
  final double gutter;
  final double gap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Padding(
        padding: padding,
        child: ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
