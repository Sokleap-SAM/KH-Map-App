import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  static final ValueNotifier<String?> tokenNotifier = ValueNotifier<String?>(null);

  static bool get isLoggedIn {
    final token = tokenNotifier.value;
    return token != null && token.isNotEmpty;
  }

  static Future<void> initTokenNotifier() async {
    final prefs = await SharedPreferences.getInstance();
    tokenNotifier.value = prefs.getString(_tokenKey);
  }

  // ===========================================================================
  // 1. REGISTER & EMAIL VERIFICATION
  // ===========================================================================

  /// Validates email syntax on the client side before sending network requests
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email.trim());
  }

  /// Register new user. Backend triggers verification email/OTP.
  Future<http.Response> register(String name, String email, String password) async {
    if (!isValidEmail(email)) {
      throw FormatException('Invalid email address format.');
    }
    
    final url = Uri.parse("$baseUrl/users/register"); 
    return await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"name": name, "email": email, "password": password}),
    );
  }

  /// Verifies the OTP code sent to the user's real email inbox.
  Future<bool> verifyOtp(String email, String otp) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/verify"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "otp": otp}),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  /// Resends verification code to the email address.
  Future<bool> resendVerificationCode(String email) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/resend-code"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email}),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  // ===========================================================================
  // 2. EMAIL & PASSWORD LOGIN
  // ===========================================================================

  Future<LoginResult> login(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    final url = Uri.parse("$baseUrl/users/login");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": cleanEmail, "password": cleanPassword}),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      final token = data['access_token'] as String?;
      await prefs.setString(_tokenKey, token ?? '');
      tokenNotifier.value = token;
      return LoginResult.success;
    }

    // Handles unverified real email addresses
    if (response.statusCode == 401 && response.body.contains('UNVERIFIED_ACCOUNT')) {
      return LoginResult.unverified;
    }

    return LoginResult.failed;
  }

  // ===========================================================================
  // 3. GOOGLE SIGN-IN (ALWAYS PROMPTS FOR ACCOUNT SELECTION)
  // ===========================================================================

  Future<GoogleAuthOutcome> loginWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // 🔑 CRITICAL: Force sign out first so the Google Account Chooser
      // pops up every single time instead of using cached credentials.
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return GoogleAuthOutcome.cancelled;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) return GoogleAuthOutcome.failed;

      // Exchange Firebase ID Token for backend JWT
      final ok = await firebaseLogin(idToken);
      return ok ? GoogleAuthOutcome.success : GoogleAuthOutcome.failed;
    } on FirebaseAuthException catch (e) {
      const cancelledCodes = {
        'canceled',
        'cancelled',
        'user-cancelled',
        'web-context-canceled',
        'popup-closed-by-user',
      };
      if (cancelledCodes.contains(e.code)) return GoogleAuthOutcome.cancelled;
      debugPrint('Google Sign-In Firebase Error: ${e.code} - ${e.message}');
      return GoogleAuthOutcome.failed;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
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

  // ===========================================================================
  // 4. FORGOT PASSWORD & RESET
  // ===========================================================================

  /// Sends password reset OTP via Backend API
  Future<bool> sendForgotPasswordOtp(String email) async {
    if (!isValidEmail(email)) return false;

    final response = await http.post(
      Uri.parse("$baseUrl/users/forgot-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email}),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  /// Reset password using OTP code sent to real email inbox
  Future<bool> resetPassword(String email, String otp, String newPassword) async {
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

  /// Direct Firebase Password Reset Link (Alternative to OTP)
  Future<bool> sendFirebasePasswordResetEmail(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      debugPrint('Firebase password reset error: $e');
      return false;
    }
  }

  // ===========================================================================
  // 5. LOGOUT
  // ===========================================================================

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    tokenNotifier.value = null;

    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Sign-out exception: $e');
    }
  }
}
