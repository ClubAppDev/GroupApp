import 'package:flutter/material.dart';
import 'package:login_ui/theme/app_theme.dart';

/// A shimmering placeholder block. Wrap layout-shaped skeletons in these while
/// content loads, instead of a spinner.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : AppColors.navy.withValues(alpha: 0.07);
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : AppColors.navy.withValues(alpha: 0.12);

    return Container(
      margin: widget.margin,
      child: RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              // Slide the gradient's alignment from off-left to off-right.
              // Using shifting alignment (not a matrix transform) avoids the
              // hard-edge flashing the ShaderMask approach produced.
              final t = _controller.value; // 0..1
              final begin = Alignment(-1.0 - 2.0 * (1 - t), 0);
              final end = Alignment(1.0 + 2.0 * t, 0);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: [base, highlight, base],
                    stops: const [0.25, 0.5, 0.75],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

/// A vertical list of card-shaped skeleton rows — a drop-in placeholder for a
/// loading list (chats, groups, search results, etc.).
class SkeletonList extends StatelessWidget {
  final int rows;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.rows = 7,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      itemBuilder: (context, i) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SkeletonBox(width: 44, height: 44, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 140, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 220, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-screen skeleton (scaffold + wallpaper + list rows) for whole-page
/// loading states like app startup.
class SkeletonScreen extends StatelessWidget {
  const SkeletonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: NeonBackground(
        child: SafeArea(child: SkeletonList(rows: 8)),
      ),
    );
  }
}

/// A skeleton shaped like a chat conversation — alternating message bubbles.
class SkeletonChat extends StatelessWidget {
  const SkeletonChat({super.key});

  @override
  Widget build(BuildContext context) {
    final widths = [180.0, 120.0, 220.0, 90.0, 200.0, 140.0];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widths.length,
      itemBuilder: (context, i) {
        final isMe = i.isOdd;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: SkeletonBox(
            width: widths[i],
            height: 38,
            radius: 14,
            margin: const EdgeInsets.only(bottom: 12),
          ),
        );
      },
    );
  }
}
