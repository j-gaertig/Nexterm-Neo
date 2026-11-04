part of '../server_editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ServerEditorIdentities on _ServerEditorScreenState {
  List<ManagedIdentity> _linkedOrg() {
    return _linkedIds
        .map(
          (id) => _allIdentities.where((e) => e.id.toString() == id.toString()),
        )
        .where((it) => it.isNotEmpty)
        .map((it) => it.first)
        .where((e) => e.isOrg)
        .toList();
  }

  List<ManagedIdentity> _linkedPersonal() {
    return _linkedIds
        .map(
          (id) => _allIdentities.where((e) => e.id.toString() == id.toString()),
        )
        .where((it) => it.isNotEmpty)
        .map((it) => it.first)
        .where((e) => !e.isOrg)
        .toList();
  }

  List<ManagedIdentity> _availableFor(bool org) {
    final linked = _linkedIds.map((e) => e.toString()).toSet();
    return _allIdentities.where((e) {
      if (linked.contains(e.id.toString())) return false;
      if (org) {
        if (!e.isOrg) return false;
        if (_organizationId != null) {
          if (e.organizationId?.toString() != _organizationId.toString()) {
            return false;
          }
        }
      }
      if (!org && e.isOrg) return false;
      final t = e.authType;
      if (!_allowedAuth.contains(t)) return false;
      return true;
    }).toList();
  }

  Widget _identitiesTab() {
    final hasOrg = _organizationId != null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        32 + FloatingNavigationBarInset.of(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasOrg)
            _identitySection(
              title: 'Organization identities',
              isOrg: true,
              linked: _linkedOrg(),
              available: _availableFor(true),
            ),
          _identitySection(
            title: 'Personal identities',
            isOrg: false,
            linked: _linkedPersonal(),
            available: _availableFor(false),
          ),
          _newDraftsSection(),
        ],
      ),
    );
  }

  Widget _identitySection({
    required String title,
    required bool isOrg,
    required List<ManagedIdentity> linked,
    required List<ManagedIdentity> available,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: appBorderColor(cs)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addDraft(isOrg),
                icon: Icon(AppIcons.plus, size: 16),
                label: const Text('New'),
              ),
            ],
          ),
          if (linked.isEmpty && available.isEmpty)
            Text(
              'No identities yet',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          for (final m in linked) _linkedIdentityCard(m),
          if (available.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Available to link (${available.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.outline,
              ),
            ),
            const SizedBox(height: 6),
            for (final m in available)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() {
                    final id = m.id is int
                        ? m.id as int
                        : int.tryParse(m.id.toString());
                    if (id != null && !_linkedIds.contains(id)) {
                      _linkedIds.add(id);
                    }
                  }),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(AppIcons.linkVariant, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name.isEmpty ? 'Unnamed' : m.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                m.username.isEmpty ? 'No username' : m.username,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _authLabel(m.authType),
                          style: TextStyle(fontSize: 11, color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _newDraftsSection() {
    final news = _drafts.entries
        .where((e) => e.key.startsWith('new-'))
        .toList();
    if (news.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in news)
          _draftCard(
            e.key,
            e.value,
            isOrgScope: e.value.scope == 'organization',
          ),
      ],
    );
  }

  Future<void> _moveToOrg(ManagedIdentity m) async {
    if (_organizationId == null || m.isOrg) return;
    try {
      await ServerEditorService.moveIdentityToOrganization(
        token: widget.token,
        identityId: m.id,
        organizationId: _organizationId,
      );
      final identities = await ServerEditorService.getIdentities(widget.token);
      if (!mounted) return;
      setState(() => _allIdentities = identities);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Identity moved to organization'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyApiError(e, fallback: 'Move failed.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _linkedIdentityCard(ManagedIdentity m) {
    final cs = Theme.of(context).colorScheme;
    final draft = _drafts[m.id.toString()];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appBorderColor(cs)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.name.isEmpty ? 'Unnamed' : m.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _authLabel(m.authType),
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
              if (!m.isOrg && _organizationId != null)
                IconButton(
                  icon: Icon(AppIcons.brandDomain, size: 18, color: cs.primary),
                  onPressed: () => _moveToOrg(m),
                ),
              IconButton(
                icon: Icon(AppIcons.cancel, size: 18, color: cs.outline),
                onPressed: () => setState(() {
                  _linkedIds.removeWhere(
                    (id) => id.toString() == m.id.toString(),
                  );
                  _drafts.remove(m.id.toString());
                }),
              ),
            ],
          ),
          if (draft != null) _draftFields(m.id.toString(), draft),
          if (draft == null)
            TextButton(
              onPressed: () => setState(() {
                _drafts[m.id.toString()] = IdentityDraft.fromManaged(m);
              }),
              child: const Text('Edit credentials'),
            ),
        ],
      ),
    );
  }

  Widget _draftCard(
    String key,
    IdentityDraft draft, {
    required bool isOrgScope,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isNew = key.startsWith('new-');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNew
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNew ? cs.primary.withValues(alpha: 0.45) : cs.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isNew
                      ? 'New identity${isOrgScope ? ' (org)' : ''}'
                      : 'Edited identity',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isNew)
                IconButton(
                  icon: Icon(
                    AppIcons.trashCanOutline,
                    size: 18,
                    color: cs.outline,
                  ),
                  onPressed: () => setState(() => _drafts.remove(key)),
                ),
            ],
          ),
          _draftFields(key, draft),
        ],
      ),
    );
  }

  Widget _draftFields(String key, IdentityDraft draft) {
    final options = ServerEditorConstants.authTypeLabels
        .where((o) => _allowedAuth.contains(o['value']))
        .toList();
    final fallback = _allowedAuth.isNotEmpty ? _allowedAuth.first : 'password';
    final selected = options.any((o) => o['value'] == draft.authType)
        ? draft.authType
        : fallback;
    final showUser = selected != 'password-only';
    final showPassword =
        selected == 'password' ||
        selected == 'password-only' ||
        selected == 'both';
    final showKey = selected == 'ssh' || selected == 'both';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Identity name'),
        TextFormField(
          initialValue: draft.name,
          decoration: _dec('Identity name', AppIcons.accountCircleOutline),
          onChanged: (v) => draft.name = v,
        ),
        if (showUser) ...[
          _label('Username'),
          TextFormField(
            initialValue: draft.username,
            decoration: _dec('Username', AppIcons.accountCircleOutline),
            onChanged: (v) => draft.username = v,
          ),
        ],
        _label('Authentication'),
        DropdownButtonFormField<String>(
          key: ValueKey('${key}_$selected'),
          initialValue: selected,
          decoration: _dec(null, AppIcons.shieldAccountOutline),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o['value'], child: Text(o['label']!)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => draft.authType = v);
          },
        ),
        if (showPassword) ...[
          _label('Password'),
          TextFormField(
            initialValue: draft.password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: _dec('Password', AppIcons.lockOutline),
            onChanged: (v) {
              draft.password = v;
              draft.passwordTouched = true;
            },
          ),
        ],
        if (showKey) ...[
          _label('SSH private key'),
          _keyPicker(key, draft),
          _label('Passphrase (optional)'),
          TextFormField(
            initialValue: draft.passphrase,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: _dec('Passphrase', AppIcons.lockOutline),
            onChanged: (v) {
              draft.passphrase = v;
              draft.passphraseTouched = true;
            },
          ),
        ],
      ],
    );
  }

  Widget _keyPicker(String key, IdentityDraft draft) {
    final cs = Theme.of(context).colorScheme;
    String? name;
    if (draft.sshKey != null && draft.sshKey!.isNotEmpty) {
      name = draft.sshKey!.length > 40
          ? 'Key loaded (${draft.sshKey!.length} chars)'
          : 'Key loaded';
    }
    return Material(
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: appBorderSide(cs),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await FilePicker.platform.pickFiles(withData: true);
          if (result == null || result.files.isEmpty) return;
          final file = result.files.first;
          try {
            String content;
            if (file.bytes != null) {
              content = utf8.decode(file.bytes!, allowMalformed: true);
            } else if (file.path != null) {
              content = await File(file.path!).readAsString();
            } else {
              return;
            }
            setState(() => draft.sshKey = content);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    friendlyApiError(e, fallback: 'Failed to read key.'),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(AppIcons.fileUploadOutline, size: 20, color: cs.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name ?? 'Select key file',
                  style: TextStyle(
                    fontSize: 14,
                    color: name != null ? cs.onSurface : cs.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (name != null)
                Icon(AppIcons.checkCircle, size: 18, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  void _addDraft(bool forOrg) {
    if (forOrg && _organizationId == null) return;
    final id = 'new-${DateTime.now().millisecondsSinceEpoch}-${_drafts.length}';
    final orgId = forOrg ? _organizationId : null;
    setState(() {
      _drafts[id] = IdentityDraft(
        name: _name.text,
        authType: _allowedAuth.isNotEmpty ? _allowedAuth.first : 'password',
        scope: forOrg ? 'organization' : 'personal',
        organizationId: orgId,
      );
    });
  }

  String _authLabel(String value) {
    final hit = ServerEditorConstants.authTypeLabels.where(
      (o) => o['value'] == value,
    );
    if (hit.isEmpty) return value;
    return hit.first['label']!;
  }
}
