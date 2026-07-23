import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kh_map_app/services/auth_service.dart';
import 'package:kh_map_app/utils/constants/colors.dart';

class VerificationScreen extends StatefulWidget {
  final String email;

  const VerificationScreen({super.key, required this.email});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  int _countdownSeconds = 60;
  Timer? _timer;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _countdownSeconds = 60;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds == 0) {
        setState(() {
          _canResend = true;
          _timer?.cancel();
        });
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  void _handleVerify() async {
    setState(() => _isLoading = true);
    // Call verifyOtp, which checks if the user has clicked the verification link.
    bool success = await _authService.verifyOtp(widget.email, "");
    setState(() => _isLoading = false);

    if (success) {
      _showMessage("គណនីរបស់អ្នកត្រូវបានផ្ទៀងផ្ទាត់រួចរាល់!");
      Navigator.pop(context, true); // Returns true to login screen to navigate
    } else {
      _showMessage("សូមចុចលើតំណភ្ជាប់ក្នុងអ៊ីមែលរបស់អ្នកជាមុនសិន ដើម្បីផ្ទៀងផ្ទាត់");
    }
  }

  void _handleResendCode() async {
    if (!_canResend) return;

    setState(() => _isLoading = true);
    bool success = await _authService.resendVerificationCode(widget.email);
    setState(() => _isLoading = false);

    if (success) {
      _showMessage("តំណភ្ជាប់ផ្ទៀងផ្ទាត់ថ្មីត្រូវបានផ្ញើ!");
      _startTimer();
    } else {
      _showMessage("បរាជ័យក្នុងការផ្ញើផ្ទៀងផ្ទាត់ឡើងវិញ");
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "ផ្ទៀងផ្ទាត់គណនី",
              style: TextStyle(
                color: Color(0xFFE8B67D),
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "តំណភ្ជាប់ផ្ទៀងផ្ទាត់ត្រូវបានផ្ញើទៅកាន់អ៊ីមែល:\n${widget.email}",
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 30),

            // Email illustration box
            Center(
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12, width: 2),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  size: 80,
                  color: Color(0xFFE8B67D),
                ),
              ),
            ),

            const SizedBox(height: 40),

            Text(
              "សូមពិនិត្យប្រអប់សំបុត្រអ៊ីមែលរបស់អ្នក ហើយចុចលើតំណភ្ជាប់ដើម្បីផ្ទៀងផ្ទាត់គណនី។ បន្ទាប់ពីចុចរួច សូមចុចប៊ូតុងខាងក្រោមដើម្បីបន្ត។",
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 40),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF91A5D4),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text(
                        "ខ្ញុំបានចុចផ្ទៀងផ្ទាត់រួចហើយ",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 30),

            // Resend code Section
            Center(
              child: Column(
                children: [
                  TextButton(
                    onPressed: _canResend ? _handleResendCode : null,
                    child: Text(
                      _canResend
                          ? "ផ្ញើតំណភ្ជាប់ឡើងវិញ (Resend Link)"
                          : "ផ្ញើតំណភ្ជាប់ឡើងវិញ ក្នុងរយៈពេល ($_countdownSeconds​ វិនាទី)",
                      style: TextStyle(
                        color: _canResend ? const Color(0xFFE8B67D) : Colors.white30,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
