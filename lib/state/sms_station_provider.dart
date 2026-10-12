import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';
import '../services/sms_listener_service.dart';
import '../services/sms_parser.dart';
import 'providers.dart';

class SmsStationState {
  const SmsStationState({
    this.isRunning = false,
    this.recentCredits = const [],
    this.totalDetected = 0,
    this.lastDetectedAt,
  });

  final bool isRunning;
  final List<ParsedBankSms> recentCredits;
  final int totalDetected;
  final DateTime? lastDetectedAt;

  SmsStationState copyWith({
    bool? isRunning,
    List<ParsedBankSms>? recentCredits,
    int? totalDetected,
    DateTime? lastDetectedAt,
  }) {
    return SmsStationState(
      isRunning: isRunning ?? this.isRunning,
      recentCredits: recentCredits ?? this.recentCredits,
      totalDetected: totalDetected ?? this.totalDetected,
      lastDetectedAt: lastDetectedAt ?? this.lastDetectedAt,
    );
  }
}

class SmsStationNotifier extends StateNotifier<SmsStationState> {
  SmsStationNotifier(this.ref) : super(const SmsStationState()) {
    _init();
  }

  final Ref ref;
  StreamSubscription? _creditSub;

  Future<void> _init() async {
    final running = await SmsListenerService.instance.isRunning();
    state = state.copyWith(isRunning: running);

    _creditSub = SmsListenerService.instance.onCreditDetected.listen(_handleCredit);
  }

  Future<void> _handleCredit(ParsedBankSms credit) async {
    final user = ref.read(authProvider);
    final orgId = user?.orgId;

    final updatedList = [credit, ...state.recentCredits];
    if (updatedList.length > 20) {
      updatedList.removeLast();
    }

    state = state.copyWith(
      recentCredits: updatedList,
      totalDetected: state.totalDetected + 1,
      lastDetectedAt: credit.receivedAt,
    );

    if (orgId != null && orgId.isNotEmpty && AppConfig.configured) {
      try {
        await sb.rpc('ingest_bank_sms', params: {
          'p_org_id': orgId,
          'p_reference': credit.reference,
          'p_amount': credit.amount,
          'p_sender': credit.senderName,
          'p_provider': credit.provider,
          'p_raw_sms': credit.rawSms,
        });
      } catch (_) {}
    }
  }

  Future<bool> toggleStation() async {
    final user = ref.read(authProvider);
    final orgId = user?.orgId;
    if (orgId == null) return false;

    if (state.isRunning) {
      await SmsListenerService.instance.stopStation();
      state = state.copyWith(isRunning: false);
      return false;
    } else {
      final success = await SmsListenerService.instance.startStation(orgId: orgId);
      state = state.copyWith(isRunning: success);
      return success;
    }
  }

  Future<void> refresh() async {
    final running = await SmsListenerService.instance.isRunning();
    state = state.copyWith(isRunning: running);
  }

  @override
  void dispose() {
    _creditSub?.cancel();
    super.dispose();
  }
}

final smsStationProvider = StateNotifierProvider<SmsStationNotifier, SmsStationState>((ref) {
  return SmsStationNotifier(ref);
});
