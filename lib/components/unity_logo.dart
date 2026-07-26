import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:login_ui/theme/app_theme.dart';

/// The "Unity" brand mark: three brass shards that interlock into a single
/// rounded triangle — symbolizing separate people/clubs coming together.
///
/// [assembly] 0..1 controls how assembled the mark is:
///   0 = shards scattered/exploded outward and faded,
///   1 = fully assembled, tight logo.
/// Use values > 1 conceptually by driving the reveal (see UnityRevealOverlay).
class UnityLogo extends StatelessWidget {
  final double size;

  /// 1 = assembled. As it goes 1 -> 0 (or beyond via [explode]) the shards
  /// separate. [explode] pushes shards further out for the reveal.
  final double assembly;

  /// Extra outward push (0 = none). Used by the split reveal to fling shards
  /// off-screen while fading.
  final double explode;

  const UnityLogo({
    super.key,
    this.size = 120,
    this.assembly = 1,
    this.explode = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _UnityPainter(assembly: assembly, explode: explode),
      ),
    );
  }
}

class _UnityPainter extends CustomPainter {
  final double assembly; // 0..1
  final double explode; // 0..N

  _UnityPainter({required this.assembly, required this.explode});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.36;

    // Three shards arranged around the center, pointing outward at 120° apart.
    // Each shard is a rounded triangle wedge; when assembled they meet at center.
    const shardColors = [
      AppColors.brass,
      AppColors.brassLight,
      AppColors.brassDeep,
    ];

    for (int i = 0; i < 3; i++) {
      final angle = -math.pi / 2 + i * (2 * math.pi / 3); // start at top
      // Separation distance: 0 when assembled, grows as assembly drops or on explode.
      final sep = (1 - assembly) * r * 1.4 + explode * size.width;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final shardCenter = center + dir * (r * 0.42 + sep);

      // Fade shards out as they explode away.
      final fade = (1.0 - explode).clamp(0.0, 1.0);
      final opacity = (0.35 + 0.65 * assembly) * fade;

      final paint = Paint()
        ..color = shardColors[i].withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      // Build a wedge shard as a path, rotated to point outward.
      final path = _shardPath(shardCenter, r, angle);
      canvas.drawPath(path, paint);
    }

    // Central "core" dot that binds them, brightest when assembled.
    final core = Paint()
      ..color = Colors.white.withValues(
        alpha: (assembly * (1 - explode)).clamp(0.0, 1.0),
      );
    if (assembly > 0.6 && explode < 0.5) {
      canvas.drawCircle(center, r * 0.14 * assembly, core);
    }
  }

  /// A rounded triangular shard centered at [c], pointing along [angle].
  Path _shardPath(Offset c, double r, double angle) {
    final size = r * 0.95;
    // Local shard: an isosceles triangle pointing "up" (toward center),
    // then rotate by angle+90° so its tip faces the middle.
    final tip = Offset(0, -size * 0.55);
    final baseL = Offset(-size * 0.5, size * 0.45);
    final baseR = Offset(size * 0.5, size * 0.45);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..close();

    final matrix = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..rotateZ(angle + math.pi / 2);
    return path.transform(matrix.storage);
  }

  @override
  bool shouldRepaint(covariant _UnityPainter oldDelegate) =>
      oldDelegate.assembly != assembly || oldDelegate.explode != explode;
}

/// Plays once after login: an OVERLAY that spins the Unity logo on a solid
/// backdrop (hiding the app while it loads), then splits the shards apart.
///
/// This renders ONLY the logo + backdrop — stack it ON TOP of the real app so
/// the app never structurally moves in the tree (which would rebuild it and
/// cause a flicker). The split does NOT start until [ready] is true, with a
/// [maxWait] cap. Calls [onDone] when finished so the parent can remove it.
class UnityRevealOverlay extends StatefulWidget {
  /// Flips to true when the app content behind the overlay is loaded. The split
  /// waits for this (up to [maxWait]) so real content is shown, not a skeleton.
  final ValueListenable<bool>? ready;

  /// Hard cap on how long to hold before splitting even if [ready] never fires.
  final Duration maxWait;

  /// Called once when the reveal animation finishes.
  final VoidCallback? onDone;

  const UnityRevealOverlay({
    super.key,
    this.ready,
    this.maxWait = const Duration(seconds: 6),
    this.onDone,
  });

  @override
  State<UnityRevealOverlay> createState() => _UnityRevealOverlayState();
}

class _UnityRevealOverlayState extends State<UnityRevealOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _minSpin = Duration(milliseconds: 1800);
  // Extra grace period spun AFTER the app reports ready — keeps the opaque
  // backdrop up a bit longer so the content fully settles before it's revealed
  // (covers any brief post-load flicker).
  static const Duration _readyGrace = Duration(milliseconds: 500);

  // Continuous spin controller (loops). We switch it to the one-shot split when
  // the app behind is ready AND the minimum time has elapsed.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000), // one spin loop = 1s
  );

  final Stopwatch _elapsed = Stopwatch()..start();
  bool _splitting = false; // true once the explode has begun
  bool _done = false;
  double _spinAtSplit = 0; // spin angle frozen when the split starts
  Stopwatch? _readySince; // starts when the app first reports ready

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
    _c.repeat(); // spin forever until we trigger the split
    widget.ready?.addListener(_maybeSplit);
    // Also poll, so "min time reached after ready" is handled.
    _tick();
  }

  void _tick() {
    if (!mounted || _splitting) return;
    _maybeSplit();
    if (!_splitting) {
      Future.delayed(const Duration(milliseconds: 60), _tick);
    }
  }

  void _maybeSplit() {
    if (_splitting || !mounted) return;
    final ready = widget.ready?.value ?? true;

    // Once ready, start (or keep) the grace clock. Only split after the grace
    // period AND the overall minimum spin time have both elapsed.
    if (ready) {
      _readySince ??= Stopwatch()..start();
    } else {
      _readySince = null; // not ready anymore — reset the grace clock
    }

    final graceDone =
        _readySince != null && _readySince!.elapsed >= _readyGrace;
    if (ready && graceDone && _elapsed.elapsed >= _minSpin) {
      _beginSplit();
    }
  }

  void _beginSplit() {
    if (_splitting || !mounted) return;
    _splitting = true;
    _spinAtSplit = _c.value; // freeze rotation here
    _c.stop();
    _c
      ..duration = const Duration(milliseconds: 650)
      ..value = 0
      ..forward(); // now _c.value drives the explode 0->1
    setState(() {});
  }

  void _onStatus(AnimationStatus s) {
    if (_splitting && s == AnimationStatus.completed && mounted) {
      setState(() => _done = true);
      widget.onDone?.call();
    }
  }

  @override
  void dispose() {
    widget.ready?.removeListener(_maybeSplit);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hard cut when done — no fade/crossfade. The navy stays 100% opaque the
    // whole animation (shards explode ON it), then this one instant removes the
    // whole overlay. Because the app behind is already painted, the cut is
    // flicker-free (there is no intermediate blended frame to flash).
    if (_done) return const SizedBox.shrink();

    return IgnorePointer(
      // Solid navy fills the screen the ENTIRE time — never translucent, so the
      // app is never partially visible through it during the animation.
      child: ColoredBox(
        color: AppColors.navy,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final spin = (_splitting ? _spinAtSplit : _c.value) * 2 * math.pi;
              final split = _splitting ? _c.value : 0.0;
              final explode = Curves.easeInCubic.transform(split);
              return Center(
                child: Transform.rotate(
                  angle: spin,
                  child: UnityLogo(
                    size: 160,
                    assembly: 1,
                    explode: explode,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
