import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Semantic page landmarks for screen-reader navigation (Flutter web → ARIA).
class A11yLandmark extends StatelessWidget {
  const A11yLandmark({
    super.key,
    required this.role,
    required this.label,
    required this.child,
  });

  final SemanticsRole role;
  final String label;
  final Widget child;

  factory A11yLandmark.main({
    Key? key,
    required String label,
    required Widget child,
  }) =>
      A11yLandmark(
        key: key,
        role: SemanticsRole.main,
        label: label,
        child: child,
      );

  factory A11yLandmark.navigation({
    Key? key,
    required String label,
    required Widget child,
  }) =>
      A11yLandmark(
        key: key,
        role: SemanticsRole.navigation,
        label: label,
        child: child,
      );

  factory A11yLandmark.complementary({
    Key? key,
    required String label,
    required Widget child,
  }) =>
      A11yLandmark(
        key: key,
        role: SemanticsRole.complementary,
        label: label,
        child: child,
      );

  factory A11yLandmark.region({
    Key? key,
    required String label,
    required Widget child,
  }) =>
      A11yLandmark(
        key: key,
        role: SemanticsRole.region,
        label: label,
        child: child,
      );

  factory A11yLandmark.contentInfo({
    Key? key,
    required String label,
    required Widget child,
  }) =>
      A11yLandmark(
        key: key,
        role: SemanticsRole.contentInfo,
        label: label,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      role: role,
      child: child,
    );
  }
}

/// Visible text that also exposes a document heading (h1–h6) in the a11y tree.
class A11yHeading extends StatelessWidget {
  const A11yHeading({
    super.key,
    required this.text,
    required this.style,
    this.level = 1,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final int level;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      headingLevel: level.clamp(1, 6),
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}

/// Ensures interactive custom widgets expose button roles + names.
class A11yButton extends StatelessWidget {
  const A11yButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
    this.enabled = true,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool? selected;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onTap != null;
    Widget body = Semantics(
      button: true,
      enabled: interactive,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: interactive ? onTap : null,
          child: child,
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      body = Tooltip(message: tooltip!, child: body);
    }
    return body;
  }
}
