import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kh_map_app/providers/settings_provider.dart';
import 'package:kh_map_app/services/auth_service.dart';
import 'package:kh_map_app/utils/constants/colors.dart';
import 'package:provider/provider.dart';

/// Email-OTP verification, shown right after email/password [register] so the
/// user can prove they own the address by typing the code sent to their inbox.
/// Pops `true` once verified. Google 1-click sign-in never routes here.
class VerificationScreen extends StatefulWidget {
  final String email;

  const VerificationScreen({super.key, required this.email});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController otpController = TextEditingController();
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
    otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() {
      _countdownSeconds = 60;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _countdownSeconds = 0;
          _canResend = true;
        });
      } else {
        setState(() => _countdownSeconds--);
      }
    });
  }

  Future<void> _handleVerify() async {
    final t = context.read<SettingsProvider>().t;
    final code = otpController.text.trim();
    if (code.isEmpty) {
      _showMessage(t.pleaseEnterCode);
      return;
    }
    setState(() => _isLoading = true);
    final success = await _authService.verifyOtp(widget.email, code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _showMessage(t.accountVerified);
      Navigator.pop(context, true); // Verified — resume registration → login.
    } else {
      _showMessage(t.invalidCode);
    }
  }

  Future<void> _handleResendCode() async {
    if (!_canResend || _isLoading) return;
    final t = context.read<SettingsProvider>().t;
    setState(() => _isLoading = true);
    final success = await _authService.resendVerificationCode(widget.email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _showMessage(t.codeSent);
      _startTimer();
    } else {
      _showMessage(t.resendFailed);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.verifyAccountTitle,
              style: const TextStyle(
                color: Color(0xFFE8B67D),
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              t.verifyAccountSubtitle(widget.email),
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
                  color: Colors.white.withValues(alpha: 0.05),
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

            // OTP code input
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                letterSpacing: 6,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: t.codeField,
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withAlpha(13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _handleVerify(),
            ),

            const SizedBox(height: 30),

            // Confirm button
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
                    : Text(
                        t.confirmWord,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 30),

            // Resend code with countdown
            Center(
              child: TextButton(
                onPressed: (_canResend && !_isLoading) ? _handleResendCode : null,
                child: Text(
                  _canResend ? t.resendCode : t.resendCodeIn(_countdownSeconds),
                  style: TextStyle(
                    color: _canResend
                        ? const Color(0xFFE8B67D)
                        : Colors.white30,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
