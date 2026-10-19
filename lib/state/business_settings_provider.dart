import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_settings.dart';
import 'providers.dart';

class BusinessSettingsNotifier extends StateNotifier<BusinessSettings> {
  BusinessSettingsNotifier(this.ref) : super(const BusinessSettings()) {
    _load();
  }

  final Ref ref;

  String _key(String orgId) => 'org_business_settings_$orgId';

  void _load() {
    final user = ref.read(authProvider);
    final prefs = ref.read(prefsProvider);
    final orgId = user?.orgId ?? 'default';

    final raw = prefs.getString(_key(orgId));
    if (raw != null && raw.isNotEmpty) {
      try {
        state = BusinessSettings.fromJson(raw);
      } catch (_) {
        state = const BusinessSettings();
      }
    } else {
      state = const BusinessSettings();
    }
  }

  Future<void> updateSettings(BusinessSettings newSettings) async {
    state = newSettings;
    final user = ref.read(authProvider);
    final prefs = ref.read(prefsProvider);
    final orgId = user?.orgId ?? 'default';

    await prefs.setString(_key(orgId), newSettings.toJson());

    // Best-effort cloud sync if Supabase is connected
    if (user != null && user.orgId.isNotEmpty) {
      try {
        await sb.from('organizations').update({
          'settings': newSettings.toMap(),
        }).eq('id', user.orgId);
      } catch (_) {}
    }
  }

  Future<void> setShiftMode(ShiftMode mode) async {
    await updateSettings(state.copyWith(shiftMode: mode));
  }

  Future<void> updateShift(int index, ShiftDefinition shift) async {
    if (index == 0) {
      await updateSettings(state.copyWith(shift1: shift));
    } else if (index == 1) {
      await updateSettings(state.copyWith(shift2: shift));
    } else if (index == 2) {
      await updateSettings(state.copyWith(shift3: shift));
    }
  }

  Future<void> setOwnerReportContact(String contact) async {
    await updateSettings(state.copyWith(ownerReportContact: contact.trim()));
  }

  Future<void> setVarianceTolerance(double tolerance) async {
    await updateSettings(state.copyWith(varianceTolerance: tolerance));
  }

  Future<void> setHighValueAlertAmount(double amount) async {
    await updateSettings(state.copyWith(highValueAlertAmount: amount));
  }

  Future<void> setRolloverHour(int hour) async {
    await updateSettings(state.copyWith(businessRolloverHour: hour));
  }
}

final businessSettingsProvider =
    StateNotifierProvider<BusinessSettingsNotifier, BusinessSettings>((ref) {
  return BusinessSettingsNotifier(ref);
});
