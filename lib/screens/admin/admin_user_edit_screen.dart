import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';

/// Create or edit a user account.
///
/// Create posts to `/users/admin`, which provisions the account already
/// verified — that's the whole point of the endpoint, since a driver otherwise
/// can't be onboarded without waiting on an OTP email.
///
/// Edit patches `/users/:id`, sending only the fields that actually changed, so
/// an untouched password stays untouched rather than being overwritten with a
/// blank.
class AdminUserEditScreen extends StatefulWidget {
  final AppUser? existing;
  const AdminUserEditScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<AdminUserEditScreen> createState() => _AdminUserEditScreenState();
}

class _AdminUserEditScreenState extends State<AdminUserEditScreen> {
  final AdminService _service = AdminService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  late String _role;
  String? _status;
  late bool _isVerified;

  bool _obscurePassword = true;
  bool _saving = false;
  String? _error;

  /// Status values offered in the picker: the ones we know about, plus whatever
  /// this account already carries. Without the union, opening a user whose
  /// status came from a value this build doesn't know would silently rewrite it
  /// on save.
  List<String> get _statusOptions {
    final current = widget.existing?.status;
    if (current == null || UserStatuses.all.contains(current)) {
      return UserStatuses.all;
    }
    return [...UserStatuses.all, current];
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl.text = e?.name ?? '';
    _emailCtrl.text = e?.email ?? '';
    _role = e?.role ?? UserRoles.user;
    _status = e?.status;
    // A new account created by an admin is verified by definition.
    _isVerified = e?.isVerified ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value, AppTexts t) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return t.emailRequired;
    // Mirrors what class-validator's @IsEmail accepts closely enough to catch
    // typos client-side; the backend remains the authority.
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
    return ok ? null : t.emailInvalid;
  }

  String? _validatePassword(String? value, AppTexts t) {
    final v = value ?? '';
    // Optional on edit ("leave blank to keep"), required on create.
    if (v.isEmpty) return widget.isEdit ? null : t.passwordRequired;
    return v.length >= 8 ? null : t.passwordTooShort;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget.isEdit) {
        final e = widget.existing!;
        final name = _nameCtrl.text.trim();
        final email = _emailCtrl.text.trim();
        final password = _passwordCtrl.text;

        // Send only what changed — PATCH semantics, and it keeps the backend
        // from re-running setRole (and its bus-unassign side effect) on a save
        // that didn't touch the role.
        await _service.updateUser(
          e.id,
          name: name == e.name ? null : name,
          email: email == e.email ? null : email,
          password: password.isEmpty ? null : password,
          role: _role == e.role ? null : _role,
          status: _status == e.status ? null : _status,
          isVerified: _isVerified == e.isVerified ? null : _isVerified,
        );
      } else {
        await _service.createUser(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          role: _role,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _saving = false;
      });
    }
  }

  String _roleLabel(AppTexts t, String role) => switch (role) {
        UserRoles.driver => t.roleDriver,
        UserRoles.admin => t.roleAdmin,
        UserRoles.user => t.roleUser,
        _ => role,
      };

  String _statusLabel(AppTexts t, String status) => switch (status) {
        UserStatuses.on => t.statusOn,
        UserStatuses.off => t.statusOff,
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(widget.isEdit ? t.editUser : t.createUser),
      ),
      body: Form(
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
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? t.nameRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: t.emailField,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              validator: (v) => _validateEmail(v, t),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordCtrl,
              decoration: InputDecoration(
                labelText: t.passwordField,
                helperText: widget.isEdit ? t.passwordOptionalHint : null,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              validator: (v) => _validatePassword(v, t),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: InputDecoration(
                labelText: t.roleField,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final role in UserRoles.all)
                  DropdownMenuItem(
                    value: role,
                    child: Text(_roleLabel(t, role)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _role = v ?? UserRoles.user),
            ),
            // Shift state is driver-only — showing it for a rider or admin
            // would offer a field the backend ignores.
            if (_role == UserRoles.driver) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _status,
                decoration: InputDecoration(
                  labelText: t.statusField,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('—')),
                  for (final s in _statusOptions)
                    DropdownMenuItem<String?>(
                      value: s,
                      child: Text(_statusLabel(t, s)),
                    ),
                ],
                onChanged: _saving ? null : (v) => setState(() => _status = v),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.verifiedField),
              subtitle: _isVerified ? null : Text(t.unverified),
              value: _isVerified,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _isVerified = v),
            ),
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
              label: Text(widget.isEdit ? t.save : t.create),
            ),
          ],
        ),
      ),
    );
  }
}
