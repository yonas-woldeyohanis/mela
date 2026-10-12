import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/config.dart';
import 'notification_service.dart';
import 'sms_parser.dart';

class SmsListenerService {
  SmsListenerService._();
  static final instance = SmsListenerService._();

  static const _methodChannel = MethodChannel('com.swiftreceipt/sms_listener');
  static const _eventChannel = EventChannel('com.swiftreceipt/sms_stream');

  StreamSubscription? _streamSub;
  final _onCreditDetected = StreamController<ParsedBankSms>.broadcast();
  Stream<ParsedBankSms> get onCreditDetected => _onCreditDetected.stream;

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _streamSub = _eventChannel.receiveBroadcastStream().listen((dynamic raw) async {
      try {
        if (raw is Map) {
          final sender = (raw['sender'] as String?) ?? '';
          final body = (raw['body'] as String?) ?? '';
          final timestampMs = raw['timestamp'] as num?;
          final timestamp = timestampMs != null ? DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt()) : DateTime.now();

          final parsed = SmsParser.parse(sender: sender, body: body, timestamp: timestamp);
          if (parsed != null) {
            _onCreditDetected.add(parsed);

            // Notify user/owner on device
            NotificationService.instance.show(
              '${parsed.provider} Payment Verified',
              'Received ETB ${parsed.amount.toStringAsFixed(2)} · Ref: ${parsed.reference}${parsed.senderName != null ? ' (${parsed.senderName})' : ''}',
            );
          }
        }
      } catch (e) {
        debugPrint('Error processing incoming SMS stream: $e');
      }
    }, onError: (err) {
      debugPrint('SMS stream error: $err');
    });
  }

  Future<bool> isRunning() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isListenerRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermissions() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('hasPermissions');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startStation({required String orgId}) async {
    init();
    try {
      final success = await _methodChannel.invokeMethod<bool>('startListener', {
        'org_id': orgId,
        'supabase_url': AppConfig.supabaseUrl,
        'supabase_key': AppConfig.supabaseAnonKey,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Failed to start SMS station: $e');
      return false;
    }
  }

  Future<void> stopStation() async {
    try {
      await _methodChannel.invokeMethod('stopListener');
      await _streamSub?.cancel();
      _streamSub = null;
      _initialized = false;
    } catch (_) {}
  }
}
