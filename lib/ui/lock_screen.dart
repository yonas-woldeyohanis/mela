import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/security_provider.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _enteredPin = '';
  String? _error;
  bool _authenticatingBio = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sec = ref.read(securityProvider);
      if (sec.biometricEnabled) {
        _tryBiometric();
      }
    });
  }

  Future<void> _tryBiometric() async {
    if (_authenticatingBio) return;
    setState(() => _authenticatingBio = true);
    final ok = await ref.read(securityProvider.notifier).authenticateBiometric();
    if (mounted) {
      setState(() => _authenticatingBio = false);
      if (!ok) {
        HapticFeedback.lightImpact();
      }
    }
  }

  void _onDigit(String d) {
    if (_enteredPin.length >= 6) return;
    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin += d;
      _error = null;
    });

    if (_enteredPin.length == 4 || _enteredPin.length == 6) {
      // Check if matches
      final sec = ref.read(securityProvider.notifier);
      if (sec.verifyPin(_enteredPin)) {
        HapticFeedback.mediumImpact();
      } else if (_enteredPin.length == 6) {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = 'Incorrect PIN';
          _enteredPin = '';
        });
      }
    }
  }

  void _onDelete() {
    if (_enteredPin.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sec = ref.watch(securityProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_rounded, size: 44, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              const Text(
                'Mela Secured',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your offline security PIN or scan fingerprint',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 32),

              // PIN Indicator Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final filled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: filled ? 18 : 14,
                    height: filled ? 18 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  );
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: cs.error, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
              const Spacer(flex: 2),

              // Number keypad
              for (var row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ]) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var d in row)
                      _keypadButton(d, cs),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  sec.biometricEnabled
                      ? IconButton.filledTonal(
                          iconSize: 32,
                          padding: const EdgeInsets.all(18),
                          onPressed: _tryBiometric,
                          icon: const Icon(Icons.fingerprint_rounded),
                        )
                      : const SizedBox(width: 72, height: 72),
                  _keypadButton('0', cs),
                  IconButton(
                    iconSize: 28,
                    padding: const EdgeInsets.all(20),
                    onPressed: _onDelete,
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                ],
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypadButton(String digit, ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => _onDigit(digit),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
