import 'package:flutter/material.dart';
import 'package:kh_map_app/services/auth_service.dart';
import 'package:kh_map_app/utils/constants/colors.dart';

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
    setState(() => _isLoading = true);
    bool success = await _authService.sendForgotPasswordOtp(emailController.text);
    setState(() => _isLoading = false);

    if (success) {
      setState(() => _isCodeSent = true);
      _showMessage("លេខកូដត្រូវបានផ្ញើ!");
    } else {
      _showMessage("រកមិនឃើញអ៊ីមែលនេះទេ");
    }
  }

  void _handleResetPassword() async {
    setState(() => _isLoading = true);
    bool success = await _authService.resetPassword(
      emailController.text,
      otpController.text,
      passwordController.text,
    );
    setState(() => _isLoading = false);

    if (success) {
      _showMessage("ប្តូរលេខសម្ងាត់ជោគជ័យ!");
      Navigator.pop(context); // Go back to Login
    } else {
      _showMessage("លេខកូដមិនត្រឹមត្រូវ");
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "ភ្លេចលេខសម្ងាត់",
              style: TextStyle(color: Color(0xFFE8B67D), fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              _isCodeSent ? "សូមបញ្ចូលលេខកូដ ៦ ខ្ទង់ដែលបានផ្ញើទៅកាន់អ៊ីមែលរបស់អ្នក" : "សូមបញ្ចូលអ៊ីមែលរបស់អ្នកដើម្បីទទួលបានលេខកូដ",
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // STEP 1: Enter Email
            _buildTextField(
              controller: emailController,
              label: "អ៊ីមែល",
              icon: Icons.email_outlined,
              enabled: !_isCodeSent, // Lock email after code is sent
            ),

            // STEP 2: Enter OTP and New Password (Shows only after code is sent)
            if (_isCodeSent) ...[
              const SizedBox(height: 20),
              _buildTextField(
                controller: otpController,
                label: "លេខកូដ ៦ ខ្ទង់",
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: passwordController,
                label: "លេខសម្ងាត់ថ្មី",
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
                onPressed: _isLoading ? null : (_isCodeSent ? _handleResetPassword : _handleSendCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF91A5D4),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.black)
                  : Text(_isCodeSent ? "ប្តូរលេខសម្ងាត់" : "ផ្ញើលេខកូដ", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false, bool enabled = true, TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}