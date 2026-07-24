import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Outcome of a "Continue with Google" attempt, so the UI can tell a real
/// failure apart from the user simply dismissing the Google prompt.
enum GoogleAuthOutcome { success, cancelled, failed }

/// Outcome of an email/password login. [unverified] means the account exists
/// but its email was never confirmed (backend 401 + `UNVERIFIED_ACCOUNT`), so
/// the UI should route to the OTP verification screen rather than error out.
enum LoginResult { success, unverified, failed }

class AuthService {
  static String baseUrl = dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:3000';
  static const String _tokenKey = 'access_token';

  // Broadcasts the current access token. Listeners (e.g. MapScreen) react
  // to login/logout so they can refresh per-user state like favorites.
  static final ValueNotifier<String?> tokenNotifier = ValueNotifier<String?>(
    null,
  );

  // Whether a user is currently signed in. Reads the in-memory notifier, which
  // is kept in sync with SharedPreferences on startup, login and logout.
  static bool get isLoggedIn {
    final token = tokenNotifier.value;
    return token != null && token.isNotEmpty;
  }

  // Call once during app startup so the notifier reflects any persisted token.
  static Future<void> initTokenNotifier() async {
    final prefs = await SharedPreferences.getInstance();
    tokenNotifier.value = prefs.getString(_tokenKey);
  }

  // 1. REGISTER
  Future<http.Response> register(
    String name,
    String email,
    String password,
  ) async {
    final url = Uri.parse("$baseUrl/users/register");
    return await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"name": name, "email": email, "password": password}),
    );
  }

  // 2. LOGIN
  //
  // Returns [LoginResult.unverified] when the backend rejects an existing but
  // unverified account (401 carrying the `UNVERIFIED_ACCOUNT` message code) so
  // the caller can send the user to the OTP verification screen.
  Future<LoginResult> login(String email, String password) async {
    final url = Uri.parse("$baseUrl/users/login");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "password": password}),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Save JWT Token to phone memory
      final prefs = await SharedPreferences.getInstance();
      final token = data['access_token'] as String?;
      await prefs.setString(_tokenKey, token ?? '');
      tokenNotifier.value = token;
      return LoginResult.success;
    }

    // Match the message code whether it arrives as a bare string or a list.
    if (response.statusCode == 401 &&
        response.body.contains('UNVERIFIED_ACCOUNT')) {
      return LoginResult.unverified;
    }
    return LoginResult.failed;
  }

  // 2b. GOOGLE 1-CLICK (Firebase)
  //
  // Runs the Firebase Google sign-in, gets the Firebase ID token, then exchanges
  // it for the app's own JWT via [firebaseLogin]. The Firebase token itself is
  // never sent anywhere except /users/firebase-login.
  Future<GoogleAuthOutcome> loginWithGoogle() async {
    try {
      final auth = FirebaseAuth.instance;
      final provider = GoogleAuthProvider();
      // Web opens a popup; mobile/desktop use the native provider flow.
      final UserCredential cred = kIsWeb
          ? await auth.signInWithPopup(provider)
          : await auth.signInWithProvider(provider);

      final idToken = await cred.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) return GoogleAuthOutcome.failed;

      final ok = await firebaseLogin(idToken);
      return ok ? GoogleAuthOutcome.success : GoogleAuthOutcome.failed;
    } on FirebaseAuthException catch (e) {
      // User dismissed the Google prompt — not an error worth alarming them over.
      const cancelled = {
        'canceled',
        'cancelled',
        'user-cancelled',
        'web-context-canceled',
        'popup-closed-by-user',
      };
      if (cancelled.contains(e.code)) return GoogleAuthOutcome.cancelled;
      debugPrint('Google sign-in failed: ${e.code} ${e.message}');
      return GoogleAuthOutcome.failed;
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      return GoogleAuthOutcome.failed;
    }
  }

  // Exchange a Firebase ID token for the app's JWT. Stores the returned
  // access_token exactly like [login] so the rest of the app is unchanged.
  Future<bool> firebaseLogin(String idToken) async {
    final url = Uri.parse("$baseUrl/users/firebase-login");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"idToken": idToken}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      final token = data['access_token'] as String?;
      await prefs.setString(_tokenKey, token ?? '');
      tokenNotifier.value = token;
      return true;
    }
    return false;
  }

  // 3. LOGOUT
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    tokenNotifier.value = null;
    // Also drop the Firebase session so the next Google sign-in re-prompts.
    // No-op / harmless when the user logged in with email + password.
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Firebase signOut skipped: $e');
    }
  }

  Future<bool> sendForgotPasswordOtp(String email) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/forgot-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email}),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  Future<bool> resetPassword(
    String email,
    String otp,
    String newPassword,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/reset-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "otp": otp,
        "newPassword": newPassword,
      }),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  // 4. VERIFY ACCOUNT (email OTP after register)
  //
  // After [register] the backend emails a one-time code; the user types it here
  // to prove they own the address before the account becomes usable. Google
  // 1-click users never hit this path — they're provisioned pre-verified.
  //
  // NOTE: /users/verify is confirmed by the backend brief; confirm the request
  // body shape ({email, otp}) matches the backend if verification ever fails.
  Future<bool> verifyOtp(String email, String otp) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/verify"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "otp": otp}),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  // Re-send the verification code to the same email.
  Future<bool> resendVerificationCode(String email) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/resend-code"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email}),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }
}
