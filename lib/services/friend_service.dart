import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Where a pair of people stand with each other.
enum FriendState {
  /// No document between them.
  none,

  /// You asked; they have not answered.
  outgoing,

  /// They asked; it is your turn.
  incoming,

  /// Accepted by both.
  friends,

  /// Declined, and left in place so the same request cannot be spammed.
  declined,
}

class Friendship {
  const Friendship({
    required this.id,
    required this.users,
    required this.requestedBy,
    required this.status,
    this.createdAt,
    this.respondedAt,
  });

  factory Friendship.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Friendship(
      id: doc.id,
      users: List<String>.from(d['users'] ?? const []),
      requestedBy: (d['requestedBy'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      respondedAt: (d['respondedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final List<String> users;
  final String requestedBy;
  final String status;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  String otherThan(String me) =>
      users.firstWhere((u) => u != me, orElse: () => '');

  FriendState stateFor(String me) {
    if (status == 'accepted') return FriendState.friends;
    if (status == 'declined') return FriendState.declined;
    return requestedBy == me ? FriendState.outgoing : FriendState.incoming;
  }
}

/// Friend requests, which are mutual by construction.
///
/// One document per pair, its id being both emails sorted and joined. That
/// single choice does most of the work: two people cannot end up with two
/// competing requests, "did I already ask?" is a document read rather than a
/// query, and the rules can say plainly that only the recipient may accept.
class FriendService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get myEmail => _auth.currentUser?.email;

  /// Sorted so both people compute the same id regardless of who asks.
  static String pairKey(String a, String b) {
    final pair = [a.toLowerCase(), b.toLowerCase()]..sort();
    // Firestore ids cannot contain '/', and emails never contain '|'.
    return '${pair[0]}|${pair[1]}';
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('friendships');

  /// Every friendship touching me, in any state. Filtering by status happens
  /// in Dart on purpose: array-contains plus an equality filter would need a
  /// composite index, and this collection is small per user.
  Stream<List<Friendship>> watchMyFriendships() {
    final me = myEmail;
    if (me == null) return Stream.value(const []);
    return _col
        .where('users', arrayContains: me)
        .snapshots()
        .map((s) => s.docs.map(Friendship.fromDoc).toList());
  }

  Stream<Friendship?> watchFriendshipWith(String other) {
    final me = myEmail;
    if (me == null) return Stream.value(null);
    return _col
        .doc(pairKey(me, other))
        .snapshots()
        .map((d) => d.exists ? Friendship.fromDoc(d) : null);
  }

  Future<void> sendRequest(String otherEmail) async {
    final me = myEmail;
    if (me == null) throw Exception('Not signed in.');
    final other = otherEmail.toLowerCase();
    if (other == me.toLowerCase()) {
      throw Exception('You cannot add yourself.');
    }

    final ref = _col.doc(pairKey(me, other));
    final existing = await ref.get();
    if (existing.exists) {
      final f = Friendship.fromDoc(existing);
      switch (f.stateFor(me)) {
        case FriendState.friends:
          throw Exception('You are already friends.');
        case FriendState.outgoing:
          throw Exception('Request already sent.');
        case FriendState.incoming:
          // They asked first — accepting is the kinder resolution.
          await respond(f.id, accept: true);
          return;
        case FriendState.declined:
        case FriendState.none:
          break;
      }
    }

    final pair = [me.toLowerCase(), other]..sort();
    await ref.set({
      'users': pair,
      'requestedBy': me,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Only the person who did not send it can answer; the rules enforce that
  /// too, so a modified client cannot accept on someone else's behalf.
  Future<void> respond(String friendshipId, {required bool accept}) =>
      _col.doc(friendshipId).update({
        'status': accept ? 'accepted' : 'declined',
        'respondedAt': FieldValue.serverTimestamp(),
      });

  /// Unfriending, and cancelling your own pending request, are the same act:
  /// remove the document.
  Future<void> remove(String friendshipId) => _col.doc(friendshipId).delete();

  /// Profile lookup by email, for member lists and profile cards.
  Future<Map<String, dynamic>?> profileFor(String email) async {
    final q = await _db
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return {'uid': q.docs.first.id, ...q.docs.first.data()};
  }

  static String displayNameFrom(Map<String, dynamic>? profile, String email) {
    if (profile == null) return email;
    final name = [
      profile['firstName'],
      profile['lastName'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return name.isEmpty ? email : name;
  }
}
