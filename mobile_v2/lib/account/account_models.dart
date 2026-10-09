/// The authenticated account (`GET /api/accounts/me`).
class UserInfo {
  const UserInfo({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    this.isAdmin = false,
    this.avatarHash,
    this.totpEnabled = false,
  });

  final int id;
  final String username;
  final String? firstName;
  final String? lastName;
  final bool isAdmin;
  final String? avatarHash;

  /// Two-factor enabled (`GET /api/accounts/me`).
  final bool totpEnabled;

  String get displayName {
    final parts = [
      if ((firstName ?? '').isNotEmpty) firstName!,
      if ((lastName ?? '').isNotEmpty) lastName!,
    ];
    if (parts.isEmpty) return username;
    return parts.join(' ');
  }

  /// Avatar image URL (query-token auth, see `API.md` §4).
  String avatarUrl(String apiBaseUrl, String token) {
    final v = avatarHash ?? '';
    return '$apiBaseUrl/accounts/$id/avatar?v=$v&token=$token';
  }

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return UserInfo(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0,
      username: json['username'] as String? ?? '',
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      isAdmin: json['isAdmin'] == true,
      avatarHash: json['avatarHash'] as String?,
      totpEnabled: json['totpEnabled'] == true,
    );
  }
}

/// An active login session (`GET /api/sessions/list`).
class LoginSession {
  const LoginSession({
    required this.id,
    this.ip,
    this.userAgent,
    this.lastActivity,
  });

  final String id;
  final String? ip;
  final String? userAgent;
  final DateTime? lastActivity;

  factory LoginSession.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return LoginSession(
      id: '$rawId',
      ip: json['ip'] as String?,
      userAgent: json['userAgent'] as String?,
      lastActivity:
          DateTime.tryParse('${json['lastActivity'] ?? ''}'),
    );
  }
}
