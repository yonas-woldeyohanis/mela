import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils.dart';
import '../data/local_db.dart';

/// Background Telegram Storage Service for free, unlimited cloud receipt image storage.
class TelegramBackupService {
  TelegramBackupService._();
  static final instance = TelegramBackupService._();

  static const keyEnabled = 'telegram_backup_enabled';
  static const keyBotToken = 'telegram_bot_token';
  static const keyChatId = 'telegram_chat_id';

  bool _isProcessing = false;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyEnabled) ?? false;
  }

  Future<String> getBotToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(keyBotToken) ?? '';
    if (token.isNotEmpty) return token;
    return prefs.getString('platform_bot_token') ?? '';
  }

  Future<String> getChatId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyChatId) ?? '';
  }

  Future<void> setConfig({
    required bool enabled,
    required String botToken,
    required String chatId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, enabled);
    await prefs.setString(keyBotToken, botToken.trim());
    await prefs.setString(keyChatId, chatId.trim());
  }

  /// Verifies the Bot Token and tests posting a message to the specified Telegram channel/group.
  Future<({bool success, String message})> testConnection({
    required String botToken,
    required String chatId,
  }) async {
    String token = botToken.trim();
    if (token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('platform_bot_token') ?? '';
    }
    final chat = chatId.trim();

    if (token.isEmpty) {
      return (success: false, message: 'Please enter your Telegram Bot Token (or configure the platform bot).');
    }
    if (chat.isEmpty) {
      return (success: false, message: 'Please enter your Telegram Channel / Group ID.');
    }

    try {
      // 1. Test getMe
      final getMeUri = Uri.parse('https://api.telegram.org/bot$token/getMe');
      final getMeRes = await http.get(getMeUri).timeout(const Duration(seconds: 10));
      if (getMeRes.statusCode != 200) {
        return (success: false, message: 'Invalid Bot Token. Check the token from @BotFather.');
      }

      final botData = jsonDecode(getMeRes.body) as Map<String, dynamic>;
      final botUsername = (botData['result']?['username'] as String?) ?? 'Your Bot';

      // 2. Test sending a test message to the channel/group
      final sendUri = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final sendRes = await http.post(sendUri, body: {
        'chat_id': chat,
        'text': '🎉 *Mela Receipt Storage Connected!*\n\nBot: @$botUsername\nReceipt photos will now be backed up here automatically in the background.',
        'parse_mode': 'Markdown',
      }).timeout(const Duration(seconds: 10));

      if (sendRes.statusCode == 200) {
        return (success: true, message: 'Connected successfully to @$botUsername!');
      } else {
        return (
          success: false,
          message: 'Bot reached, but could not post to $chat. Make sure the bot is an Administrator in the channel/group with "Post Messages" permission.'
        );
      }
    } catch (e) {
      return (success: false, message: 'Connection failed: Check internet connection or token syntax.');
    }
  }

  /// Queues a scanned receipt photo for silent background upload to Telegram.
  Future<void> queueUpload({
    required String localId,
    required String orgId,
    required String imagePath,
    required double amount,
    required String reference,
    required String provider,
    String? sender,
    String? waiterName,
    String? orgName,
    String? receiptUrl,
  }) async {
    try {
      final enabled = await isEnabled();
      if (!enabled) return;

      final now = DateTime.now();
      final dateStr = fmtDateTime(now);
      final refDisplay = reference.startsWith('NO-REF') ? 'None (Cash / Manual)' : reference;

      final caption = '''
🧾 *Mela Receipt* · ${fmtCurrency(amount)}
🏢 *Business*: ${orgName ?? 'Organization'}
🔢 *Ref*: `$refDisplay`
🏦 *Provider*: $provider
👤 *Staff*: ${waiterName ?? 'Staff'}
📅 *Date*: $dateStr
${sender != null ? '👤 *Payer*: $sender\n' : ''}${receiptUrl != null && receiptUrl.isNotEmpty ? '🔗 *Bank Link*: $receiptUrl\n' : ''}#receipt #payment
''';

      await LocalDb.instance.queueTelegramUpload(
        localId: localId,
        orgId: orgId,
        imagePath: imagePath,
        caption: caption,
      );

      // Trigger background upload without waiting
      processQueue();
    } catch (e) {
      debugPrint('Telegram queue error (non-fatal): $e');
    }
  }

  /// Processes pending items in the Telegram queue when internet connectivity is present.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final enabled = await isEnabled();
      if (!enabled) return;

      final botToken = await getBotToken();
      final chatId = await getChatId();

      if (botToken.isEmpty || chatId.isEmpty) return;

      final pending = await LocalDb.instance.getPendingTelegramUploads();
      for (final item in pending) {
        final localId = item['local_id'] as String;
        final imagePath = item['image_path'] as String;
        final caption = item['caption'] as String;

        final file = File(imagePath);
        if (!file.existsSync()) {
          // File was deleted or missing, remove from queue
          await LocalDb.instance.markTelegramUploaded(localId);
          continue;
        }

        try {
          final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendPhoto');
          final req = http.MultipartRequest('POST', uri);
          req.fields['chat_id'] = chatId;
          req.fields['caption'] = caption;
          req.fields['parse_mode'] = 'Markdown';
          req.files.add(await http.MultipartFile.fromPath('photo', imagePath));

          final streamedResponse = await req.send().timeout(const Duration(seconds: 25));
          if (streamedResponse.statusCode == 200) {
            await LocalDb.instance.markTelegramUploaded(localId);
            debugPrint('Telegram backup: Receipt $localId uploaded successfully.');
          } else {
            await LocalDb.instance.incrementTelegramRetry(localId);
          }
        } catch (e) {
          debugPrint('Telegram upload network pause: $e');
          await LocalDb.instance.incrementTelegramRetry(localId);
          break; // Stop loop if network is offline
        }
      }
    } catch (e) {
      debugPrint('Telegram processQueue error: $e');
    } finally {
      _isProcessing = false;
    }
  }
}
