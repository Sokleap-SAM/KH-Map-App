import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/settings_provider.dart';
import '../services/profile_service.dart';
import '../utils/constants/colors.dart';
import '../utils/constants/text_strings.dart';
import '../utils/theme/app_palette.dart';

/// Self-service profile edit (`PATCH /users/me`) — name and password only.
///
/// Role, status and email are deliberately absent: the first two are privilege,
/// and letting someone rewrite their own email would hand them another
/// account's password-reset flow. The email is shown read-only so the field
/// isn't simply missing without explanation.
///
/// Pops `true` when something was actually saved.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final ProfileService _service = ProfileService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _currentPasswordCtrl = TextEditingController();
  final TextEditingController _newPasswordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();

  AppUser? _user;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// The password fields stay collapsed until asked for — most visits here are
  /// a name change, and three empty password boxes read as required work.
  bool _changingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  /// Set when the backend rejects the current password, so the message lands on
  /// that field instead of in a banner at the top.
  String? _currentPasswordError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = await _service.fetchProfile();
      if (!mounted) return;
      setState(() {
        _user = user;
        _nameCtrl.text = user.name;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ProfileApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  bool get _nameChanged =>
      _user != null && _nameCtrl.text.trim() != _user!.name;

  Future<void> _save() async {
    final t = context.read<SettingsProvider>().t;
    setState(() => _currentPasswordError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final wantsPasswordChange =
        _changingPassword && _newPasswordCtrl.text.isNotEmpty;

    // Nothing to send — say so rather than firing an empty PATCH that reports
    // success without having done anything.
    if (!_nameChanged && !wantsPasswordChange) {
      _snack(t.nothingToSave);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await _service.updateProfile(
        name: _nameChanged ? _nameCtrl.text.trim() : null,
        currentPassword:
            wantsPasswordChange ? _currentPasswordCtrl.text : null,
        newPassword: wantsPasswordChange ? _newPasswordCtrl.text : null,
      );
      if (!mounted) return;
      _user = updated;
      _snack(t.profileUpdated);
      Navigator.of(context).pop(true);
    } on ProfileApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // 401 here means the current password was wrong — not that the session
        // expired, so don't treat it as a logout.
        if (e.isWrongPassword) {
          _currentPasswordError = t.currentPasswordWrong;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.editProfile),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
              ? _buildLoadError(t)
              : _buildForm(t, p),
    );
  }

  Widget _buildLoadError(AppTexts t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.failedWith(_error ?? ''),
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: Text(t.tryAgain)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppTexts t, AppPalette p) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                t.failedWith(_error!),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          TextFormField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: t.nameField,
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? t.nameRequired : null,
            onChanged: (_) => setState(() {}), // enables/disables Save
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _user!.email,
            readOnly: true,
            enabled: false,
            decoration: InputDecoration(
              labelText: t.emailField,
              helperText: t.emailNotEditable,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.lock_outline, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.changePassword),
            value: _changingPassword,
            onChanged: _saving
                ? null
                : (v) => setState(() {
                      _changingPassword = v;
                      if (!v) {
                        // Drop anything typed so a collapsed section can't
                        // silently submit a password change.
                        _currentPasswordCtrl.clear();
                        _newPasswordCtrl.clear();
                        _confirmPasswordCtrl.clear();
                        _currentPasswordError = null;
                      }
                    }),
          ),
          if (_changingPassword) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _currentPasswordCtrl,
              decoration: InputDecoration(
                labelText: t.currentPassword,
                errorText: _currentPasswordError,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureCurrent ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
              obscureText: _obscureCurrent,
              autocorrect: false,
              enableSuggestions: false,
              validator: (v) => (v == null || v.isEmpty)
                  ? t.currentPasswordRequired
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newPasswordCtrl,
              decoration: InputDecoration(
                labelText: t.newPassword,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNew ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
              obscureText: _obscureNew,
              autocorrect: false,
              enableSuggestions: false,
              validator: (v) {
                if (v == null || v.isEmpty) return t.passwordRequired;
                return v.length >= 8 ? null : t.passwordTooShort;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordCtrl,
              decoration: InputDecoration(
                labelText: t.confirmNewPassword,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              validator: (v) =>
                  v == _newPasswordCtrl.text ? null : t.passwordsDoNotMatch,
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(t.save),
          ),
        ],
      ),
    );
  }
}
