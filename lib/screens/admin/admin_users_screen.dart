import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import '../../utils/jwt.dart';
import 'admin_user_edit_screen.dart';

/// Users tab — CRUD over `/users`. Filtering, search and paging are all
/// server-side (`GET /users?page=&limit=&role=&status=&search=`) rather than
/// client-side like the Places screen: the user table is unbounded, so pulling
/// it all down to filter locally doesn't stay viable.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final AdminService _service = AdminService();
  final TextEditingController _searchCtrl = TextEditingController();

  UserPage _page = UserPage.empty;
  bool _loading = true;
  String? _error;

  String? _roleFilter;
  String? _statusFilter;
  String _search = '';
  int _currentPage = 1;

  /// Debounces keystrokes into one request — the search hits the backend, so
  /// firing per character would queue a request per letter typed.
  Timer? _searchDebounce;

  /// Our own id, from the JWT. Used to hide the delete action on our own row:
  /// the backend refuses self-deletion anyway, so offering it is a dead end.
  String? get _selfId => userIdFromToken(AuthService.tokenNotifier.value);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    final target = page ?? _currentPage;
    if (mounted) setState(() => _loading = true);
    try {
      final result = await _service.fetchUsers(
        page: target,
        role: _roleFilter,
        status: _statusFilter,
        search: _search,
      );
      if (!mounted) return;
      setState(() {
        _page = result;
        _currentPage = result.page;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      // A new query invalidates the current page — page 3 of the old result set
      // is meaningless against the new one.
      _search = value;
      _load(page: 1);
    });
  }

  void _setRoleFilter(String? role) {
    setState(() => _roleFilter = role);
    _load(page: 1);
  }

  void _setStatusFilter(String? status) {
    setState(() => _statusFilter = status);
    _load(page: 1);
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminUserEditScreen()),
    );
    if (saved == true && mounted) {
      _snack(context.read<SettingsProvider>().t.userCreated);
      _load(page: 1);
    }
  }

  Future<void> _edit(AppUser user) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminUserEditScreen(existing: user)),
    );
    if (saved == true && mounted) {
      _snack(context.read<SettingsProvider>().t.userUpdated);
      _load();
    }
  }

  /// Quick role change straight from the list, via the dedicated
  /// `PATCH /users/admin/users/:id/role`. Same server-side effect as editing the
  /// role in the full form — this just saves opening it to flip one field.
  Future<void> _changeRole(AppUser user) async {
    final t = context.read<SettingsProvider>().t;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t.changeRole),
        children: [
          for (final role in UserRoles.all)
            ListTile(
              leading: Icon(
                user.role == role
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: user.role == role ? AppColors.primaryColor : null,
              ),
              title: Text(_roleLabel(t, role)),
              onTap: () => Navigator.of(ctx).pop(role),
            ),
        ],
      ),
    );
    if (picked == null || picked == user.role) return;
    if (!mounted) return;

    // Demoting yourself is recoverable only by another admin, and the running
    // session won't notice until the JWT is reissued — so make it deliberate.
    if (user.id == _selfId && picked != UserRoles.admin) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.demoteSelfTitle),
          content: Text(t.demoteSelfWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                t.confirmWord,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await _service.setUserRole(user.id, picked);
      if (!mounted) return;
      _snack(t.roleUpdated);
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack(t.failedWith(e is AdminApiException ? e.message : e.toString()));
    }
  }

  Future<void> _delete(AppUser user) async {
    final t = context.read<SettingsProvider>().t;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteUserTitle),
        content: Text(t.deleteUserConfirm(user.name.isEmpty ? user.email : user.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              t.confirmWord,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _service.deleteUser(user.id);
      if (!mounted) return;
      _snack(t.userDeleted);
      // Deleting the only row on the last page would otherwise strand us on an
      // empty page.
      final onlyRowLeft = _page.data.length == 1 && _currentPage > 1;
      _load(page: onlyRowLeft ? _currentPage - 1 : _currentPage);
    } catch (e) {
      if (!mounted) return;
      // The backend owns the rules (last admin, driver mid-trip, self) — show
      // its message rather than guessing which one tripped.
      _snack(
        t.failedWith(e is AdminApiException ? e.message : e.toString()),
      );
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Color _roleColor(String role) => switch (role) {
        UserRoles.admin => Colors.deepPurple,
        UserRoles.driver => AppColors.secondaryColor,
        _ => Colors.blueGrey,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.manageUsers),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_users_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(t.newUser),
      ),
      body: Column(
        children: [
          _buildFilters(t),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.searchUsersHint,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (v) {
                _onSearchChanged(v);
                setState(() {}); // reflect the clear button
              },
            ),
          ),
          Expanded(child: _buildBody(t)),
          if (_page.totalPages > 1) _buildPager(t),
        ],
      ),
    );
  }

  Widget _buildFilters(AppTexts t) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _chip(t.all, _roleFilter == null, () => _setRoleFilter(null)),
          for (final role in UserRoles.all)
            _chip(
              _roleLabel(t, role),
              _roleFilter == role,
              () => _setRoleFilter(role),
            ),
          const VerticalDivider(width: 16),
          // Shift state only exists for drivers, so the status filter is only
          // meaningful alongside the driver role.
          for (final status in UserStatuses.all)
            _chip(
              _statusLabel(t, status),
              _statusFilter == status,
              () => _setStatusFilter(_statusFilter == status ? null : status),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _buildBody(AppTexts t) {
    if (_loading && _page.data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _page.data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _load(),
                child: Text(t.tryAgain),
              ),
            ],
          ),
        ),
      );
    }
    if (_page.data.isEmpty) {
      return Center(child: Text(t.noUsers));
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        itemCount: _page.data.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _buildTile(t, _page.data[i]),
      ),
    );
  }

  Widget _buildTile(AppTexts t, AppUser user) {
    final isSelf = user.id == _selfId;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _roleColor(user.role),
        child: Text(
          (user.name.isNotEmpty ? user.name : user.email)
              .characters
              .first
              .toUpperCase(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.name.isEmpty ? user.email : user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!user.isVerified) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: t.unverified,
              child: const Icon(
                Icons.error_outline,
                size: 15,
                color: Colors.orange,
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.email, style: const TextStyle(fontSize: 11)),
          Text(
            [
              _roleLabel(t, user.role),
              if (user.isDriver && user.status != null)
                _statusLabel(t, user.status!),
              if (user.assignedBusNumber != null)
                '🚌 ${user.assignedBusNumber}',
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: _roleColor(user.role)),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => _edit(user),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: t.edit,
            onPressed: () => _edit(user),
          ),
          // Role change and delete live behind the overflow: both are one-tap
          // destructive-ish on a list you scroll, and delete in particular is
          // too easy to hit by accident as a bare icon.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) {
              if (action == 'role') _changeRole(user);
              if (action == 'delete') _delete(user);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'role',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined, size: 20),
                  title: Text(t.changeRole),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                // The backend refuses self-deletion, so offering it is a dead
                // end — disable rather than let it fail.
                enabled: !isSelf,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete,
                    size: 20,
                    color: isSelf ? Colors.grey : Colors.red,
                  ),
                  title: Text(
                    isSelf ? t.cannotDeleteSelf : t.delete,
                    style: TextStyle(color: isSelf ? Colors.grey : Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPager(AppTexts t) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _page.hasPrevious && !_loading
                  ? () => _load(page: _currentPage - 1)
                  : null,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.pageOf(_page.page, _page.totalPages),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  t.usersFound(_page.total),
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _page.hasNext && !_loading
                  ? () => _load(page: _currentPage + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
