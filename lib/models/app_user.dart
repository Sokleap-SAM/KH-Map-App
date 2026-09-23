/// Roles the backend's `UserRole` enum accepts. `user` is the default a
/// self-registered account gets; `driver` and `admin` are only assignable by an
/// admin (see AdminCreateUserDto / AdminUpdateUserDto).
class UserRoles {
  static const String user = 'user';
  static const String driver = 'driver';
  static const String admin = 'admin';

  static const List<String> all = [user, driver, admin];

  const UserRoles._();
}

/// Driver shift state (`UserStatus`). Only meaningful for drivers — riders and
/// admins carry it as dead weight.
///
/// These mirror the literals `PATCH /drivers/me/status` already accepts
/// elsewhere in the app ([DriverService.setShiftStatus]). If the backend enum
/// uses different strings, this is the single place to change: unknown values
/// coming back from the API are preserved and displayed rather than dropped, so
/// a mismatch shows up in the UI instead of silently rewriting someone's state.
class UserStatuses {
  static const String on = 'on';
  static const String off = 'off';

  static const List<String> all = [on, off];

  const UserStatuses._();
}

/// A user account as returned by the admin endpoints (`GET /users`,
/// `GET /users/:id`) and by `GET /users/profile`.
class AppUser {
  final String id;
  final String name;
  final String email;

  /// One of [UserRoles]; unrecognised values are kept verbatim.
  final String role;

  /// Driver shift state, or null for accounts that have never had one.
  final String? status;

  final bool isVerified;
  final DateTime? createdAt;

  /// Populated for drivers when the backend expands the relation.
  final String? assignedBusId;
  final String? assignedBusNumber;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.status,
    this.isVerified = false,
    this.createdAt,
    this.assignedBusId,
    this.assignedBusNumber,
  });

  bool get isDriver => role == UserRoles.driver;
  bool get isAdmin => role == UserRoles.admin;
  bool get hasAssignedBus =>
      assignedBusId != null && assignedBusId!.isNotEmpty;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    // `assignedBus` arrives either expanded or as a bare id, same as
    // DriverProfile handles it.
    final assignedRaw = json['assignedBus'] ?? json['assignedBusId'];
    String? assignedBusId;
    String? assignedBusNumber;
    if (assignedRaw is Map) {
      assignedBusId = assignedRaw['_id'] as String?;
      assignedBusNumber = assignedRaw['busNumber'] as String?;
    } else if (assignedRaw is String && assignedRaw.isNotEmpty) {
      assignedBusId = assignedRaw;
    }

    final rawStatus = json['status'] as String?;
    final rawCreated = json['createdAt'] as String?;

    return AppUser(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? UserRoles.user,
      status: (rawStatus == null || rawStatus.isEmpty) ? null : rawStatus,
      isVerified: (json['isVerified'] as bool?) ?? false,
      createdAt: rawCreated == null ? null : DateTime.tryParse(rawCreated),
      assignedBusId: assignedBusId,
      assignedBusNumber: assignedBusNumber,
    );
  }
}

/// One page of `GET /users?page=&limit=&role=&status=&search=`.
class UserPage {
  final List<AppUser> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const UserPage({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  static const UserPage empty = UserPage(
    data: [],
    total: 0,
    page: 1,
    limit: 20,
    totalPages: 1,
  );

  bool get hasPrevious => page > 1;
  bool get hasNext => page < totalPages;

  factory UserPage.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    final users = raw is List
        ? raw.whereType<Map<String, dynamic>>().map(AppUser.fromJson).toList()
        : <AppUser>[];
    final limit = (json['limit'] as num?)?.toInt() ?? 20;
    final total = (json['total'] as num?)?.toInt() ?? users.length;
    return UserPage(
      data: users,
      total: total,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: limit,
      // Derive rather than trust: a backend that omits totalPages would
      // otherwise pin the pager to a single page.
      totalPages: (json['totalPages'] as num?)?.toInt() ??
          (limit <= 0 ? 1 : (total / limit).ceil().clamp(1, 1 << 30)),
    );
  }
}
