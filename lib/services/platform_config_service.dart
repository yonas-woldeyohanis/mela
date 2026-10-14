import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/providers.dart';

class PlatformConfig {
  const PlatformConfig({
    required this.supportPhone,
    required this.supportTelegram,
    required this.defaultBotToken,
  });

  final String supportPhone;
  final String supportTelegram;
  final String defaultBotToken;
}

class PlatformConfigService {
  PlatformConfigService._();
  static final instance = PlatformConfigService._();

  static const defaultPhone = '0996246990';
  static const defaultTelegram = '@jonas_wjohn';

  static const keySupportPhone = 'platform_support_phone';
  static const keySupportTelegram = 'platform_support_telegram';
  static const keyPlatformBotToken = 'platform_bot_token';

  Future<PlatformConfig> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString(keySupportPhone) ?? defaultPhone;
    final tg = prefs.getString(keySupportTelegram) ?? defaultTelegram;
    final botToken = prefs.getString(keyPlatformBotToken) ?? '';

    // Async background refresh from Supabase if connected
    _refreshFromCloud(prefs);

    return PlatformConfig(
      supportPhone: phone,
      supportTelegram: tg,
      defaultBotToken: botToken,
    );
  }

  Future<void> _refreshFromCloud(SharedPreferences prefs) async {
    try {
      final rows = await sb.from('platform_config').select('key, value');
      for (final r in rows) {
        final k = r['key'] as String;
        final v = r['value'] as String;
        if (k == 'support_phone') await prefs.setString(keySupportPhone, v);
        if (k == 'support_telegram') await prefs.setString(keySupportTelegram, v);
        if (k == 'platform_bot_token') await prefs.setString(keyPlatformBotToken, v);
      }
    } catch (_) {
      // Table might not exist yet or offline, local values will be preserved
    }
  }

  Future<void> updateConfig({
    required String phone,
    required String telegram,
    String? botToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySupportPhone, phone.trim());
    await prefs.setString(keySupportTelegram, telegram.trim());
    if (botToken != null) {
      await prefs.setString(keyPlatformBotToken, botToken.trim());
    }

    // Push to Supabase platform_config table
    try {
      await sb.from('platform_config').upsert([
        {'key': 'support_phone', 'value': phone.trim(), 'updated_at': DateTime.now().toIso8601String()},
        {'key': 'support_telegram', 'value': telegram.trim(), 'updated_at': DateTime.now().toIso8601String()},
        if (botToken != null)
          {'key': 'platform_bot_token', 'value': botToken.trim(), 'updated_at': DateTime.now().toIso8601String()},
      ]);
    } catch (e) {
      debugPrint('Cloud config upsert non-fatal: $e');
    }
  }

  Future<void> callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  Future<void> openTelegram(String telegramHandle) async {
    final handle = telegramHandle.replaceAll('@', '').trim();
    final uri = Uri.parse('https://t.me/$handle');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
