import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'providers.dart';

class SecurityState {
  const SecurityState({
    required this.pinEnabled,
    required this.biometricEnabled,
    required this.isLocked,
    this.hasPin = false,
  });

  final bool pinEnabled;
  final bool biometricEnabled;
  final bool isLocked;
  final bool hasPin;

  SecurityState copyWith({
    bool? pinEnabled,
    bool? biometricEnabled,
    bool? isLocked,
    bool? hasPin,
  }) =>
      SecurityState(
        pinEnabled: pinEnabled ?? this.pinEnabled,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        isLocked: isLocked ?? this.isLocked,
        hasPin: hasPin ?? this.hasPin,
      );
}

class SecurityNotifier extends Notifier<SecurityState> {
  static const _pinKey = 'local_security_pin';
  static const _pinEnabledKey = 'local_security_pin_enabled';
  static const _bioEnabledKey = 'local_security_bio_enabled';

  final _auth = LocalAuthentication();

  @override
  SecurityState build() {
    final p = ref.read(prefsProvider);
    final savedPin = p.getString(_pinKey);
    final pinOn = p.getBool(_pinEnabledKey) ?? false;
    final bioOn = p.getBool(_bioEnabledKey) ?? false;
    final hasPin = savedPin != null && savedPin.isNotEmpty;

    // Lock app on start if PIN or Biometric is active
    final needsLock = (pinOn && hasPin) || bioOn;

    return SecurityState(
      pinEnabled: pinOn,
      biometricEnabled: bioOn,
      isLocked: needsLock,
      hasPin: hasPin,
    );
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Scan fingerprint or face to unlock Mela',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (authenticated) {
        unlock();
        return true;
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: $e');
    }
    return false;
  }

  bool verifyPin(String enteredPin) {
    final savedPin = ref.read(prefsProvider).getString(_pinKey);
    if (savedPin != null && savedPin == enteredPin) {
      unlock();
      return true;
    }
    return false;
  }

  void unlock() {
    state = state.copyWith(isLocked: false);
  }

  void lock() {
    if (state.pinEnabled || state.biometricEnabled) {
      state = state.copyWith(isLocked: true);
    }
  }

  Future<void> setPin(String newPin) async {
    final p = ref.read(prefsProvider);
    await p.setString(_pinKey, newPin);
    await p.setBool(_pinEnabledKey, true);
    state = state.copyWith(pinEnabled: true, hasPin: true);
  }

  Future<void> disablePin() async {
    final p = ref.read(prefsProvider);
    await p.setBool(_pinEnabledKey, false);
    state = state.copyWith(pinEnabled: false);
  }

  Future<void> setBiometric(bool enable) async {
    final p = ref.read(prefsProvider);
    await p.setBool(_bioEnabledKey, enable);
    state = state.copyWith(biometricEnabled: enable);
  }
}

final securityProvider = NotifierProvider<SecurityNotifier, SecurityState>(SecurityNotifier.new);
