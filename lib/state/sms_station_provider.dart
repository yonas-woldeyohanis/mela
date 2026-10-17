import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/config.dart';
import '../data/local_db.dart';
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
    _creditSub = SmsListenerService.instance.onCreditDetected.listen(_handleCredit);
    final running = await SmsListenerService.instance.isRunning();

    final prefs = ref.read(prefsProvider);
    final disabledByUser = prefs.getBool('station_disabled_by_user') ?? false;

    final user = ref.read(authProvider);
    // Role-based guard: ONLY 'owner' should run the SMS verification station and request SMS permissions!
    // Waiters and other staff should NEVER be prompted for SMS permissions.
    if (user != null && user.role != 'owner') {
      if (running) {
        await SmsListenerService.instance.stopStation();
      }
      state = state.copyWith(isRunning: false);
      return;
    }

    if (!running && !disabledByUser && user != null && user.role == 'owner' && user.orgId.isNotEmpty) {
      final success = await SmsListenerService.instance.startStation(orgId: user.orgId);
      state = state.copyWith(isRunning: success);
    } else {
      state = state.copyWith(isRunning: running);
    }
  }

  Future<void> autoStartIfNeeded() async {
    if (state.isRunning) return;
    final prefs = ref.read(prefsProvider);
    final disabledByUser = prefs.getBool('station_disabled_by_user') ?? false;
    if (disabledByUser) return;

    final user = ref.read(authProvider);
    if (user != null && user.role == 'owner' && user.orgId.isNotEmpty) {
      final success = await SmsListenerService.instance.startStation(orgId: user.orgId);
      if (success) {
        state = state.copyWith(isRunning: true);
      }
    }
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

    if (orgId != null && orgId.isNotEmpty) {
      final creditId = const Uuid().v4();
      var synced = false;

      if (AppConfig.configured) {
        try {
          await sb.rpc('ingest_bank_sms', params: {
            'p_org_id': orgId,
            'p_reference': credit.reference,
            'p_amount': credit.amount,
            'p_sender': credit.senderName,
            'p_provider': credit.provider,
            'p_raw_sms': credit.rawSms,
          });
          synced = true;
        } catch (_) {}
      }

      // Always save to local SQLite database so credits are kept for days and verified offline!
      await LocalDb.instance.saveLocalBankCredit(
        id: creditId,
        orgId: orgId,
        reference: credit.reference,
        amount: credit.amount,
        provider: credit.provider,
        senderName: credit.senderName,
        receiverPhone: credit.receiverPhone,
        balance: credit.balance,
        rawSms: credit.rawSms,
        receivedAt: credit.receivedAt,
        syncedToCloud: synced,
      );
    }
  }

  Future<bool> toggleStation() async {
    final user = ref.read(authProvider);
    final orgId = user?.orgId;
    if (orgId == null || user?.role != 'owner') return false;
    final prefs = ref.read(prefsProvider);

    if (state.isRunning) {
      await SmsListenerService.instance.stopStation();
      await prefs.setBool('station_disabled_by_user', true);
      state = state.copyWith(isRunning: false);
      return false;
    } else {
      final success = await SmsListenerService.instance.startStation(orgId: orgId);
      if (success) {
        await prefs.setBool('station_disabled_by_user', false);
      }
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
