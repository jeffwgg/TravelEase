import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps flex layouts usable when the keyboard or a short screen reduces space.
class ScrollableScreenBody extends StatelessWidget {
  const ScrollableScreenBody({
    super.key,
    required this.minimumHeight,
    required this.child,
  });

  final double minimumHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: SizedBox(
            height: math.max(
              constraints.maxHeight,
              minimumHeight * math.max(1, textScale),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
