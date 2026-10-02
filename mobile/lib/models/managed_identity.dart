class ManagedIdentity {
  final dynamic id;
  final String name;
  final String username;
  final String authType;
  final String scope;
  final dynamic organizationId;
  final dynamic accountId;

  const ManagedIdentity({
    this.id,
    this.name = '',
    this.username = '',
    this.authType = 'password',
    this.scope = 'personal',
    this.organizationId,
    this.accountId,
  });

  bool get isNew => id == null || id.toString().startsWith('new-');
  bool get isOrg => scope == 'organization';

  factory ManagedIdentity.fromJson(Map<String, dynamic> json) {
    final rawAuth = (json['authType'] ?? json['type'])?.toString();
    return ManagedIdentity(
      id: json['id'],
      name: (json['name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      authType: (rawAuth == null || rawAuth.isEmpty) ? 'password' : rawAuth,
      scope: (json['scope'] ?? (json['organizationId'] != null ? 'organization' : 'personal')).toString(),
      organizationId: json['organizationId'],
      accountId: json['accountId'],
    );
  }

}

class IdentityDraft {
  String name;
  String username;
  String authType;
  String password;
  String? sshKey;
  String passphrase;
  String scope;
  dynamic organizationId;
  bool passwordTouched;
  bool passphraseTouched;

  IdentityDraft({
    this.name = '',
    this.username = '',
    this.authType = 'password',
    this.password = '',
    this.sshKey,
    this.passphrase = '',
    this.scope = 'personal',
    this.organizationId,
    this.passwordTouched = false,
    this.passphraseTouched = false,
  });

  factory IdentityDraft.fromManaged(ManagedIdentity m) => IdentityDraft(
        name: m.name,
        username: m.username,
        authType: m.authType,
        scope: m.scope,
        organizationId: m.organizationId,
      );

  Map<String, dynamic> toPayload() {
    final payload = <String, dynamic>{
      'name': name,
      'type': authType,
    };
    if (authType != 'password-only' && username.isNotEmpty) {
      payload['username'] = username;
    }
    if (organizationId != null && organizationId.toString().isNotEmpty) {
      if (organizationId is int) {
        payload['organizationId'] = organizationId;
      } else {
        final parsed = int.tryParse(organizationId.toString());
        if (parsed == null) throw Exception('Invalid organization id');
        payload['organizationId'] = parsed;
      }
    }
    final hasPassphrase = passphrase.isNotEmpty;
    if (authType == 'password' || authType == 'password-only') {
      if (passwordTouched || password.isNotEmpty) payload['password'] = password;
    } else if (authType == 'both') {
      if (passwordTouched || password.isNotEmpty) payload['password'] = password;
      if (sshKey != null) payload['sshKey'] = sshKey;
      if (hasPassphrase) payload['passphrase'] = passphrase;
    } else {
      if (sshKey != null) payload['sshKey'] = sshKey;
      if (hasPassphrase) payload['passphrase'] = passphrase;
    }
    return payload;
  }
}
