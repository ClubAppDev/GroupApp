import 'package:cloud_functions/cloud_functions.dart';

/// Outcome of a single scan, shaped for the scanner UI.
///
/// A rejected scan is not an exception as far as the UI is concerned — the
/// officer needs to see *why* it failed and keep scanning, so failures come
/// back as a value with a message rather than something to catch.
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

/// QR check-in, enforced by Cloud Functions.
///
/// Every rule lives in `checkInMember` server-side: that the caller is a club
/// admin, that the scanned person is a member of that club, that check-in is
/// open by *server* time, and that nobody is recorded twice. None of it can be
/// bypassed by a modified client, so none of it is duplicated here.
class CheckInService {
  // Region must match the functions' declared region or calls fail with an
  // opaque 'not-found'.
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  /// The current user's own check-in token, used to render their QR code.
  ///
  /// The token is opaque and holds no personal data, so anyone scanning the
  /// code with a generic QR app learns nothing about the member.
  ///
  /// Pass [rotate] to invalidate the old token — use it if a member's code
  /// has been screenshotted and passed around.
  Future<String> getMyCheckInToken({bool rotate = false}) async {
    final callable = _functions.httpsCallable('getCheckInToken');
    final res = await callable.call<Map<String, dynamic>>({'rotate': rotate});
    final token = res.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Could not get a check-in code.');
    }
    return token;
  }

  /// Record a member as present.
  ///
  /// Pass [token] for a scan, or [memberEmail] to check someone in by hand
  /// when their phone is dead. Both paths are admin-only on the server.
  Future<CheckInResult> checkIn({
    required String groupId,
    required String eventId,
    String? token,
    String? memberEmail,
  }) async {
    assert(
      (token != null) ^ (memberEmail != null),
      'Pass exactly one of token or memberEmail.',
    );

    try {
      final callable = _functions.httpsCallable('checkInMember');
      final res = await callable.call<Map<String, dynamic>>({
        'groupId': groupId,
        'eventId': eventId,
        if (token != null) 'token': token,
        if (memberEmail != null) 'memberEmail': memberEmail,
      });

      final data = res.data;
      final member = Map<String, dynamic>.from(
        (data['member'] as Map?) ?? const {},
      );
      final name = member['displayName'] as String?;
      final already = data['alreadyCheckedIn'] == true;

      return CheckInResult(
        ok: true,
        alreadyCheckedIn: already,
        displayName: name,
        email: member['email'] as String?,
        photoUrl: member['photoUrl'] as String?,
        message: already
            ? '${name ?? 'This member'} is already checked in'
            : '${name ?? 'Member'} checked in',
      );
    } on FirebaseFunctionsException catch (e) {
      // The function's HttpsError messages are written to be shown to the
      // officer verbatim ('That person is not a member of this club', etc).
      return CheckInResult(
        ok: false,
        message: e.message ?? 'Check-in failed. Please try again.',
      );
    } catch (_) {
      return const CheckInResult(
        ok: false,
        message: 'Network problem. Check your connection and try again.',
      );
    }
  }
}
