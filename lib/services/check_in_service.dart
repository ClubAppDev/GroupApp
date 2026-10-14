import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Outcome of a single scan, shaped for the scanner UI.
///
/// A rejected scan is not an exception as far as the UI is concerned — the
/// person running the door needs to see *why* it failed and keep scanning, so
/// failures come back as a value with a message rather than something to catch.
class CheckInResult {
  const CheckInResult({
    required this.ok,
    required this.message,
    this.displayName,
    this.email,
    this.photoUrl,
    this.alreadyCheckedIn = false,
  });

  final bool ok;
  final String message;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final bool alreadyCheckedIn;
}

/// One row of a club day's attendance sheet: every member of the club,
/// present or not, so the sheet answers "who showed up" and "who didn't".
class AttendanceRow {
  const AttendanceRow({
    required this.email,
    required this.displayName,
    required this.present,
    this.checkedInAt,
    this.photoUrl,
    this.method,
  });

  final String email;
  final String displayName;
  final bool present;
  final DateTime? checkedInAt;
  final String? photoUrl;
  final String? method;
}

/// A club day plus its computed attendance, for the statistics screens.
class ClubDayReport {
  const ClubDayReport({
    required this.dateKey,
    required this.date,
    required this.isOpen,
    required this.rows,
  });

  final String dateKey;
  final DateTime date;
  final bool isOpen;
  final List<AttendanceRow> rows;

  int get totalMembers => rows.length;
  int get presentCount => rows.where((r) => r.present).length;
  int get absentCount => totalMembers - presentCount;
  double get attendanceRate =>
      totalMembers == 0 ? 0 : presentCount / totalMembers;
}

/// QR check-in and club days.
///
/// Writes go straight to Firestore rather than through the `checkInMember`
/// Cloud Function: that function is deployed but its Cloud Run invoker
/// binding could not be set, so every call returns 401. Firestore rules are
/// the enforcement point for this path — see firestore.rules, which is
/// written but not yet deployed. Until it is, the checks in this file are
/// for the operator's benefit, not a security boundary.
class CheckInService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ---------------------------------------------------------------------------
  // Member QR tokens
  // ---------------------------------------------------------------------------

  /// The current user's own check-in token, used to render their QR code.
  ///
  /// The token is opaque and carries no personal data, so anyone scanning the
  /// code with a generic QR app learns nothing about the member. A lookup
  /// document keyed by the token maps it back to the account.
  Future<String> getMyCheckInToken({bool rotate = false}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('Not signed in.');
    }

    final userRef = _db.collection('users').doc(user.uid);
    final existing = (await userRef.get()).data()?['checkInToken'] as String?;
    if (!rotate && existing != null && existing.isNotEmpty) {
      return existing;
    }

    final token = _generateToken();
    await _db.collection('checkInTokens').doc(token).set({
      'uid': user.uid,
      'email': user.email,
    });
    await userRef.set(
      {'email': user.email, 'checkInToken': token},
      SetOptions(merge: true),
    );

    // Drop the old mapping last, so a failure here cannot leave the member
    // without a working token.
    if (existing != null && existing.isNotEmpty && existing != token) {
      try {
        await _db.collection('checkInTokens').doc(existing).delete();
      } catch (_) {
        // A stale mapping is harmless: it points at the same member.
      }
    }
    return token;
  }

  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Resolves a scanned token to the account it belongs to.
  Future<({String uid, String email})?> _resolveToken(String token) async {
    final doc = await _db.collection('checkInTokens').doc(token).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    final uid = data['uid'] as String?;
    final email = data['email'] as String?;
    if (uid == null || email == null) return null;
    return (uid: uid, email: email);
  }

  Future<({String uid, String email})?> _resolveEmail(String email) async {
    final q = await _db
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return (uid: q.docs.first.id, email: email);
  }

  // ---------------------------------------------------------------------------
  // Club days
  // ---------------------------------------------------------------------------

  /// Date key for a club day, e.g. `2026-10-13`. Using the date as the
  /// document id means "open today's club day" is naturally idempotent — two
  /// admins tapping it at once get the same session rather than two.
  static String dateKeyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  CollectionReference<Map<String, dynamic>> _days(String groupId) =>
      _db.collection('groups').doc(groupId).collection('clubDays');

  /// Opens today's club day, creating it on first use. Returns the date key.
  Future<String> openClubDay(String groupId, {String? groupName}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in.');

    final now = DateTime.now();
    final key = dateKeyFor(now);
    await _days(groupId).doc(key).set({
      'dateKey': key,
      'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
      'isOpen': true,
      'openedBy': user.email,
      'openedAt': FieldValue.serverTimestamp(),
      if (groupName != null) 'groupName': groupName,
    }, SetOptions(merge: true));
    return key;
  }

  Future<void> closeClubDay(String groupId, String dateKey) async {
    await _days(groupId).doc(dateKey).set({
      'isOpen': false,
      'closedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchClubDay(
    String groupId,
    String dateKey,
  ) =>
      _days(groupId).doc(dateKey).snapshots();

  /// Club days newest first, for the statistics list.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchClubDays(String groupId) =>
      _days(groupId).orderBy('dateKey', descending: true).snapshots();

  /// Live attendance for one club day, newest scan first — this is what makes
  /// names appear in the sheet the moment someone is scanned.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchClubDayCheckIns(
    String groupId,
    String dateKey,
  ) =>
      _days(groupId)
          .doc(dateKey)
          .collection('checkIns')
          .orderBy('checkedInAt', descending: true)
          .snapshots();

  /// Records a member present at a club day.
  ///
  /// Pass [token] for a QR scan or [memberEmail] to add someone by hand when
  /// their phone is dead.
  Future<CheckInResult> checkInToClubDay({
    required String groupId,
    required String dateKey,
    String? token,
    String? memberEmail,
  }) async {
    assert(
      (token != null) ^ (memberEmail != null),
      'Pass exactly one of token or memberEmail.',
    );

    final officer = _auth.currentUser;
    if (officer == null || officer.email == null) {
      return const CheckInResult(ok: false, message: 'You are not signed in.');
    }

    try {
      final who = token != null
          ? await _resolveToken(token)
          : await _resolveEmail(memberEmail!);
      if (who == null) {
        return CheckInResult(
          ok: false,
          message: token != null
              ? "This code isn't recognized."
              : 'No account for that email.',
        );
      }

      final groupSnap =
          await _db.collection('groups').doc(groupId).get();
      final members =
          List<String>.from(groupSnap.data()?['members'] ?? const []);
      if (!members.contains(who.email)) {
        return const CheckInResult(
          ok: false,
          message: 'That person is not a member of this club.',
        );
      }

      final daySnap = await _days(groupId).doc(dateKey).get();
      if (daySnap.data()?['isOpen'] != true) {
        return const CheckInResult(
          ok: false,
          message: 'Club day is closed. Reopen it to keep scanning.',
        );
      }

      final profile = await _db.collection('users').doc(who.uid).get();
      final p = profile.data() ?? const <String, dynamic>{};
      final name = [p['firstName'], p['lastName']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
      final displayName = name.isEmpty ? who.email : name;
      final photoUrl = p['profilePicture'] as String?;

      // Doc id is the uid, so a second scan updates one row instead of
      // inflating the count.
      final ref = _days(groupId)
          .doc(dateKey)
          .collection('checkIns')
          .doc(who.uid);

      if ((await ref.get()).exists) {
        return CheckInResult(
          ok: true,
          alreadyCheckedIn: true,
          displayName: displayName,
          email: who.email,
          photoUrl: photoUrl,
          message: '$displayName is already signed in',
        );
      }

      await ref.set({
        'uid': who.uid,
        'email': who.email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'checkedInAt': FieldValue.serverTimestamp(),
        'checkedInBy': officer.email,
        'method': token != null ? 'qr' : 'manual',
      });

      return CheckInResult(
        ok: true,
        displayName: displayName,
        email: who.email,
        photoUrl: photoUrl,
        message: '$displayName signed in',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const CheckInResult(
          ok: false,
          message: 'Not allowed. Check that you are an admin of this club.',
        );
      }
      return CheckInResult(ok: false, message: 'Sign-in failed: ${e.code}');
    } catch (_) {
      return const CheckInResult(
        ok: false,
        message: 'Network problem. Check your connection and try again.',
      );
    }
  }

  /// Removes a check-in, for a mis-scan.
  Future<void> undoClubDayCheckIn(
    String groupId,
    String dateKey,
    String uid,
  ) =>
      _days(groupId).doc(dateKey).collection('checkIns').doc(uid).delete();

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------

  /// Builds the full attendance sheet for one club day: every member of the
  /// club as a row, marked present or absent. Absences are the point — a list
  /// of only the people who scanned cannot tell you who is missing.
  Future<ClubDayReport> buildReport(String groupId, String dateKey) async {
    final groupSnap = await _db.collection('groups').doc(groupId).get();
    final members = List<String>.from(
      groupSnap.data()?['members'] ?? const [],
    )..sort();

    final daySnap = await _days(groupId).doc(dateKey).get();
    final day = daySnap.data() ?? const <String, dynamic>{};

    final checkIns =
        await _days(groupId).doc(dateKey).collection('checkIns').get();
    final byEmail = <String, Map<String, dynamic>>{};
    for (final d in checkIns.docs) {
      final e = d.data()['email'] as String?;
      if (e != null) byEmail[e] = d.data();
    }

    // Names come from the check-in row when present, and from the member's
    // profile otherwise, so absent rows are not bare email addresses.
    final rows = <AttendanceRow>[];
    for (final email in members) {
      final hit = byEmail[email];
      if (hit != null) {
        rows.add(AttendanceRow(
          email: email,
          displayName: (hit['displayName'] as String?) ?? email,
          present: true,
          checkedInAt: (hit['checkedInAt'] as Timestamp?)?.toDate(),
          photoUrl: hit['photoUrl'] as String?,
          method: hit['method'] as String?,
        ));
      } else {
        rows.add(AttendanceRow(
          email: email,
          displayName: await _nameFor(email) ?? email,
          present: false,
        ));
      }
    }

    // Present first, then by time, so the sheet reads as an arrival log.
    rows.sort((a, b) {
      if (a.present != b.present) return a.present ? -1 : 1;
      if (a.present && b.present) {
        final at = a.checkedInAt, bt = b.checkedInAt;
        if (at != null && bt != null) return at.compareTo(bt);
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    return ClubDayReport(
      dateKey: dateKey,
      date: (day['date'] as Timestamp?)?.toDate() ??
          DateTime.tryParse(dateKey) ??
          DateTime.now(),
      isOpen: day['isOpen'] == true,
      rows: rows,
    );
  }

  final Map<String, String?> _nameCache = {};

  Future<String?> _nameFor(String email) async {
    if (_nameCache.containsKey(email)) return _nameCache[email];
    try {
      final q = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return _nameCache[email] = null;
      final p = q.docs.first.data();
      final name = [p['firstName'], p['lastName']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
      return _nameCache[email] = name.isEmpty ? null : name;
    } catch (_) {
      return _nameCache[email] = null;
    }
  }

  /// Comma-separated attendance, for pasting into Sheets or Excel.
  String reportToCsv(ClubDayReport report, {String? clubName}) {
    String esc(String v) =>
        v.contains(',') || v.contains('"') ? '"${v.replaceAll('"', '""')}"' : v;

    final out = StringBuffer();
    if (clubName != null) out.writeln('Club,${esc(clubName)}');
    out.writeln('Club day,${report.dateKey}');
    out.writeln('Present,${report.presentCount}');
    out.writeln('Absent,${report.absentCount}');
    out.writeln('Members,${report.totalMembers}');
    out.writeln();
    out.writeln('Name,Email,Status,Signed in at,Method');
    for (final r in report.rows) {
      final t = r.checkedInAt;
      final time = t == null
          ? ''
          : '${t.year}-${t.month.toString().padLeft(2, '0')}-'
              '${t.day.toString().padLeft(2, '0')} '
              '${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}';
      out.writeln(
        '${esc(r.displayName)},${esc(r.email)},'
        '${r.present ? 'Present' : 'Absent'},$time,${r.method ?? ''}',
      );
    }
    return out.toString();
  }

  /// Every group, for the school admin's cross-club view.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllGroups() =>
      _db.collection('groups').snapshots();
}
