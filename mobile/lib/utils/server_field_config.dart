class ServerFieldConfig {
  final bool showProtocol;
  final bool showIpPort;
  final bool showIdentities;
  final bool showSettings;
  final bool showMonitoring;
  final bool showKeyboardLayout;
  final bool showTerminalSettings;
  final bool showConnectionHooks;
  final bool showDisplaySettings;
  final bool showPerformanceSettings;
  final bool showAudioSettings;
  final bool showRdpSecurity;
  final bool showWakeOnLan;
  final List<String> allowedAuthTypes;

  const ServerFieldConfig({
    this.showProtocol = false,
    this.showIpPort = true,
    this.showIdentities = true,
    this.showSettings = true,
    this.showMonitoring = false,
    this.showKeyboardLayout = false,
    this.showTerminalSettings = false,
    this.showConnectionHooks = false,
    this.showDisplaySettings = false,
    this.showPerformanceSettings = false,
    this.showAudioSettings = false,
    this.showRdpSecurity = false,
    this.showWakeOnLan = true,
    this.allowedAuthTypes = const ['password', 'ssh', 'both'],
  });
}

ServerFieldConfig getServerFieldConfig(String type, String? protocol) {
  if (type == 'pve-shell' || type == 'pve-lxc' || type == 'pve-qemu') {
    if (type == 'pve-qemu') {
      return const ServerFieldConfig(
        showIpPort: false,
        showIdentities: false,
        showSettings: true,
        showDisplaySettings: true,
        showAudioSettings: true,
        showWakeOnLan: false,
      );
    }
    return const ServerFieldConfig(
      showIpPort: false,
      showIdentities: false,
      showSettings: false,
      showWakeOnLan: false,
    );
  }
  if (type != 'server') {
    return const ServerFieldConfig(
      showProtocol: true,
      showMonitoring: true,
      showWakeOnLan: false,
    );
  }
  switch (protocol) {
    case 'ssh':
      return const ServerFieldConfig(
        showMonitoring: true,
        showTerminalSettings: true,
        showConnectionHooks: true,
        allowedAuthTypes: ['password', 'ssh', 'both'],
      );
    case 'telnet':
      return const ServerFieldConfig(
        showIdentities: false,
        showTerminalSettings: true,
      );
    case 'rdp':
      return const ServerFieldConfig(
        showKeyboardLayout: true,
        showDisplaySettings: true,
        showPerformanceSettings: true,
        showAudioSettings: true,
        showRdpSecurity: true,
        allowedAuthTypes: ['password-only', 'password'],
      );
    case 'vnc':
      return const ServerFieldConfig(
        showDisplaySettings: true,
        showAudioSettings: true,
        allowedAuthTypes: ['password-only', 'password'],
      );
    case 'sftp':
      return const ServerFieldConfig(
        allowedAuthTypes: ['password', 'ssh', 'both'],
      );
    case 'ftp':
    case 'ftps':
      return const ServerFieldConfig(
        allowedAuthTypes: ['password'],
      );
    case 'demo':
      return const ServerFieldConfig(
        showIpPort: false,
        showIdentities: false,
        showSettings: false,
        showMonitoring: false,
        showWakeOnLan: false,
      );
    default:
      return const ServerFieldConfig(
        showProtocol: true,
        showMonitoring: true,
        showKeyboardLayout: true,
      );
  }
}

List<String> getServerTabs(String type, String? protocol) {
  final config = getServerFieldConfig(type, protocol);
  final tabs = <String>['details'];
  if (config.showIdentities) tabs.add('identities');
  final hasSettings = config.showMonitoring ||
      config.showKeyboardLayout ||
      config.showDisplaySettings ||
      config.showAudioSettings ||
      config.showWakeOnLan ||
      config.showTerminalSettings ||
      config.showConnectionHooks ||
      config.showRdpSecurity ||
      config.showPerformanceSettings;
  if (config.showSettings && hasSettings) tabs.add('settings');
  return tabs;
}

bool validateServerFields(String type, String? protocol, String name, Map<String, dynamic> config) {
  final fieldConfig = getServerFieldConfig(type, protocol);
  if (name.trim().isEmpty) return false;
  if (fieldConfig.showIpPort) {
    final ip = (config['ip'] ?? '').toString().trim();
    final port = (config['port'] ?? '').toString().trim();
    if (ip.isEmpty || port.isEmpty) return false;
  }
  if (fieldConfig.showProtocol) {
    final p = (config['protocol'] ?? '').toString();
    if (p.isEmpty) return false;
  }
  return true;
}

class ServerEditorConstants {
  static const List<Map<String, String>> protocols = [
    {'label': 'SSH', 'value': 'ssh'},
    {'label': 'Telnet', 'value': 'telnet'},
    {'label': 'RDP', 'value': 'rdp'},
    {'label': 'VNC', 'value': 'vnc'},
    {'label': 'SFTP', 'value': 'sftp'},
    {'label': 'FTP', 'value': 'ftp'},
    {'label': 'FTPS', 'value': 'ftps'},
  ];

  static const Map<String, String> defaultPorts = {
    'ssh': '22',
    'telnet': '23',
    'rdp': '3389',
    'vnc': '5900',
    'sftp': '22',
    'ftp': '21',
    'ftps': '21',
  };

  static const Map<String, String> protocolIcons = {
    'ssh': 'mdiConsole',
    'telnet': 'mdiConsole',
    'rdp': 'mdiMicrosoftWindows',
    'vnc': 'mdiMonitor',
    'sftp': 'mdiFolderNetwork',
    'ftp': 'mdiFolderNetwork',
    'ftps': 'mdiFolderNetwork',
    'demo': 'mdiFlaskOutline',
  };

  static const List<Map<String, String>> authTypeLabels = [
    {'label': 'No Username', 'value': 'password-only'},
    {'label': 'Password', 'value': 'password'},
    {'label': 'SSH Key', 'value': 'ssh'},
    {'label': 'Key+Pass', 'value': 'both'},
  ];

  static const List<Map<String, String>> colorDepths = [
    {'label': 'Auto', 'value': ''},
    {'label': '256 colors (8-bit)', 'value': '8'},
    {'label': 'Low color (16-bit)', 'value': '16'},
    {'label': 'True color (24-bit)', 'value': '24'},
    {'label': 'True color (32-bit)', 'value': '32'},
  ];

  static const List<Map<String, String>> resizeMethods = [
    {'label': 'Display Update (recommended)', 'value': 'display-update'},
    {'label': 'Reconnect', 'value': 'reconnect'},
    {'label': 'None', 'value': 'none'},
  ];

  static const List<Map<String, String>> backspaceModes = [
    {'label': 'DEL', 'value': 'del'},
    {'label': '^H', 'value': 'ctrl-h'},
  ];

  static const List<Map<String, String>> deleteModes = [
    {'label': 'VT', 'value': 'vt'},
    {'label': 'DEL', 'value': 'del'},
  ];

  static const List<Map<String, String>> functionKeyModes = [
    {'label': 'Xterm', 'value': 'xterm'},
    {'label': 'VT', 'value': 'vt'},
    {'label': 'Linux', 'value': 'linux'},
  ];

  static const List<Map<String, String>> rdpSecurityMethods = [
    {'label': 'Auto (negotiate best)', 'value': ''},
    {'label': 'Any (highest available)', 'value': 'any'},
    {'label': 'NLA (Kerberos / CredSSP)', 'value': 'nla'},
    {'label': 'TLS (SSL)', 'value': 'tls'},
    {'label': 'RDP (NTLM)', 'value': 'rdp'},
    {'label': 'Hyper-V (vmconnect)', 'value': 'vmconnect'},
  ];

  static const List<Map<String, String>> keyboardLayouts = [
    {'label': 'Čeština (Qwertz)', 'value': 'cs-cz-qwertz'},
    {'label': 'Dänish (Qwerty)', 'value': 'da-dk-qwerty'},
    {'label': 'Swiss German (Qwertz)', 'value': 'de-ch-qwertz'},
    {'label': 'Deutsch (Qwertz)', 'value': 'de-de-qwertz'},
    {'label': 'English (GB) (Qwerty)', 'value': 'en-gb-qwerty'},
    {'label': 'English (US) (Qwerty)', 'value': 'en-us-qwerty'},
    {'label': 'Spanish (Qwerty)', 'value': 'es-es-qwerty'},
    {'label': 'Spanish (Latin America) (Qwerty)', 'value': 'es-latam-qwerty'},
    {'label': 'Unicode', 'value': 'failsafe'},
    {'label': 'Belgian French (Azerty)', 'value': 'fr-be-azerty'},
    {'label': 'Schweiz/Französisch (Qwertz)', 'value': 'fr-ch-qwertz'},
    {'label': 'French (Azerty)', 'value': 'fr-fr-azerty'},
    {'label': 'Hungarian (Qwertz)', 'value': 'hu-hu-qwertz'},
    {'label': 'Italian (Qwerty)', 'value': 'it-it-qwerty'},
    {'label': 'Japanese (Qwerty)', 'value': 'ja-jp-qwerty'},
    {'label': 'Portuguese-Brazil (BR) (Qwerty)', 'value': 'pt-br-qwerty'},
    {'label': 'Swedish (Qwerty)', 'value': 'sv-se-qwerty'},
    {'label': 'Turkish (Qwerty)', 'value': 'tr-tr-qwerty'},
  ];

  static const List<String> iconOptions = [
    'mdiServer',
    'mdiConsole',
    'mdiMicrosoftWindows',
    'mdiMonitor',
    'mdiDesktopClassic',
    'mdiFolderNetwork',
    'mdiServerNetwork',
    'mdiDatabase',
    'mdiWeb',
    'mdiCloud',
    'mdiFlaskOutline',
    'mdiCamera',
    'mdiPrinter',
    'mdiRouterNetwork',
  ];
}
