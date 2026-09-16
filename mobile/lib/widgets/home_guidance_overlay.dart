import 'dart:math' as math;

import 'package:flutter/material.dart';

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

/// Dims a screen while highlighting one target. It is intentionally
/// dependency-free so the tour can match the TravelEase theme.
class HomeGuidanceOverlay extends StatefulWidget {
  const HomeGuidanceOverlay({
    super.key,
    required this.targetKey,
    required this.title,
    required this.message,
    required this.onSkip,
    this.actions = const [],
    this.scrollController,
    this.skipLabel = 'Skip tour',
  });

  final GlobalKey targetKey;
  final String title;
  final String message;
  final VoidCallback onSkip;
  final List<HomeGuidanceAction> actions;
  final ScrollController? scrollController;
  final String skipLabel;

  @override
  State<HomeGuidanceOverlay> createState() => _HomeGuidanceOverlayState();
}

class _HomeGuidanceOverlayState extends State<HomeGuidanceOverlay> {
  Rect? _target;
  Rect? _candidateTarget;
  bool _targetReady = false;
  int _measurementAttempts = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_refreshTargetPosition);
    _scheduleTargetMeasurement();
  }

  @override
  void didUpdateWidget(covariant HomeGuidanceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_refreshTargetPosition);
      widget.scrollController?.addListener(_refreshTargetPosition);
    }
    if (oldWidget.targetKey != widget.targetKey) {
      _target = null;
      _candidateTarget = null;
      _targetReady = false;
      _measurementAttempts = 0;
      _scheduleTargetMeasurement();
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_refreshTargetPosition);
    super.dispose();
  }

  void _refreshTargetPosition() {
    _scheduleTargetMeasurement();
  }

  /// Measures only after a frame has been laid out. Two identical frame
  /// measurements avoid displaying a spotlight at an intermediate page-route
  /// position and then moving it once an animation settles.
  void _scheduleTargetMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final measured = _targetRect(context);
      if (measured == null) {
        _candidateTarget = null;
        if (_measurementAttempts++ < 90) _scheduleTargetMeasurement();
        return;
      }

      if (!_targetReady) {
        if (_candidateTarget == measured) {
          setState(() {
            _target = measured;
            _targetReady = true;
          });
          return;
        }
        _candidateTarget = measured;
        if (_measurementAttempts++ < 90) _scheduleTargetMeasurement();
        return;
      }

      if (_target != measured) setState(() => _target = measured);
    });
  }

  Rect? _targetRect(BuildContext overlayContext) {
    final targetBox = widget.targetKey.currentContext?.findRenderObject();
    final overlayBox = overlayContext.findRenderObject();
    if (targetBox is! RenderBox ||
        overlayBox is! RenderBox ||
        !targetBox.attached ||
        !overlayBox.attached ||
        !targetBox.hasSize ||
        !overlayBox.hasSize) {
      return null;
    }
    // A target may itself be laid out while one of its animated ancestors is
    // not (notably RenderFractionalTranslation during a route transition).
    // localToGlobal walks that ancestor chain and would assert in that case.
    if (!_hasLaidOutAncestors(targetBox) || !_hasLaidOutAncestors(overlayBox)) {
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

  bool _hasLaidOutAncestors(RenderObject object) {
    RenderObject? current = object;
    while (current != null) {
      if (current is RenderBox && !current.hasSize) return false;
      current = current.parent;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // During automatic scrolling the next target can take a few frames to
    // settle. Keep the guidance card (and its Next button) visible instead of
    // returning an empty overlay, otherwise the tour looks as though it has
    // stopped after a step such as Quick Actions.
    return LayoutBuilder(
      builder: (overlayContext, constraints) {
        final size = constraints.biggest;
        final target = _targetReady ? _target : null;
        final spotlight = target?.inflate(8).intersect(Offset.zero & size);

        return Semantics(
          container: true,
          label: 'TravelEase guidance',
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(),
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
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in widget.actions)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: action.isPrimary
                            ? ElevatedButton(
                                onPressed: action.onPressed,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(action.label),
                              )
                            : OutlinedButton(
                                onPressed: action.onPressed,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(action.label),
                              ),
                      ),
                    TextButton(
                      onPressed: widget.onSkip,
                      child: Text(widget.skipLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
