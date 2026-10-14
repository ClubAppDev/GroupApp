import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import * as admin from "firebase-admin";
import { randomBytes } from "crypto";

// The Anthropic API key is stored as a Firebase secret, never shipped in the app.
// Set it once with:  firebase functions:secrets:set ANTHROPIC_API_KEY
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const ADMIN_SIGNUP_CODE = defineSecret("ADMIN_SIGNUP_CODE");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

// System prompt scopes Claude to *this* app so it answers support questions
// about GroupApp's real features rather than acting as a generic chatbot.
const SYSTEM_PROMPT = `You are the friendly support assistant for GroupApp, a mobile app for student clubs and groups.

GroupApp's features:
- Group chats: users create or join group chats. Public groups can be joined with a 6-character join code, or discovered on the Discover page. Private groups require an invite.
- Join codes: each group has a 6-character code (letters + numbers). Share it so others can join. Find it via the group's info (i) button.
- Direct messages: users can message each other one-on-one, including tapping "Message" next to a member in a group's info panel.
- Calendar & events: club officers with event permissions can add events that appear on the group chat and every member's home calendar. Filter which groups show via the calendar settings (tune) icon.
- Announcements: authorized club officers can publish announcements directly into the group chat.
- Roles: the creator is President and can appoint Co-Presidents and Officers, assign members, and create custom titles with configurable permissions. "Who can post" can be set to all members or members with posting permission.
- Profile: users set a first/last name and profile picture in Settings. Settings also has a Dark Mode toggle.

Guidelines:
- Be concise, warm, and practical. Give step-by-step instructions when explaining how to do something.
- Only answer questions about GroupApp. If asked something unrelated, gently redirect to app support topics.
- If you don't know an app-specific detail, say so and suggest contacting a human admin rather than inventing features.
- Never ask for or handle passwords, join codes, or personal data.`;

type ChatMessage = { role: "user" | "assistant"; content: string };

export const supportChat = onCall(
  {
    secrets: [ANTHROPIC_API_KEY],
    // Cap concurrency/instances to keep costs predictable.
    maxInstances: 10,
    region: "us-central1",
  },
  async (request) => {
    // Firebase Auth is enforced here — only signed-in users can call this.
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to use support chat.",
      );
    }

    const history = request.data?.messages as ChatMessage[] | undefined;
    if (!Array.isArray(history) || history.length === 0) {
      throw new HttpsError("invalid-argument", "messages must be a non-empty array.");
    }

    // Basic input hygiene: bound history length and message size.
    const trimmed = history.slice(-20).map((m) => ({
      role: m.role === "assistant" ? ("assistant" as const) : ("user" as const),
      content: String(m.content ?? "").slice(0, 4000),
    }));

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });

    try {
      const response = await client.messages.create({
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages: trimmed,
      });

      const reply = response.content
        .filter((b): b is Anthropic.TextBlock => b.type === "text")
        .map((b) => b.text)
        .join("")
        .trim();

      return { reply: reply || "Sorry, I couldn't generate a response. Please try again." };
    } catch (err) {
      console.error("Claude API error:", err);
      throw new HttpsError("internal", "The assistant is unavailable right now. Please try again.");
    }
  },
);

export const verifyAdminSignupCode = onCall(
  {
    secrets: [ADMIN_SIGNUP_CODE],
    region: "us-central1",
    maxInstances: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const rawCode = request.data?.code;
    const submittedCode = String(rawCode ?? "").trim();
    if (!submittedCode) {
      throw new HttpsError("invalid-argument", "Verification code is required.");
    }

    const expectedCode = ADMIN_SIGNUP_CODE.value().trim();
    if (!expectedCode) {
      throw new HttpsError(
        "failed-precondition",
        "Admin verification is not configured.",
      );
    }
    if (submittedCode != expectedCode) {
      throw new HttpsError("permission-denied", "Invalid verification code.");
    }

    const uid = request.auth.uid;
    const userRecord = await admin.auth().getUser(uid);
    const existingClaims = userRecord.customClaims || {};

    await admin.auth().setCustomUserClaims(uid, {
      ...existingClaims,
      schoolAdmin: true,
    });

    await admin.firestore().collection("users").doc(uid).set(
      {
        email: request.auth.token.email ?? null,
        schoolAdmin: true,
        schoolAdminVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        schoolAdminVerifiedBy: "verifyAdminSignupCode",
      },
      { merge: true },
    );

    return { success: true };
  },
);

// ---------------------------------------------------------------------------
// QR check-in
//
// The member displays a QR code holding an opaque token; a club admin scans it.
// The attendance write happens here rather than in the app so that none of the
// checks below can be bypassed by a modified client.
// ---------------------------------------------------------------------------

// Late arrivals still get counted for a short window after check-in closes.
const CHECK_IN_GRACE_MS = 15 * 60 * 1000;

export const checkInMember = onCall(
  { region: "us-central1", maxInstances: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const callerEmail = request.auth.token.email;
    if (!callerEmail) {
      throw new HttpsError("failed-precondition", "Your account has no email.");
    }

    const groupId = String(request.data?.groupId ?? "").trim();
    const eventId = String(request.data?.eventId ?? "").trim();
    const token = String(request.data?.token ?? "").trim();
    // Manual check-in names the member directly, for a dead or absent phone.
    // It is admin-only in exactly the same way a scan is.
    const manualEmail = String(request.data?.memberEmail ?? "")
      .trim()
      .toLowerCase();
    if (!groupId || !eventId || (!token && !manualEmail)) {
      throw new HttpsError(
        "invalid-argument",
        "groupId, eventId and either token or memberEmail are required.",
      );
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const eventRef = groupRef.collection("events").doc(eventId);

    const [groupSnap, eventSnap] = await Promise.all([
      groupRef.get(),
      eventRef.get(),
    ]);
    if (!groupSnap.exists) throw new HttpsError("not-found", "Group not found.");
    if (!eventSnap.exists) throw new HttpsError("not-found", "Event not found.");

    const group = groupSnap.data() ?? {};
    const event = eventSnap.data() ?? {};

    // Check-in permission is granted by a club role. Older clubs without role
    // assignments continue to use their existing admins list.
    // schoolAdmin is read off the ID token (set by verifyAdminSignupCode), so
    // it cannot be forged — but it only refreshes when the token does.
    const admins: string[] = Array.isArray(group.admins) ? group.admins : [];
    const memberPermissions = group.memberPermissions as
      | Record<string, string[]>
      | undefined;
    const isClubAdmin = group.createdBy === callerEmail ||
      (memberPermissions
        ? (memberPermissions[callerEmail] ?? []).includes("manage_check_ins")
        : admins.includes(callerEmail));
    const isSchoolAdmin = request.auth.token.schoolAdmin === true;
    if (!isClubAdmin && !isSchoolAdmin) {
      throw new HttpsError(
        "permission-denied",
        "You need the event attendance permission to check members in.",
      );
    }

    // Window is judged on server time; the client's clock is never trusted.
    if (event.checkInEnabled !== true) {
      throw new HttpsError("failed-precondition", "Check-in is not open.");
    }
    const now = Date.now();
    const opensAt: number | undefined = event.checkInOpensAt?.toMillis?.();
    const closesAt: number | undefined = event.checkInClosesAt?.toMillis?.();
    if (opensAt && now < opensAt) {
      throw new HttpsError("failed-precondition", "Check-in hasn't opened yet.");
    }
    if (closesAt && now > closesAt + CHECK_IN_GRACE_MS) {
      throw new HttpsError("failed-precondition", "Check-in has closed.");
    }

    // Resolve the scanned token, or the named member for a manual entry.
    const userQuery = token
      ? await db
          .collection("users")
          .where("checkInToken", "==", token)
          .limit(1)
          .get()
      : await db
          .collection("users")
          .where("email", "==", manualEmail)
          .limit(1)
          .get();
    if (userQuery.empty) {
      throw new HttpsError(
        "not-found",
        token ? "This code isn't recognized." : "No account for that email.",
      );
    }
    const userDoc = userQuery.docs[0];
    const user = userDoc.data();
    const memberEmail: string | undefined = user.email;
    if (!memberEmail) {
      throw new HttpsError("failed-precondition", "That account has no email.");
    }

    // Membership is keyed on email throughout this app, matching groups.members.
    const members: string[] = Array.isArray(group.members) ? group.members : [];
    if (!members.includes(memberEmail)) {
      throw new HttpsError(
        "permission-denied",
        "That person is not a member of this club.",
      );
    }

    // Doc id is the uid, so a repeat scan can never create a second row. The
    // transaction keeps the exists-check and the write atomic in case two
    // officers scan the same person at the same moment.
    const checkInRef = eventRef.collection("checkIns").doc(userDoc.id);
    const displayName =
      [user.firstName, user.lastName].filter(Boolean).join(" ") || memberEmail;

    const alreadyCheckedIn = await db.runTransaction(async (tx) => {
      const existing = await tx.get(checkInRef);
      if (existing.exists) return true;
      tx.set(checkInRef, {
        uid: userDoc.id,
        email: memberEmail,
        displayName,
        photoUrl: user.profilePicture ?? null,
        checkedInAt: admin.firestore.FieldValue.serverTimestamp(),
        checkedInBy: callerEmail,
        method: token ? "qr" : "manual",
      });
      return false;
    });

    // Identity is returned either way so the scanner screen can show a name
    // and photo for the officer to check against the person in front of them.
    return {
      success: true,
      alreadyCheckedIn,
      member: {
        displayName,
        email: memberEmail,
        photoUrl: user.profilePicture ?? null,
      },
    };
  },
);

export const getCheckInToken = onCall(
  { region: "us-central1", maxInstances: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const userRef = admin.firestore().collection("users").doc(request.auth.uid);
    const snap = await userRef.get();
    const existing: string | undefined = snap.data()?.checkInToken;

    // The token is stable across meetings unless rotation is asked for, so a
    // member's QR code stays the same image. Rotating invalidates a leaked code.
    if (existing && request.data?.rotate !== true) {
      return { token: existing };
    }

    const token = randomBytes(24).toString("base64url");
    await userRef.set(
      { email: request.auth.token.email ?? null, checkInToken: token },
      { merge: true },
    );
    return { token };
  },
);
