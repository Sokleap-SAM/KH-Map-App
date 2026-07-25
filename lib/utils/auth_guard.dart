import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import 'constants/colors.dart';
import 'theme/app_palette.dart';

/// Ensures the user is signed in before a gated action (creating a place,
/// rating, etc.) runs. Guests otherwise fill in a form whose request never
/// reaches the backend, so it *looks* like they contributed when they didn't.
///
/// Returns `true` when the user is already logged in, or logs in / registers
/// successfully after being prompted. Returns `false` if they dismiss the
/// prompt or leave the login screen without authenticating.
Future<bool> ensureLoggedIn(
  BuildContext context, {
  String message =
      'អ្នកត្រូវចូលគណនីជាមុនសិន ដើម្បីរួមចំណែក។', // "Please sign in first to contribute."
}) async {
  if (AuthService.isLoggedIn) return true;

  final p = context.palette;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'ត្រូវការគណនី',
        style: GoogleFonts.notoSansKhmer(
          color: p.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        message,
        style: GoogleFonts.notoSansKhmer(color: p.textSecondary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'បោះបង់',
            style: GoogleFonts.notoSansKhmer(color: p.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'ចូលគណនី',
            style: GoogleFonts.notoSansKhmer(
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  if (proceed != true || !context.mounted) return false;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
  );

  // LoginScreen pops with `true` on success, but a user can also swipe back;
  // rely on the token state, which is the single source of truth.
  return AuthService.isLoggedIn;
}
