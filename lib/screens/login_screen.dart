import 'package:flutter/material.dart';
import 'package:kh_map_app/providers/settings_provider.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:kh_map_app/screens/forgot_password_screen.dart';

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
        bool success = await _authService.login(
          emailController.text,
          passwordController.text,
        );

        if (success) {
          if (!mounted) return;
          Navigator.pop(context, true);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.loginSuccess)));
        } else {
          final response = await _authService.register(
            nameController.text,
            emailController.text,
            passwordController.text,
          );
          if (!mounted) return;

          if (response.statusCode == 201) {
            setState(() => isLoginMode = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t.registerSuccess)),
            );
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
        if (response.statusCode == 201) {
          bool loginSuccess = await _authService.login(
            emailController.text,
            passwordController.text,
          );
          if (!mounted) return;

          if (loginSuccess) {
            _finishAuth();
          }
        } else {
          if (!mounted) return;
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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

            // 5. Toggle Switch
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
