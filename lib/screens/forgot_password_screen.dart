import 'package:flutter/material.dart';
import 'package:kh_map_app/providers/settings_provider.dart';
import 'package:kh_map_app/services/auth_service.dart';
import 'package:kh_map_app/utils/theme/app_palette.dart';
import 'package:provider/provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _isCodeSent = false; // Toggles between Step 1 and Step 2
  bool _isLoading = false;

  void _handleSendCode() async {
    final t = context.read<SettingsProvider>().t;
    setState(() => _isLoading = true);
    bool success = await _authService.sendForgotPasswordOtp(
      emailController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      setState(() => _isCodeSent = true);
      _showMessage(t.codeSent);
    } else {
      _showMessage(t.emailNotFound);
    }
  }

  void _handleResetPassword() async {
    final t = context.read<SettingsProvider>().t;
    setState(() => _isLoading = true);
    bool success = await _authService.resetPassword(
      emailController.text,
      otpController.text,
      passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _showMessage(t.passwordChanged);
      Navigator.pop(context); // Go back to Login
    } else {
      _showMessage(t.invalidCode);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.forgotPasswordTitle,
              style: TextStyle(
                color: p.accent,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isCodeSent ? t.enterCodeSubtitle : t.enterEmailSubtitle,
              style: TextStyle(color: p.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // STEP 1: Enter Email
            _buildTextField(
              controller: emailController,
              label: t.emailField,
              icon: Icons.email_outlined,
              enabled: !_isCodeSent, // Lock email after code is sent
            ),

            // STEP 2: Enter OTP and New Password (Shows only after code is sent)
            if (_isCodeSent) ...[
              const SizedBox(height: 20),
              _buildTextField(
                controller: otpController,
                label: t.codeField,
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: passwordController,
                label: t.newPasswordField,
                icon: Icons.lock_outline,
                isPassword: true,
              ),
            ],

            const SizedBox(height: 40),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (_isCodeSent ? _handleResetPassword : _handleSendCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF91A5D4),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        _isCodeSent ? t.changePassword : t.sendCode,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final p = context.palette;
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: TextStyle(color: p.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: p.textFaint),
        prefixIcon: Icon(icon, color: p.textFaint),
        filled: true,
        fillColor: p.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
