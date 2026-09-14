import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme.dart';

/// A single action displayed in a [HomeGuidanceOverlay] coach-mark card.
class HomeGuidanceAction {
  const HomeGuidanceAction({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
}

/// Dims a screen while leaving one target visible and, when requested,
/// interactive. It is intentionally dependency-free so the tour can match the
/// TravelEase theme and support real text-field, list, and button actions.
class HomeGuidanceOverlay extends StatefulWidget {
  const HomeGuidanceOverlay({
    super.key,
    required this.targetKey,
    required this.title,
    required this.message,
    required this.onSkip,
    this.actions = const [],
    this.scrollController,
    this.allowTargetInteraction = false,
    this.showSwipeHint = false,
    this.skipLabel = 'Skip tour',
  });

  final GlobalKey targetKey;
  final String title;
  final String message;
  final VoidCallback onSkip;
  final List<HomeGuidanceAction> actions;
  final ScrollController? scrollController;
  final bool allowTargetInteraction;
  final bool showSwipeHint;
  final String skipLabel;

  @override
  State<HomeGuidanceOverlay> createState() => _HomeGuidanceOverlayState();
}

class _HomeGuidanceOverlayState extends State<HomeGuidanceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swipeController;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_refreshTargetPosition);
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSwipeAnimation();
  }

  void _updateSwipeAnimation() {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    if (widget.showSwipeHint && !reducedMotion) {
      _swipeController.repeat(reverse: true);
    } else {
      _swipeController.stop();
      _swipeController.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant HomeGuidanceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_refreshTargetPosition);
      widget.scrollController?.addListener(_refreshTargetPosition);
    }
    if (oldWidget.showSwipeHint != widget.showSwipeHint) {
      _updateSwipeAnimation();
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_refreshTargetPosition);
    _swipeController.dispose();
    super.dispose();
  }

  void _refreshTargetPosition() {
    if (mounted) setState(() {});
  }

  Rect? _targetRect(BuildContext overlayContext) {
    final targetBox = widget.targetKey.currentContext?.findRenderObject();
    final overlayBox = overlayContext.findRenderObject();
    if (targetBox is! RenderBox ||
        overlayBox is! RenderBox ||
        !targetBox.attached ||
        !overlayBox.attached) {
      return null;
    }
    // The target is a child of the screen's Scaffold while this overlay is a
    // sibling above it in a Stack. Convert both points through global space;
    // neither render box is an ancestor of the other.
    final targetGlobal = targetBox.localToGlobal(Offset.zero);
    final overlayGlobal = overlayBox.localToGlobal(Offset.zero);
    final origin = targetGlobal - overlayGlobal;
    return origin & targetBox.size;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (overlayContext, constraints) {
        final size = constraints.biggest;
        final target = _targetRect(overlayContext);
        final spotlight = target?.inflate(8).intersect(Offset.zero & size);

        return Semantics(
          container: true,
          label: 'Home page guidance',
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SpotlightPainter(spotlight: spotlight),
                  ),
                ),
              ),
              Positioned.fill(
                child: _PassThroughSpotlight(
                  passThrough: widget.allowTargetInteraction ? spotlight : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              _buildGuidanceCard(size, target),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGuidanceCard(Size size, Rect? target) {
    const horizontalMargin = 20.0;
    final width = math.min(352.0, size.width - horizontalMargin * 2);
    final left = (size.width - width) / 2;
    final preferAbove = target != null && target.center.dy > size.height * 0.58;
    final top = target == null
        ? math.max(24.0, (size.height - 260) / 2)
        : math.min(size.height - 216, target.bottom + 18);

    return Positioned(
      left: left,
      width: width,
      top: preferAbove ? null : math.max(16, top),
      bottom: preferAbove ? math.max(16, size.height - target.top + 18) : null,
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.message,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                if (widget.showSwipeHint) ...[
                  const SizedBox(height: 12),
                  _SwipeHint(controller: _swipeController),
                ],
                const SizedBox(height: 14),
                ...widget.actions.map(
                  (action) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: action.isPrimary
                          ? ElevatedButton(
                              onPressed: action.onPressed,
                              child: Text(action.label),
                            )
                          : OutlinedButton(
                              onPressed: action.onPressed,
                              child: Text(action.label),
                            ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onSkip,
                    child: Text(widget.skipLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(-14 * controller.value, 0),
              child: child,
            ),
            child: const Icon(
              Icons.swipe_left_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Swipe for more.',
              style: TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.spotlight});

  final Rect? spotlight;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xB3000000));
    if (spotlight != null && !spotlight!.isEmpty) {
      final cutout = RRect.fromRectAndRadius(
        spotlight!,
        const Radius.circular(16),
      );
      canvas.drawRRect(cutout, Paint()..blendMode = BlendMode.clear);
    }
    canvas.restore();

    if (spotlight != null && !spotlight!.isEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(spotlight!, const Radius.circular(16)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.spotlight != spotlight;
}

/// Lets pointer events pass only through the spotlight to the real control
/// below it while the rest of the darkened screen behaves as a modal barrier.
class _PassThroughSpotlight extends SingleChildRenderObjectWidget {
  const _PassThroughSpotlight({
    required this.passThrough,
    required super.child,
  });

  final Rect? passThrough;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PassThroughSpotlightRenderBox(passThrough);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _PassThroughSpotlightRenderBox renderObject,
  ) {
    renderObject.passThrough = passThrough;
  }
}

class _PassThroughSpotlightRenderBox extends RenderProxyBox {
  _PassThroughSpotlightRenderBox(this._passThrough);

  Rect? _passThrough;

  set passThrough(Rect? value) {
    if (_passThrough == value) return;
    _passThrough = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_passThrough?.contains(position) ?? false) return false;
    return super.hitTest(result, position: position);
  }
}
