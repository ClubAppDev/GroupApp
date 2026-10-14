import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/check_in_service.dart';
import '../theme/app_theme.dart';

/// The member's side of check-in: a QR code a club admin scans at the door.
///
/// The code holds an opaque token, never the member's email, so anyone who
/// scans it with a generic QR app learns nothing about them.
class MyCheckInCodePage extends StatefulWidget {
  const MyCheckInCodePage({super.key});

  @override
  State<MyCheckInCodePage> createState() => _MyCheckInCodePageState();
}

class _MyCheckInCodePageState extends State<MyCheckInCodePage> {
  final CheckInService _checkInService = CheckInService();

  String? _token;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken({bool rotate = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _checkInService.getMyCheckInToken(rotate: rotate);
      if (!mounted) return;
      setState(() {
        _token = token;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your code. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _confirmRotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset your code?'),
        content: const Text(
          'Your old QR code stops working immediately. Use this if someone '
          'else has a copy of it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _loadToken(rotate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Check-In Code'),
        actions: [
          IconButton(
            tooltip: 'Reset code',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _confirmRotate,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(isDark),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const CircularProgressIndicator();
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _loadToken(),
            child: const Text('Try again'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The QR is always rendered on white regardless of theme — scanners
        // need the contrast, and a dark-mode QR fails to read.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: _token!,
            version: QrVersions.auto,
            size: 240,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Show this to a club admin',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Turn your screen brightness up if it will not scan.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          ),
        ),
      ],
    );
  }
}
