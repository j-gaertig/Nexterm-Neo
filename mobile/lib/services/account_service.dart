import 'dart:convert';

import '../utils/api_client.dart';
import '../utils/api_exception.dart';

class AccountProfile {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final bool totpEnabled;
  final bool isAdmin;
  final Set<String> permissions;
  final String sessionSync;

  const AccountProfile({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
    this.totpEnabled = false,
    this.isAdmin = false,
    this.permissions = const {},
    this.sessionSync = 'across_devices',
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: (json['username'] ?? '').toString(),
    firstName: (json['firstName'] ?? '').toString(),
    lastName: (json['lastName'] ?? '').toString(),
    totpEnabled: json['totpEnabled'] == true,
    isAdmin: json['isAdmin'] == true,
    permissions: {
      for (final p in (json['permissions'] as List?) ?? const []) p.toString(),
    },
    sessionSync: (json['sessionSync'] ?? 'across_devices').toString(),
  );

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }

  bool can(String permission) => isAdmin || permissions.contains(permission);

  bool get hasAnyAdminAccess =>
      ['settings.monitoring', 'settings.engines', 'users.view'].any(can);
}

class ApiKeyInfo {
  final int id;
  final String name;
  final String prefix;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  /// Full secret, only present right after creation.
  final String? token;

  const ApiKeyInfo({
    required this.id,
    required this.name,
    required this.prefix,
    this.lastUsedAt,
    this.expiresAt,
    this.createdAt,
    this.token,
  });

  factory ApiKeyInfo.fromJson(Map<String, dynamic> json) => ApiKeyInfo(
    id: (json['id'] as num).toInt(),
    name: (json['name'] ?? '').toString(),
    prefix: (json['prefix'] ?? '').toString(),
    lastUsedAt: DateTime.tryParse((json['lastUsedAt'] ?? '').toString()),
    expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()),
    createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
    token: json['token'] as String?,
  );
}

class EngineInfoItem {
  final int id;
  final String name;
  final bool isLocal;
  final bool connected;
  final String? version;
  final String? remoteAddr;
  final bool encrypted;
  final DateTime? lastConnectedAt;

  const EngineInfoItem({
    required this.id,
    required this.name,
    required this.isLocal,
    required this.connected,
    this.version,
    this.remoteAddr,
    this.encrypted = false,
    this.lastConnectedAt,
  });

  factory EngineInfoItem.fromJson(Map<String, dynamic> json) => EngineInfoItem(
    id: (json['id'] as num).toInt(),
    name: (json['name'] ?? '').toString(),
    isLocal: json['isLocal'] == true,
    connected: json['connected'] == true,
    version: json['version'] as String?,
    remoteAddr: json['remoteAddr'] as String?,
    encrypted: json['encrypted'] == true,
    lastConnectedAt: DateTime.tryParse(
      (json['lastConnectedAt'] ?? '').toString(),
    ),
  );
}

class UserInfoItem {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final bool totpEnabled;
  final List<String> groups;

  const UserInfoItem({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
    this.totpEnabled = false,
    this.groups = const [],
  });

  factory UserInfoItem.fromJson(Map<String, dynamic> json) {
    final groups = <String>[];
    for (final key in const ['groups', 'roles']) {
      final raw = json[key];
      if (raw is List) {
        for (final g in raw) {
          if (g is Map && g['name'] != null) {
            groups.add(g['name'].toString());
          } else if (g is String) {
            groups.add(g);
          }
        }
      }
    }
    return UserInfoItem(
      id: (json['id'] as num).toInt(),
      username: (json['username'] ?? '').toString(),
      firstName: (json['firstName'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      totpEnabled: json['totpEnabled'] == true,
      groups: groups,
    );
  }

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }
}

class MonitoringSettings {
  final bool statusCheckerEnabled;
  final int statusInterval;
  final bool monitoringEnabled;
  final int monitoringInterval;
  final int dataRetentionHours;
  final int connectionTimeout;
  final int batchSize;

  const MonitoringSettings({
    this.statusCheckerEnabled = true,
    this.statusInterval = 30,
    this.monitoringEnabled = true,
    this.monitoringInterval = 60,
    this.dataRetentionHours = 24,
    this.connectionTimeout = 30,
    this.batchSize = 10,
  });

  factory MonitoringSettings.fromJson(Map<String, dynamic> json) =>
      MonitoringSettings(
        statusCheckerEnabled: json['statusCheckerEnabled'] != false,
        statusInterval: (json['statusInterval'] as num?)?.toInt() ?? 30,
        monitoringEnabled: json['monitoringEnabled'] != false,
        monitoringInterval: (json['monitoringInterval'] as num?)?.toInt() ?? 60,
        dataRetentionHours: (json['dataRetentionHours'] as num?)?.toInt() ?? 24,
        connectionTimeout: (json['connectionTimeout'] as num?)?.toInt() ?? 30,
        batchSize: (json['batchSize'] as num?)?.toInt() ?? 10,
      );

  Map<String, dynamic> toJson() => {
    'statusCheckerEnabled': statusCheckerEnabled,
    'statusInterval': statusInterval,
    'monitoringEnabled': monitoringEnabled,
    'monitoringInterval': monitoringInterval,
    'dataRetentionHours': dataRetentionHours,
    'connectionTimeout': connectionTimeout,
    'batchSize': batchSize,
  };

  MonitoringSettings copyWith({
    bool? statusCheckerEnabled,
    int? statusInterval,
    bool? monitoringEnabled,
    int? monitoringInterval,
    int? dataRetentionHours,
    int? connectionTimeout,
    int? batchSize,
  }) => MonitoringSettings(
    statusCheckerEnabled: statusCheckerEnabled ?? this.statusCheckerEnabled,
    statusInterval: statusInterval ?? this.statusInterval,
    monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
    monitoringInterval: monitoringInterval ?? this.monitoringInterval,
    dataRetentionHours: dataRetentionHours ?? this.dataRetentionHours,
    connectionTimeout: connectionTimeout ?? this.connectionTimeout,
    batchSize: batchSize ?? this.batchSize,
  );
}

/// Account, API key, identity and administration endpoints used by the
/// settings pages (mirrors the web `Settings` area).
class AccountService {
  static dynamic _decode(dynamic response, String fallback) {
    if (response.statusCode >= 300) {
      throw ApiException.fromResponse(response, fallback: fallback);
    }
    if (response.body.isEmpty) return null;
    dynamic data;
    try {
      data = json.decode(response.body);
    } catch (_) {
      return null;
    }
    if (data is Map && data['code'] is int && (data['code'] as int) >= 300) {
      throw ApiException(
        (data['message'] ?? fallback).toString(),
        statusCode: data['code'] as int,
      );
    }
    return data;
  }

  // --- Profile ---------------------------------------------------------------

  static Future<AccountProfile> getMe(String token) async {
    final r = await ApiClient.get('/accounts/me', token: token);
    final data = _decode(r, 'Could not load your profile.');
    if (data is! Map<String, dynamic>) {
      throw ApiException('Could not load your profile.');
    }
    return AccountProfile.fromJson(data);
  }

  static Future<void> updateName({
    required String token,
    required String firstName,
    required String lastName,
  }) async {
    final r = await ApiClient.patch(
      '/accounts/name',
      body: {'firstName': firstName, 'lastName': lastName},
      token: token,
    );
    _decode(r, 'Could not update your name.');
  }

  static Future<void> changePassword({
    required String token,
    required String password,
  }) async {
    final r = await ApiClient.patch(
      '/accounts/password',
      body: {'password': password},
      token: token,
    );
    _decode(r, 'Could not change your password.');
  }

  static Future<void> setSessionSync(String token, String mode) async {
    final r = await ApiClient.patch(
      '/accounts/session-sync',
      body: {'sessionSync': mode},
      token: token,
    );
    _decode(r, 'Could not update session synchronization.');
  }

  // --- Two-factor ------------------------------------------------------------

  static Future<({String secret, String url})> getTotpSecret(
    String token,
  ) async {
    final r = await ApiClient.get('/accounts/totp/secret', token: token);
    final data = _decode(r, 'Could not load the 2FA secret.');
    return (
      secret: (data?['secret'] ?? '').toString(),
      url: (data?['url'] ?? '').toString(),
    );
  }

  static Future<void> enableTotp(String token, int code) async {
    final r = await ApiClient.post(
      '/accounts/totp/enable',
      body: {'code': code},
      token: token,
    );
    _decode(r, 'The code is invalid or has expired.');
  }

  static Future<void> disableTotp(String token) async {
    final r = await ApiClient.post('/accounts/totp/disable', token: token);
    _decode(r, 'Could not disable two-factor authentication.');
  }

  // --- API keys --------------------------------------------------------------

  static Future<List<ApiKeyInfo>> listApiKeys(String token) async {
    final r = await ApiClient.get('/accounts/api-keys', token: token);
    final data = _decode(r, 'Could not load API keys.');
    if (data is! List) return const [];
    return [
      for (final k in data)
        if (k is Map<String, dynamic>) ApiKeyInfo.fromJson(k),
    ];
  }

  static Future<ApiKeyInfo> createApiKey({
    required String token,
    required String name,
    DateTime? expiresAt,
  }) async {
    final r = await ApiClient.post(
      '/accounts/api-keys',
      body: {
        'name': name,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
      token: token,
    );
    final data = _decode(r, 'Could not create the API key.');
    return ApiKeyInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  static Future<void> deleteApiKey(String token, int id) async {
    final r = await ApiClient.delete('/accounts/api-keys/$id', token: token);
    _decode(r, 'Could not delete the API key.');
  }

  // --- Identities ------------------------------------------------------------

  static Future<void> deleteIdentity(String token, dynamic id) async {
    final r = await ApiClient.delete('/identities/$id', token: token);
    _decode(r, 'Could not delete the identity.');
  }

  // --- Administration --------------------------------------------------------

  static Future<String?> getServerVersion() async {
    try {
      final r = await ApiClient.get('/service/version');
      final data = _decode(r, 'Could not read the server version.');
      return data?['version']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<MonitoringSettings> getMonitoringSettings(String token) async {
    final r = await ApiClient.get('/monitoring/settings/global', token: token);
    final data = _decode(r, 'Could not load monitoring settings.');
    return MonitoringSettings.fromJson(Map<String, dynamic>.from(data as Map));
  }

  static Future<void> saveMonitoringSettings(
    String token,
    MonitoringSettings settings,
  ) async {
    final r = await ApiClient.patch(
      '/monitoring/settings/global',
      body: settings.toJson(),
      token: token,
    );
    _decode(r, 'Could not save monitoring settings.');
  }

  static Future<List<EngineInfoItem>> listEngines(String token) async {
    final r = await ApiClient.get('/engines', token: token);
    final data = _decode(r, 'Could not load engines.');
    if (data is! List) return const [];
    return [
      for (final e in data)
        if (e is Map<String, dynamic>) EngineInfoItem.fromJson(e),
    ];
  }

  static Future<({List<UserInfoItem> users, int total})> listUsers(
    String token, {
    String search = '',
  }) async {
    final r = await ApiClient.get(
      '/users/list?limit=100${search.isEmpty ? '' : '&search=${Uri.encodeQueryComponent(search)}'}',
      token: token,
    );
    final data = _decode(r, 'Could not load users.');
    final list = (data?['users'] as List?) ?? const [];
    return (
      users: [
        for (final u in list)
          if (u is Map<String, dynamic>) UserInfoItem.fromJson(u),
      ],
      total: (data?['total'] as num?)?.toInt() ?? list.length,
    );
  }
}
