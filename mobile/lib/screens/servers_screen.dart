import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/app_ui.dart';
import '../widgets/nav_scope.dart';
import '../utils/app_icons.dart';
import '../models/server.dart';
import '../models/server_folder.dart';
import '../services/script_manager.dart';
import '../services/server_service.dart';
import '../services/session_manager.dart';
import '../utils/api_exception.dart';
import '../utils/auth_manager.dart';
import '../utils/snippet_manager.dart';
import '../utils/folder_state_manager.dart';
import '../utils/muted_colors.dart';
import '../utils/server_view_settings.dart';
import '../utils/tag_color.dart';
import '../widgets/floating_navigation_bar.dart';
import 'widgets/quick_connect_sheet.dart';
import 'widgets/server_grid_card.dart';
import 'widgets/connection_reason_dialog.dart';
import 'widgets/instance_switcher.dart';
import 'widgets/identity_picker_sheet.dart';
import 'widgets/name_dialog.dart';
import 'widgets/server_actions_sheet.dart';
import 'widgets/server_notes_sheet.dart';
import 'widgets/server_tags_sheet.dart';
import '../services/server_actions_service.dart';
import 'widgets/server_protocol_sheet.dart';
import 'widgets/tag_filter_sheet.dart';
import 'widgets/script/run_script_sheet.dart';
import '../services/server_editor_service.dart';
import 'server_accounts_screen.dart';
import 'server_editor_screen.dart';

part 'servers/filter.dart';
part 'servers/ui.dart';
part 'servers/actions.dart';
part 'servers/menu.dart';

class ServersScreen extends StatefulWidget {
  final AuthManager authManager;
  final SnippetManager snippetManager;
  final SessionManager sessionManager;
  final ServerViewSettings serverViewSettings;

  /// Opens the session that was just created from this screen.
  final ValueChanged<String>? onSessionOpened;
  final Future<List<dynamic>> Function(String token)? loadEntries;

  const ServersScreen({
    super.key,
    required this.authManager,
    required this.snippetManager,
    required this.sessionManager,
    required this.serverViewSettings,
    this.onSessionOpened,
    this.loadEntries,
  });

  @override
  State<ServersScreen> createState() => ServersScreenState();
}

class ServersScreenState extends State<ServersScreen> {
  List<dynamic> folders = [];
  List<dynamic> filteredFolders = [];
  bool isLoading = true;
  String? errorMessage;
  FolderStateManager? _folderState;
  final Set<String> _expanded = {};
  final _search = TextEditingController();
  String _query = '';
  Timer? _debounce;
  bool _searchFocused = false;
  bool _hasText = false;
  final Set<int> _selectedTags = {};
  List<Tag> _allTags = [];
  late final ScriptManager _scriptManager;
  String? _activeAccountId;
  int _loadGeneration = 0;

  String _folderKey(ServerFolder folder) {
    final id = folder.id;
    if (id != null) return 'id:$id';
    return 'n:${folder.type}:${folder.name}:${folder.position}';
  }

  int get _totalServers =>
      folders.fold(0, (sum, item) => sum + _countServers(item));
  int _countServers(dynamic item) {
    if (item is Server) return 1;
    if (item is ServerFolder) {
      return item.allServers.length +
          item.allFolders.fold(0, (sum, sf) => sum + _countServers(sf));
    }
    return 0;
  }

  int get _onlineServers =>
      folders.fold(0, (sum, item) => sum + _countOnline(item));
  int _countOnline(dynamic item) {
    if (item is Server) return item.isRunning ? 1 : 0;
    if (item is ServerFolder) {
      return item.allServers.where((s) => s.isRunning).length +
          item.allFolders.fold(0, (sum, sf) => sum + _countOnline(sf));
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _hasText = _search.text.isNotEmpty;
    _search.addListener(_onSearch);
    _activeAccountId = widget.authManager.accountManager.activeAccount?.id;
    widget.authManager.addListener(_onAuthChanged);
    _scriptManager = ScriptManager();
    _initStateManager();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.authManager.removeListener(_onAuthChanged);
    _search.removeListener(_onSearch);
    _search.dispose();
    _scriptManager.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    final accountId = widget.authManager.accountManager.activeAccount?.id;
    if (accountId == _activeAccountId) return;
    _activeAccountId = accountId;
    _handleAccountSwitch();
  }

  void _handleAccountSwitch() {
    _debounce?.cancel();
    _search.clear();
    if (!mounted) return;
    setState(() {
      folders = [];
      filteredFolders = [];
      _allTags = [];
      _selectedTags.clear();
      _query = '';
      _hasText = false;
      errorMessage = null;
      isLoading = true;
    });
    _loadData();
  }

  void _onSearch() {
    final hasText = _search.text.isNotEmpty;
    if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _query = _search.text.trim();
          _filterFolders();
        });
      }
    });
  }

  void _clearSearch() {
    _search.clear();
    _debounce?.cancel();
    if (mounted) {
      setState(() {
        _query = '';
        _hasText = false;
        _filterFolders();
      });
    }
  }

  Future<void> _initStateManager() async {
    _folderState = await FolderStateManager.create();
    await _loadData();
  }

  Future<void> _loadData() async {
    final generation = ++_loadGeneration;
    try {
      final token = widget.authManager.sessionToken;
      if (token == null) {
        if (mounted) {
          setState(() {
            errorMessage = 'Not authenticated';
            isLoading = false;
          });
        }
        return;
      }
      final data =
          await (widget.loadEntries?.call(token) ??
              ServerService.getServerList(token));
      if (!mounted || generation != _loadGeneration) return;
      final tags = _collectTags(data);
      final validTagIds = tags.map((t) => t.id).toSet();
      _selectedTags.removeWhere((id) => !validTagIds.contains(id));
      setState(() {
        folders = data;
        _allTags = tags;
        isLoading = false;
        errorMessage = null;
        _expanded.clear();
        if (_folderState != null) _restoreStates(data);
        _filterFolders();
      });
      _pruneStaleFolderStates(data);
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          errorMessage = friendlyApiError(
            e,
            fallback: 'Failed to load servers.',
          );
          isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    final generation = ++_loadGeneration;
    try {
      final token = widget.authManager.sessionToken;
      if (token == null) return;
      final data =
          await (widget.loadEntries?.call(token) ??
              ServerService.getServerList(token));
      if (!mounted || generation != _loadGeneration) return;
      final tags = _collectTags(data);
      final validTagIds = tags.map((t) => t.id).toSet();
      _selectedTags.removeWhere((id) => !validTagIds.contains(id));
      setState(() {
        folders = data;
        _allTags = tags;
        errorMessage = null;
        _expanded.clear();
        if (_folderState != null) _restoreStates(data);
        _filterFolders();
      });
      _pruneStaleFolderStates(data);
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyApiError(e, fallback: 'Failed to refresh.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _restoreStates(List<dynamic> list) {
    for (final item in list) {
      if (item is ServerFolder) {
        if (_folderState != null &&
            item.id != null &&
            _folderState!.isFolderExpanded(item.id)) {
          _expanded.add(_folderKey(item));
        }
        if (item.allFolders.isNotEmpty) _restoreStates(item.allFolders);
      }
    }
  }

  void _pruneStaleFolderStates(List<dynamic> list) {
    final state = _folderState;
    if (state == null) return;
    final valid = <String>{};
    void collect(List<dynamic> items) {
      for (final item in items) {
        if (item is ServerFolder) {
          valid.add(_folderKey(item));
          collect(item.allFolders);
        }
      }
    }

    collect(list);
    _expanded.removeWhere((k) => !valid.contains(k));
    for (final id in state.getAllExpandedFolderIds()) {
      if (!valid.contains('id:$id')) {
        state.setFolderExpanded(id, false);
      }
    }
  }

  Future<void> _toggleFolder(ServerFolder folder) async {
    final key = _folderKey(folder);
    _expanded.contains(key) ? _expanded.remove(key) : _expanded.add(key);
    final shouldExpand = _expanded.contains(key);
    if (_folderState != null && folder.id != null) {
      await _folderState!.setFolderExpanded(folder.id, shouldExpand);
      if (!mounted) return;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(cs, tt),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.serverViewSettings,
                builder: (_, __) => isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : errorMessage != null
                    ? _buildError(cs, tt)
                    : filteredFolders.isEmpty
                    ? _buildEmpty(cs, tt)
                    : _buildList(cs),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasActiveFilter =>
      _query.trim().isNotEmpty || _selectedTags.isNotEmpty;

  static const double _gridSpacing = 8;
  static const double _minGridCardWidth = 104;

  /// Opens the script picker and starts a script session with the chosen
  /// script (mirrors the web `runScript` → `initiateConnection({scriptId})`).
  Future<void> _runScript(Server server) async {
    if (server.disabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${server.name} is disabled'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (server.isStopped) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${server.name} is ${server.isPve ? "not running" : "offline"}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    if (server.identities == null || server.identities!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${server.name} has no identity configured for script execution',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final organization = _organizationForServer(server);
    final selection = await showRunScriptSheet(
      context,
      server,
      token,
      manager: _scriptManager,
      organizationId: _organizationIdFromFolder(organization),
    );
    if (selection == null || !mounted) return;

    await _initiateConnection(server, script: selection);
  }

  /// Opens the protocol picker and the server editor. Used by the add action
  /// next to the floating navigation bar.
  ///
  /// [inFolder] pre-selects the target folder (used by the folder menu);
  /// otherwise the deepest expanded folder is used.
  Future<void> createServer({FolderOption? inFolder}) async {
    final token = widget.authManager.sessionToken;
    if (token == null) return;
    final protocol = await showServerProtocolSheet(context);
    if (protocol == null || !mounted) return;
    final contextFolder = inFolder ?? _expandedFolderContext();
    final changed = await pushPage(
      context,
      (_) => ServerEditorScreen(
        token: token,
        initialProtocol: protocol,
        folderOptions: _folderOptions(),
        initialFolderId: contextFolder?.id,
        initialOrganizationId: contextFolder?.organizationId,
      ),
    );
    if (changed == true) _refreshData();
  }
}
