import 'package:flutter/material.dart';
import 'package:kh_map_app/providers/settings_provider.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:kh_map_app/screens/forgot_password_screen.dart';
import 'package:kh_map_app/screens/verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool isLoginMode = true;

  void _handleSubmit() async {
    final t = context.read<SettingsProvider>().t;
    if (!isLoginMode) {
      if (passwordController.text != confirmPasswordController.text) {
        _showError(t.passwordsDoNotMatch);
        return;
      }
    }
    setState(() => _isLoading = true);

    try {
      if (isLoginMode) {
        final result = await _authService.login(
          emailController.text,
          passwordController.text,
        );
        if (!mounted) return;

        if (result == LoginResult.success) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.loginSuccess)));
        } else if (result == LoginResult.unverified) {
          // Account exists but the email was never verified — route to the OTP
          // screen, then finish signing in once verified.
          final ok = await _verifyThenLogin();
          if (!mounted) return;
          if (ok) _finishAuth();
        } else {
          // No account (or wrong credentials) — fall back to registering.
          final response = await _authService.register(
            nameController.text,
            emailController.text,
            passwordController.text,
          );
          if (!mounted) return;

          if (response.statusCode == 201) {
            final ok = await _verifyThenLogin();
            if (!mounted) return;
            if (ok) {
              _finishAuth();
            } else {
              setState(() => isLoginMode = true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.registerSuccess)),
              );
            }
          } else {
            _showError(t.registerFailedEmailExists);
          }
        }
      } else {
        final response = await _authService.register(
          nameController.text,
          emailController.text,
          passwordController.text,
        );
        if (!mounted) return;

        if (response.statusCode == 201) {
          // New account created — make them verify the email (OTP) before login.
          final ok = await _verifyThenLogin();
          if (!mounted) return;
          if (ok) _finishAuth();
        } else {
          _showError(t.registerFailed);
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showError(t.cannotReachServer);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _finishAuth() {
    Navigator.pop(
      context,
      true,
    ); // Returns 'true' to AccountScreen to fetch profile
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<SettingsProvider>().t.success)),
    );
  }

  // After a successful email/password register, make the user verify the email
  // via the OTP screen, then sign them in. Returns true only when the email was
  // verified AND the subsequent login succeeded.
  Future<bool> _verifyThenLogin() async {
    if (!mounted) return false;
    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationScreen(email: emailController.text),
      ),
    );
    if (verified != true || !mounted) return false;
    final result = await _authService.login(
      emailController.text,
      passwordController.text,
    );
    return result == LoginResult.success;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Google 1-click: Firebase sign-in → exchange for app JWT. Same success path
  // as email/password login (pop back to AccountScreen with `true`).
  void _handleGoogleSignIn() async {
    final t = context.read<SettingsProvider>().t;
    setState(() => _isLoading = true);
    try {
      final outcome = await _authService.loginWithGoogle();
      if (!mounted) return;
      switch (outcome) {
        case GoogleAuthOutcome.success:
          Navigator.pop(context, true);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.loginSuccess)));
        case GoogleAuthOutcome.cancelled:
          break; // User backed out — stay on the screen, say nothing.
        case GoogleAuthOutcome.failed:
          _showError(t.googleSignInFailed);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Controllers to get the text from inputs
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context), // Go back to Account Screen
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isLoginMode ? t.login : t.createAccount,
              style: const TextStyle(
                color: Color(0xFFE8B67D),
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isLoginMode ? t.loginSubtitle : t.registerSubtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // 1. Name Field (Only shows during Registration)
            if (!isLoginMode) ...[
              _buildTextField(
                controller: nameController,
                label: t.nameField,
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 20),
            ],

            // 2. Email Field
            _buildTextField(
              controller: emailController,
              label: t.emailField,
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),

            // 3. Password Field
            _buildTextField(
              controller: passwordController,
              label: t.passwordField,
              icon: Icons.lock_outline,
              isPassword: true,
            ),
            if (!isLoginMode) ...[
              const SizedBox(height: 20),
              _buildTextField(
                controller: confirmPasswordController,
                label: t.confirmPasswordField,
                icon: Icons.lock_reset_outlined,
                isPassword: true,
              ),
            ],
            if (isLoginMode)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordScreen(),
                      ),
                    );
                  },
                  child: Text(
                    t.forgotPasswordLink,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 40),

            // 4. Main Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  _isLoading ? null : _handleSubmit();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF91A5D4),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  isLoginMode ? t.signIn : t.signUp,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 5. "or" divider
            Row(
              children: [
                const Expanded(child: Divider(color: Colors.white24)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    t.orDivider,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                const Expanded(child: Divider(color: Colors.white24)),
              ],
            ),
            const SizedBox(height: 20),

            // 6. Continue with Google (Firebase 1-click)
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _handleGoogleSignIn,
                icon: Image.asset(
                  'assets/images/google_icon.png',
                  width: 22,
                  height: 22,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.login, color: Colors.white),
                ),
                label: Text(
                  t.continueWithGoogle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(13),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 7. Toggle Switch
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    isLoginMode = !isLoginMode;
                  });
                },
                child: Text(
                  isLoginMode ? t.noAccountSignUp : t.haveAccountSignIn,
                  style: const TextStyle(color: Color(0xFFE8B67D)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper function to create clean text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE8B67D)),
        ),
        filled: true,
        fillColor: Colors.white.withAlpha(13),
      ),
    );
  }
}
