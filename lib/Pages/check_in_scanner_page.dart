import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/check_in_service.dart';

/// Camera scanner for member QR codes.
///
/// Deliberately knows nothing about club days or events: the caller supplies
/// [onScan], which does the actual recording and hands back a result to show.
/// It also keeps a manual entry path, because cameras fail, phones die, and
/// people still need signing in.
class CheckInScannerPage extends StatefulWidget {
  const CheckInScannerPage({
    super.key,
    required this.title,
    required this.onScan,
  });

  final String title;

  /// Called with a scanned (or typed) token. Returns what to show the
  /// operator. Never throws — a failure is a [CheckInResult] with `ok: false`.
  final Future<CheckInResult> Function(String token) onScan;

  @override
  State<CheckInScannerPage> createState() => _CheckInScannerPageState();
}

class _CheckInScannerPageState extends State<CheckInScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    // noDuplicates stops one code firing repeatedly while it sits in frame;
    // _busy still guards, since a member may legitimately be rescanned
    // after an error.
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  CheckInResult? _last;
  Timer? _clearBanner;
  bool _busy = false;
  int _successCount = 0;

  @override
  void dispose() {
    _clearBanner?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String token) async {
    if (_busy || token.isEmpty) return;
    setState(() => _busy = true);

    final result = await widget.onScan(token);

    if (!mounted) return;
    setState(() {
      _last = result;
      _busy = false;
      if (result.ok && !result.alreadyCheckedIn) _successCount++;
    });

    // Hold the result long enough to read the name and match it to the person
    // standing there, then clear so the next scan is unambiguous.
    _clearBanner?.cancel();
    _clearBanner = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _last = null);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    _submit(raw.trim());
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter code manually'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Check-in code',
            hintText: "Paste the member's code",
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (token != null) _submit(token.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Enter code manually',
            icon: const Icon(Icons.keyboard),
            onPressed: _manualEntry,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) =>
                      _cameraUnavailable(error),
                ),
                _reticle(),
                if (_busy)
                  const ColoredBox(
                    color: Colors.black38,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_last != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _resultBanner(_last!),
                  ),
              ],
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  /// A frame to aim with. Without one the whole screen is live and people do
  /// not know where to hold the phone.
  Widget _reticle() {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 230,
          height: 230,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 2),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  /// Shown when the camera cannot start — denied permission, or no camera.
  /// Manual entry keeps the screen usable either way.
  Widget _cameraUnavailable(MobileScannerException error) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                'Camera unavailable',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                error.errorDetails?.message ??
                    'Grant camera permission, or enter codes manually.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter code manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultBanner(CheckInResult r) {
    final Color bg;
    final IconData icon;
    if (!r.ok) {
      bg = Colors.red.shade700;
      icon = Icons.error_outline;
    } else if (r.alreadyCheckedIn) {
      bg = Colors.orange.shade800;
      icon = Icons.info_outline;
    } else {
      bg = Colors.green.shade700;
      icon = Icons.check_circle_outline;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // The photo is the point: compare it to the person in front of
            // you, which is what stops a shared screenshot.
            if (r.ok && r.photoUrl != null && r.photoUrl!.isNotEmpty)
              CircleAvatar(
                radius: 26,
                backgroundImage: CachedNetworkImageProvider(r.photoUrl!),
              )
            else
              Icon(icon, color: Colors.white, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  if (r.ok && r.email != null)
                    Text(
                      r.email!,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.how_to_reg, size: 20),
            const SizedBox(width: 8),
            Text(
              '$_successCount signed in',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              "Point at a member's QR code",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
