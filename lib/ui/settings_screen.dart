import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../core/friendly_error.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../state/providers.dart';
import '../state/security_provider.dart';
import '../state/sms_station_provider.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.showSync = false});
  final bool showSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider)!;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final sec = ref.watch(securityProvider);
    final secNotifier = ref.read(securityProvider.notifier);
    final station = ref.watch(smsStationProvider);
    final stationNotifier = ref.read(smsStationProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final sync = ref.watch(syncProvider);
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Panel(
        child: Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.primaryContainer,
            child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(user.orgName, style: TextStyle(color: cs.onSurfaceVariant)),
            ]),
          ),
          StatusPill(user.role.toUpperCase(), cs.primary),
        ]),
      ),
      if (user.isManager && !user.isSuperAdmin) ...[
        const SizedBox(height: 12),
        Panel(
          child: Row(children: [
            const Icon(Icons.vpn_key_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Team join code', style: TextStyle(fontWeight: FontWeight.w700)),
                Text(user.joinCode,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 3)),
              ]),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: user.joinCode));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Join code copied'), behavior: SnackBarBehavior.floating));
              },
            ),
          ]),
        ),
        _section(context, 'SMS Verification Station'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                station.isRunning ? Icons.sim_card_download_rounded : Icons.sim_card_outlined,
                color: station.isRunning ? StatusColors.synced : null,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Business SIM SMS Listener', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(
                    station.isRunning
                        ? 'Active · Background station verifying Telebirr & CBE'
                        : 'Disabled · Turn on if this phone has the business SIM card',
                    style: TextStyle(
                      fontSize: 12,
                      color: station.isRunning ? StatusColors.synced : cs.onSurfaceVariant,
                      fontWeight: station.isRunning ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ]),
              ),
              Switch(
                value: station.isRunning,
                onChanged: (_) async {
                  final ok = await stationNotifier.toggleStation();
                  if (context.mounted && !ok && !station.isRunning) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('SMS permission denied or unable to start station background service.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ]),
            if (station.isRunning) ...[
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${station.totalDetected} Bank SMS Captured',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (station.lastDetectedAt != null)
                  Text('Last: ${fmtTime(station.lastDetectedAt!)}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
              if (station.recentCredits.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final c in station.recentCredits.take(3))
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      ProviderAvatar(c.provider),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${fmtCurrency(c.amount)} · ${c.reference}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          if (c.senderName != null)
                            Text('From: ${c.senderName}',
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                      const StatusPill('Verified', StatusColors.synced),
                    ]),
                  ),
              ],
            ],
          ]),
        ),
      ],
      _section(context, 'Appearance'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => n.setTheme(v.first),
          ),
          const SizedBox(height: 16),
          const Text('Accent colour', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(spacing: 12, children: [
            for (var i = 0; i < seeds.length; i++)
              GestureDetector(
                onTap: () => n.setSeed(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: seeds[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: s.seed == i ? cs.onSurface : Colors.transparent, width: 3),
                  ),
                  child: s.seed == i ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                ),
              ),
          ]),
        ]),
      ),
      _section(context, 'App Security & Privacy'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          SwitchListTile(
            value: sec.biometricEnabled,
            onChanged: (val) async {
              if (val) {
                final canBio = await secNotifier.canCheckBiometrics();
                if (!canBio) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Biometric hardware (fingerprint) is not configured on this device.'), behavior: SnackBarBehavior.floating),
                    );
                  }
                  return;
                }
                final ok = await secNotifier.authenticateBiometric();
                if (ok) {
                  await secNotifier.setBiometric(true);
                }
              } else {
                await secNotifier.setBiometric(false);
              }
            },
            title: const Text('Fingerprint / Biometric Lock'),
            subtitle: const Text('Authenticate with fingerprint on app launch (100% offline)'),
            secondary: const Icon(Icons.fingerprint_rounded),
          ),
          SwitchListTile(
            value: sec.pinEnabled,
            onChanged: (val) async {
              if (val) {
                _promptSetPin(context, ref);
              } else {
                await secNotifier.disablePin();
              }
            },
            title: const Text('Passcode / PIN Lock'),
            subtitle: Text(sec.hasPin ? 'PIN is active · Protects local access' : 'Tap to configure a 4 to 6 digit PIN'),
            secondary: const Icon(Icons.pin_rounded),
          ),
          if (sec.pinEnabled)
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Change Lock PIN'),
              subtitle: const Text('Update your local security passcode'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _promptChangePin(context, ref),
            ),
          ListTile(
            leading: const Icon(Icons.lock_reset_rounded),
            title: const Text('Change Password'),
            subtitle: const Text('Update your sign-in password'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _promptChangePassword(context, ref),
          ),
          if (sec.pinEnabled || sec.biometricEnabled)
            ListTile(
              leading: const Icon(Icons.lock_clock_rounded),
              title: const Text('Lock App Now'),
              subtitle: const Text('Immediately lock screen and test verification'),
              onTap: () => secNotifier.lock(),
            ),
        ]),
      ),
      _section(context, 'Alerts & feedback'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          SwitchListTile(
            value: s.sound,
            onChanged: n.setSound,
            title: const Text('Notification sound'),
            subtitle: const Text('Play sound when receipts and payments are verified'),
            secondary: const Icon(Icons.volume_up_rounded),
          ),
          SwitchListTile(
            value: s.haptics,
            onChanged: n.setHaptics,
            title: const Text('Haptic feedback'),
            subtitle: const Text('Vibrate gently when capturing receipts'),
            secondary: const Icon(Icons.vibration_rounded),
          ),
        ]),
      ),
      if (showSync) ...[
        _section(context, 'Sync'),
        Panel(
          child: Column(children: [
            Row(children: [
              Icon(sync.online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: sync.online ? StatusColors.synced : StatusColors.pending),
              const SizedBox(width: 12),
              Expanded(
                child: Text(sync.online ? 'Online' : 'Offline – receipts are saved on this device',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              StatusPill('$pending pending', pending == 0 ? StatusColors.synced : StatusColors.pending),
            ]),
            if (sync.lastSync != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, left: 36),
                  child: Text('Last sync ${fmtDateTime(sync.lastSync!)}', style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: sync.syncing ? null : () => ref.read(syncProvider.notifier).sync(),
              icon: sync.syncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded),
              label: Text(sync.syncing ? 'Syncing…' : 'Sync now'),
            ),
          ]),
        ),
      ],
      _section(context, 'Data retention'),
      Panel(
        child: Row(children: [
          const Icon(Icons.auto_delete_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Receipt photos are deleted after ${AppConfig.retentionDays} days (device and cloud). '
              'Amounts, references and totals are kept permanently.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: cs.error,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Sign out?'),
              content: Text(pending > 0
                  ? '$pending receipt(s) are not synced yet. They stay on this device and upload when you sign back in.'
                  : 'You will need to sign in again.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sign out')),
              ],
            ),
          );
          if (ok == true) ref.read(authProvider.notifier).signOut();
        },
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
      ),
    ]);
  }

  Widget _section(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.primary)),
      );

  void _promptSetPin(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Offline PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a 4 to 6 digit passcode to lock the app locally.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              autofocus: true,
              style: const TextStyle(letterSpacing: 8, fontSize: 22, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                hintText: '••••',
                counterText: '',
                prefixIcon: Icon(Icons.password_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final pin = controller.text.trim();
              if (pin.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN must be at least 4 digits.')),
                );
                return;
              }
              await ref.read(securityProvider.notifier).setPin(pin);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN lock enabled successfully!'), behavior: SnackBarBehavior.floating),
                );
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  void _promptChangePin(BuildContext context, WidgetRef ref) {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final sec = ref.read(securityProvider.notifier);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Lock PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your current PIN:'),
            const SizedBox(height: 8),
            TextField(
              controller: oldController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(letterSpacing: 6, fontSize: 18, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: 'Current PIN', counterText: '', prefixIcon: Icon(Icons.pin_outlined)),
            ),
            const SizedBox(height: 16),
            const Text('Enter your new PIN (4 to 6 digits):'),
            const SizedBox(height: 8),
            TextField(
              controller: newController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              style: const TextStyle(letterSpacing: 6, fontSize: 18, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: 'New PIN', counterText: '', prefixIcon: Icon(Icons.password_rounded)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final oldPin = oldController.text.trim();
              final newPin = newController.text.trim();
              if (!sec.verifyPin(oldPin)) {
                FriendlyError.show(context, 'Current PIN is incorrect. Please try again.');
                return;
              }
              if (newPin.length < 4) {
                FriendlyError.show(context, 'New PIN must be at least 4 digits.');
                return;
              }
              await sec.setPin(newPin);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                FriendlyError.showSuccess(context, 'Lock PIN updated successfully!');
              }
            },
            child: const Text('Update PIN'),
          ),
        ],
      ),
    );
  }

  void _promptChangePassword(BuildContext context, WidgetRef ref) {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter a new password for your Mela account:'),
              const SizedBox(height: 14),
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final p1 = newPassCtrl.text.trim();
                      final p2 = confirmPassCtrl.text.trim();
                      if (p1.length < 6) {
                        FriendlyError.show(context, 'Password must be at least 6 characters.');
                        return;
                      }
                      if (p1 != p2) {
                        FriendlyError.show(context, 'Passwords do not match. Please retype.');
                        return;
                      }

                      setState(() => loading = true);
                      try {
                        await sb.auth.updateUser(
                          UserAttributes(password: p1),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          FriendlyError.showSuccess(context, 'Account password updated successfully!');
                        }
                      } catch (e) {
                        setState(() => loading = false);
                        if (context.mounted) {
                          FriendlyError.show(context, e, title: 'Password Update Failed');
                        }
                      }
                    },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }
}
