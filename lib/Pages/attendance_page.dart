import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/check_in_service.dart';
import 'check_in_scanner_page.dart';

/// Attendance for one event: who is present, plus the admin controls for
/// opening check-in and scanning.
class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.eventTitle,
    required this.isAdmin,
  });

  final String groupId;
  final String eventId;
  final String eventTitle;
  final bool isAdmin;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final ChatService _chatService = ChatService();
  final CheckInService _checkInService = CheckInService();

  DocumentReference<Map<String, dynamic>> get _eventRef =>
      FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('events')
          .doc(widget.eventId);

  Future<void> _toggleCheckIn(bool enable) async {
    final now = DateTime.now();
    try {
      await _chatService.setEventCheckIn(
        widget.groupId,
        widget.eventId,
        enabled: enable,
        // Opening check-in sets a generous default window; the function adds
        // a further 15 minute grace period after it closes.
        opensAt: enable ? now.subtract(const Duration(minutes: 30)) : null,
        closesAt: enable ? now.add(const Duration(hours: 4)) : null,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update check-in.')),
      );
    }
  }

  Future<void> _openScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckInScannerPage(
          groupId: widget.groupId,
          eventId: widget.eventId,
          eventTitle: widget.eventTitle,
        ),
      ),
    );
  }

  /// Manual check-in for members whose phone is dead or missing.
  ///
  /// This still routes through the Cloud Function using that member's own
  /// token, so the same membership and window checks apply.
  Future<void> _manualAdd() async {
    final pending = await _chatService.getUncheckedMembers(
      widget.groupId,
      widget.eventId,
    );
    if (!mounted) return;

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Everyone is already checked in.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Not yet checked in',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pending.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(pending[i]),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () {
                    Navigator.pop(context);
                    _checkInByEmail(pending[i]);
                  },
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tap a member to check them in by hand.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkInByEmail(String email) async {
    final result = await _checkInService.checkIn(
      groupId: widget.groupId,
      eventId: widget.eventId,
      memberEmail: email,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Attendance — ${widget.eventTitle}')),
      body: Column(
        children: [
          if (widget.isAdmin) _adminControls(),
          Expanded(child: _roster()),
        ],
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan'),
            )
          : null,
    );
  }

  Widget _adminControls() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _eventRef.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final enabled = data?['checkInEnabled'] == true;
        return Column(
          children: [
            SwitchListTile(
              value: enabled,
              onChanged: _toggleCheckIn,
              title: const Text('Check-in open'),
              subtitle: Text(
                enabled
                    ? 'Members can be scanned now'
                    : 'Scans will be rejected while this is off',
              ),
              secondary: const Icon(Icons.how_to_reg),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Add a member manually'),
              subtitle: const Text('For dead phones and forgotten codes'),
              onTap: _manualAdd,
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  Widget _roster() {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.watchEventCheckIns(widget.groupId, widget.eventId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load attendance.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nobody has checked in yet.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${docs.length} present',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              );
            }

            final data = docs[i - 1].data() as Map<String, dynamic>;
            final photoUrl = data['photoUrl'] as String?;
            final at = (data['checkedInAt'] as Timestamp?)?.toDate();
            final manual = data['method'] == 'manual';

            return ListTile(
              leading: (photoUrl != null && photoUrl.isNotEmpty)
                  ? CircleAvatar(
                      backgroundImage: CachedNetworkImageProvider(photoUrl),
                    )
                  : const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text((data['displayName'] as String?) ?? 'Member'),
              subtitle: Text((data['email'] as String?) ?? ''),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (at != null)
                    Text(
                      '${at.hour.toString().padLeft(2, '0')}:'
                      '${at.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (manual)
                    const Text('manual', style: TextStyle(fontSize: 10)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
