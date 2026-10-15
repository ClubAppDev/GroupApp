import 'package:flutter/material.dart';

class SquareTile extends StatelessWidget {
  const SquareTile({super.key, required this.imagePath, this.logoHeight = 40});

  final String imagePath;

  /// Optical size, not a raw box size. Marks differ in how much of their
  /// canvas the glyph fills — the Apple mark is tall and narrow, so matched
  /// heights make it read as the smaller of the two. Callers nudge this per
  /// logo so the pair looks balanced.
  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    // Decode at display size. The source art is far larger than it is drawn
    // (the Apple mark is 3400x4400, about 15 megapixels), and decoding that
    // at full size costs tens of megabytes and a visible hitch.
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: SizedBox(
        height: 48,
        width: 48,
        child: Center(
          child: Image.asset(
            imagePath,
            height: logoHeight,
            cacheHeight: (logoHeight * dpr).round(),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            // Asset images are resolved and cached by the framework, so this
            // no longer re-reads the bundle on every build the way the old
            // FutureBuilder did.
            errorBuilder: (context, error, stack) =>
                const Icon(Icons.broken_image, size: 32, color: Colors.black45),
          ),
        ),
      ),
    );
  }
}
