import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/check_in_service.dart';
import 'check_in_scanner_page.dart';
import 'club_stats_page.dart';

/// Club Day: the live sign-in session for one date.
///
/// An admin opens the day, scans members at the door, and the sheet below
/// fills in as each person is scanned — it is a Firestore stream, so rows
/// appear without a refresh and on every admin's phone at once.
class ClubDayPage extends StatefulWidget {
  const ClubDayPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.isAdmin,
  });

  final String groupId;
  final String groupName;
  final bool isAdmin;

  @override
  State<ClubDayPage> createState() => _ClubDayPageState();
}

class _ClubDayPageState extends State<ClubDayPage> {
  final CheckInService _service = CheckInService();

  late final String _todayKey = CheckInService.dateKeyFor(DateTime.now());
  bool _working = false;

  Future<void> _openDay() async {
    setState(() => _working = true);
    try {
      await _service.openClubDay(widget.groupId, groupName: widget.groupName);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open club day.')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _closeDay() async {
    setState(() => _working = true);
    try {
      await _service.closeClubDay(widget.groupId, _todayKey);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _scan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckInScannerPage(
          title: 'Club Day — ${widget.groupName}',
          onScan: (token) => _service.checkInToClubDay(
            groupId: widget.groupId,
            dateKey: _todayKey,
            token: token,
          ),
        ),
      ),
    );
  }

  Future<void> _addByHand() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in by hand'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Member email',
            hintText: 'name@example.com',
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
    if (email == null || email.trim().isEmpty) return;

    final result = await _service.checkInToClubDay(
      groupId: widget.groupId,
      dateKey: _todayKey,
      memberEmail: email.trim().toLowerCase(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Day'),
        actions: [
          IconButton(
            tooltip: 'Statistics',
            icon: const Icon(Icons.insert_chart_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ClubStatsPage(
                  groupId: widget.groupId,
                  groupName: widget.groupName,
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _service.watchClubDay(widget.groupId, _todayKey),
        builder: (context, daySnap) {
          final day = daySnap.data?.data();
          final exists = daySnap.data?.exists ?? false;
          final isOpen = day?['isOpen'] == true;

          return Column(
            children: [
              _header(exists: exists, isOpen: isOpen),
              const Divider(height: 1),
              Expanded(child: _sheet(isOpen: isOpen)),
            ],
          );
        },
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _working ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan'),
            )
          : null,
    );
  }

  Widget _header({required bool exists, required bool isOpen}) {
    final cs = Theme.of(context).colorScheme;
    final pretty = _prettyDate(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(pretty,
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              _statusChip(exists: exists, isOpen: isOpen),
            ],
          ),
          if (widget.isAdmin) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (!isOpen)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _working ? null : _openDay,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(exists ? 'Reopen club day' : 'Start club day'),
                    ),
                  )
                else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : _addByHand,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('By hand'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : _closeDay,
                      icon: const Icon(Icons.stop),
                      label: const Text('Close day'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip({required bool exists, required bool isOpen}) {
    final (String label, Color color) = !exists
        ? ('Not started', Colors.grey)
        : isOpen
            ? ('Open', Colors.green)
            : ('Closed', Colors.orange);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// The live sign-in sheet. Rows arrive via the Firestore stream, so a scan
  /// on one phone shows up on every admin's screen immediately.
  Widget _sheet({required bool isOpen}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchClubDayCheckIns(widget.groupId, _todayKey),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Could not load sign-ins.'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 14),
                  Text(
                    isOpen
                        ? 'Nobody signed in yet.\nTap Scan and point at a member’s code.'
                        : 'Start the club day, then scan members in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Text(
                      '${docs.length} signed in',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const Spacer(),
                    Text('TIME',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                  ],
                ),
              );
            }

            final doc = docs[i - 1];
            final d = doc.data();
            final at = (d['checkedInAt'] as Timestamp?)?.toDate();
            final photoUrl = d['photoUrl'] as String?;
            final manual = d['method'] == 'manual';

            return ListTile(
              leading: (photoUrl != null && photoUrl.isNotEmpty)
                  ? CircleAvatar(
                      backgroundImage: CachedNetworkImageProvider(photoUrl))
                  : const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(
                (d['displayName'] as String?) ?? 'Member',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                manual
                    ? '${d['email'] ?? ''} • by hand'
                    : (d['email'] as String?) ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                at == null ? '—' : _clock(at),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onLongPress: widget.isAdmin
                  ? () => _confirmUndo(doc.id,
                      (d['displayName'] as String?) ?? 'this member')
                  : null,
            );
          },
        );
      },
    );
  }

  Future<void> _confirmUndo(String uid, String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove sign-in?'),
        content: Text('$name will be marked absent for today.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await _service.undoClubDayCheckIn(widget.groupId, _todayKey, uid);
    }
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _prettyDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
