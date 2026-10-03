import 'package:flutter/widgets.dart';

// Localizations for the password prompt detection feature.
//
// The mobile app has no global i18n framework (all other strings are
// hardcoded English), so this file mirrors the exact web translations for
// `settings.terminal.input.passwordPromptDetection`, `enabled`/`disabled`,
// `servers.passwordHint.{paste,pasteFor,cycle}` and
// `servers.contextMenu.pasteIdentityPassword` from
// `client/public/assets/locales/*.json` (11 languages). Strings are copied
// 1:1 from the web client so both platforms read identically.

class PasswordPromptStrings {
  final String settingTitle;
  final String enabled;
  final String disabled;
  final String paste;
  final String pasteForTemplate;
  final String cycle;
  final String pasteIdentityPassword;

  const PasswordPromptStrings({
    required this.settingTitle,
    required this.enabled,
    required this.disabled,
    required this.paste,
    required this.pasteForTemplate,
    required this.cycle,
    required this.pasteIdentityPassword,
  });

  String pasteFor(String? username) {
    if (username == null || username.isEmpty) return paste;
    return pasteForTemplate.replaceAll('{{username}}', username);
  }
}

const PasswordPromptStrings _en = PasswordPromptStrings(
  settingTitle: 'Password input detection',
  enabled: 'Enabled',
  disabled: 'Disabled',
  paste: 'paste password',
  pasteForTemplate: 'paste {{username}} password',
  cycle: 'Use the arrow keys to switch identity',
  pasteIdentityPassword: 'Paste Password',
);

const Map<String, PasswordPromptStrings> _localized = {
  'en': _en,
  'de': PasswordPromptStrings(
    settingTitle: 'Erkennung der Passworteingabe',
    enabled: 'Aktiviert',
    disabled: 'Deaktiviert',
    paste: 'Passwort einfügen',
    pasteForTemplate: 'Einfügen {{username}} Passwort',
    cycle: 'Verwende die Pfeiltasten, um die Identität zu wechseln',
    pasteIdentityPassword: 'Passwort einfügen',
  ),
  'fr': PasswordPromptStrings(
    settingTitle: 'Détection de la saisie d\'un mot de passe',
    enabled: 'Activé',
    disabled: 'Désactivé',
    paste: 'coller le mot de passe',
    pasteForTemplate: 'copier-coller {{username}} mot de passe',
    cycle: 'Utilise les touches fléchées pour changer d\'identité',
    pasteIdentityPassword: 'Coller le mot de passe',
  ),
  'es': PasswordPromptStrings(
    settingTitle: 'Detección de la introducción de la contraseña',
    enabled: 'Activado',
    disabled: 'Desactivado',
    paste: 'pega la contraseña',
    pasteForTemplate: 'pega {{username}} contraseña',
    cycle: 'Usa las teclas de flecha para cambiar de identidad',
    pasteIdentityPassword: 'Pegar contraseña',
  ),
  'it': PasswordPromptStrings(
    settingTitle: 'Rilevamento dell\'inserimento della password',
    enabled: 'Attivato',
    disabled: 'Disabile',
    paste: 'incolla la password',
    pasteForTemplate: 'incolla {{username}} password',
    cycle: 'Usa i tasti freccia per cambiare identità',
    pasteIdentityPassword: 'Incolla la password',
  ),
  'pt': PasswordPromptStrings(
    settingTitle: 'Detecção de digitação de senha',
    enabled: 'Ativado',
    disabled: 'Desativado',
    paste: 'colar a senha',
    pasteForTemplate: 'colar {{username}} senha',
    cycle: 'Use as setas do teclado para trocar de identidade',
    pasteIdentityPassword: 'Colar Senha',
  ),
  'ru': PasswordPromptStrings(
    settingTitle: 'Обнаружение ввода пароля',
    enabled: 'Включено',
    disabled: 'Отключено',
    paste: 'вставить пароль',
    pasteForTemplate: 'вставь {{username}} пароль',
    cycle: 'Используй клавиши со стрелками, чтобы сменить персонажа',
    pasteIdentityPassword: 'Вставить пароль',
  ),
  'cs': PasswordPromptStrings(
    settingTitle: 'Detekce zadávání hesla',
    enabled: 'Zapnuto',
    disabled: 'Znevýhodnění',
    paste: 'vložit heslo',
    pasteForTemplate: 'vložit {{username}} heslo',
    cycle: 'K přepínání identity použijte šipky',
    pasteIdentityPassword: 'Vložit heslo',
  ),
  'ar': PasswordPromptStrings(
    settingTitle: 'الكشف عن إدخال كلمة المرور',
    enabled: 'ممكّن',
    disabled: 'ذوو الإعاقة',
    paste: 'لصق كلمة المرور',
    pasteForTemplate: 'لصق {{username}} كلمة المرور',
    cycle: 'استخدم مفاتيح الأسهم لتغيير الهوية',
    pasteIdentityPassword: 'لصق كلمة المرور',
  ),
  'zh_CN': PasswordPromptStrings(
    settingTitle: '密码输入检测',
    enabled: '已启用',
    disabled: '已禁用',
    paste: '粘贴密码',
    pasteForTemplate: '粘贴 {{username}} 密码',
    cycle: '使用方向键切换角色',
    pasteIdentityPassword: '粘贴密码',
  ),
  'zh_TW': PasswordPromptStrings(
    settingTitle: '密碼輸入偵測',
    enabled: '已啟用',
    disabled: '已停用',
    paste: '貼上密碼',
    pasteForTemplate: '貼上 {{username}} 密碼',
    cycle: '使用方向鍵切換角色',
    pasteIdentityPassword: '貼上密碼',
  ),
};

/// Resolves the strings for a locale tag such as `de_DE`, `pt-BR` or `zh-Hant`.
///
/// Lookup order: full tag with `_` separator (`zh_CN`), then language code
/// (`zh` -> `zh_CN`), then English fallback. `zh` without region defaults to
/// simplified Chinese, matching the larger user base.
PasswordPromptStrings passwordPromptStringsForTag(String? tag) {
  if (tag == null || tag.isEmpty) return _en;
  final normalized = tag.replaceAll('-', '_');
  if (_localized.containsKey(normalized)) return _localized[normalized]!;
  final lang = normalized.split('_').first.toLowerCase();
  if (lang == 'zh') {
    final upper = normalized.toUpperCase();
    if (upper.contains('TW') ||
        upper.contains('HANT') ||
        upper.contains('HK')) {
      return _localized['zh_TW']!;
    }
    return _localized['zh_CN']!;
  }
  if (_localized.containsKey(lang)) return _localized[lang]!;
  return _en;
}

class PasswordPromptLocalizations {
  const PasswordPromptLocalizations._();

  /// Returns the strings for the current device locale.
  static PasswordPromptStrings of(BuildContext context) {
    try {
      final locale = Localizations.localeOf(context);
      final tag = locale.toLanguageTag();
      final resolved = passwordPromptStringsForTag(tag);
      if (resolved != _en) return resolved;
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
        return passwordPromptStringsForTag(
            '${locale.languageCode}_${locale.countryCode}');
      }
      return passwordPromptStringsForTag(locale.languageCode);
    } catch (_) {
      return _en;
    }
  }
}
