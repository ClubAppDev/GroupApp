import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/check_in_service.dart';
import 'club_stats_page.dart';

/// Every club's attendance, for the school admin.
///
/// Club admins see only their own club's statistics; this screen is the
/// school-wide view, so it lists all clubs and opens any of their sheets.
class AllClubsStatsPage extends StatelessWidget {
  const AllClubsStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CheckInService();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('All Club Statistics')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchAllGroups(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load clubs.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final groups = snap.data!.docs;
          if (groups.isEmpty) {
            return const Center(child: Text('No clubs yet.'));
          }

          return ListView.separated(
            itemCount: groups.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Text(
                    '${groups.length} ${groups.length == 1 ? 'club' : 'clubs'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                );
              }

              final doc = groups[i - 1];
              final d = doc.data();
              final name = (d['name'] as String?) ?? 'Club';
              final members =
                  List<String>.from(d['members'] ?? const []).length;
              final admins = List<String>.from(d['admins'] ?? const []);

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  child: Icon(Icons.groups, color: cs.primary, size: 20),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '$members ${members == 1 ? 'member' : 'members'}'
                  '${admins.isEmpty ? '' : '  •  ${admins.first}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClubStatsPage(
                      groupId: doc.id,
                      groupName: name,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
