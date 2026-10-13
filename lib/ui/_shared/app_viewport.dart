import 'package:flutter/material.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';

/// A bounded reading surface on desktop, edge to edge on phones.
class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surfaceDark,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: SizedBox.expand(child: child),
      ),
    ),
  );
}
