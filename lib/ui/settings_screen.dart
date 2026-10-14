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
import '../data/models.dart';
import '../services/platform_config_service.dart';
import '../services/telegram_service.dart';
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
          Stack(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cs.primaryContainer,
              child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
              ),
            ),
          ]),
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_rounded, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bank Account Holder Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  user.accountHolderName?.isNotEmpty == true
                      ? user.accountHolderName!
                      : 'Not configured (slips match "${user.orgName}")',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: user.accountHolderName?.isNotEmpty == true ? FontWeight.w700 : FontWeight.normal,
                    color: user.accountHolderName?.isNotEmpty == true ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Name appearing on CBE / Telebirr slips. Prevents fraud warnings when customers transfer.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            IconButton.filledTonal(
              icon: const Icon(Icons.edit_rounded, size: 20),
              tooltip: 'Edit Account Holder Name',
              onPressed: () => _promptEditAccountHolder(context, ref, user.accountHolderName ?? ''),
            ),
          ]),
        ),
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
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.workspace_premium_rounded, color: cs.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Business Subscription', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(
                      user.orgName,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ]),
                ),
                _subscriptionBadge(user),
              ]),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Plan / Rate', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    const Text('1,000 ETB / month', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Days Remaining', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      _remainingDaysText(user.subscriptionExpiresAt),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _remainingDaysColor(user.subscriptionExpiresAt),
                      ),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      user.subscriptionExpiresAt != null && user.subscriptionExpiresAt!.isBefore(DateTime.now())
                          ? Icons.error_outline_rounded
                          : Icons.event_available_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user.subscriptionExpiresAt != null
                            ? 'Renews / Expires: ${fmtDateTime(user.subscriptionExpiresAt!)}'
                            : 'No active expiration date recorded',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SupportContactCard(),
            ],
          ),
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
        _section(context, 'Telegram Cloud Storage'),
        const TelegramBackupCard(),
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
      const SizedBox(height: 28),
      Center(
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mela · Digital Receipt Ledger',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '© DropEffect Solutions · All rights reserved',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ]);
  }

  void _promptEditAccountHolder(BuildContext context, WidgetRef ref, String currentName) {
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.account_balance_rounded, size: 22),
          SizedBox(width: 8),
          Text('Account Holder Name'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the registered account owner name(s) appearing on CBE, Telebirr, or Dashen payment slips:\n\n'
              'When customers transfer money to this account name, Mela will automatically accept the receipt without fraud warnings.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Account Holder Name *',
                hintText: 'e.g. BETELHEM FKADU CHALA',
                helperText: 'Separate multiple names with commas',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              await ref.read(authProvider.notifier).updateAccountHolderName(newName);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                FriendlyError.showSuccess(context, 'Bank account holder name updated!');
              }
            },
            child: const Text('Save Name'),
          ),
        ],
      ),
    );
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

Widget _subscriptionBadge(AppUser user) {
  if (user.orgStatus == 'suspended') {
    return const StatusPill('Suspended', StatusColors.flagged, icon: Icons.block_rounded);
  }
  if (user.subscriptionExpiresAt != null) {
    final diff = user.subscriptionExpiresAt!.difference(DateTime.now()).inDays;
    if (diff < 0) {
      return const StatusPill('Expired', StatusColors.flagged, icon: Icons.cancel_outlined);
    }
    if (diff <= 7) {
      return const StatusPill('Expiring Soon', Color(0xFFF59E0B), icon: Icons.timelapse_rounded);
    }
  }
  return const StatusPill('Active', StatusColors.synced, icon: Icons.check_circle_rounded);
}

String _remainingDaysText(DateTime? expiresAt) {
  if (expiresAt == null) return 'N/A';
  final diff = expiresAt.difference(DateTime.now()).inDays;
  if (diff < 0) return 'Expired';
  if (diff == 0) return 'Expires today';
  if (diff == 1) return '1 day left';
  return '$diff days left';
}

Color _remainingDaysColor(DateTime? expiresAt) {
  if (expiresAt == null) return Colors.grey;
  final diff = expiresAt.difference(DateTime.now()).inDays;
  if (diff < 0) return StatusColors.flagged;
  if (diff <= 7) return const Color(0xFFF59E0B);
  return StatusColors.synced;
}

class TelegramBackupCard extends StatefulWidget {
  const TelegramBackupCard({super.key});

  @override
  State<TelegramBackupCard> createState() => _TelegramBackupCardState();
}

class _TelegramBackupCardState extends State<TelegramBackupCard> {
  bool _enabled = false;
  bool _obscureToken = true;
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isEditing = false;
  String? _testMessage;
  bool? _testSuccess;

  final _tokenCtrl = TextEditingController();
  final _chatIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final tg = TelegramBackupService.instance;
    final enabled = await tg.isEnabled();
    final token = await tg.getBotToken();
    final chat = await tg.getChatId();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _tokenCtrl.text = token;
        _chatIdCtrl.text = chat;
        _isLoading = false;
        _isEditing = token.isEmpty && chat.isEmpty;
      });
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _chatIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig({bool? forceEnabled}) async {
    final enabled = forceEnabled ?? _enabled;
    await TelegramBackupService.instance.setConfig(
      enabled: enabled,
      botToken: _tokenCtrl.text,
      chatId: _chatIdCtrl.text,
    );
  }

  Future<void> _saveSettings() async {
    final chat = _chatIdCtrl.text.trim();
    if (chat.isEmpty && _enabled) {
      FriendlyError.show(context, 'Please enter a Channel or Group ID.');
      return;
    }
    await _saveConfig();
    setState(() => _isEditing = false);
    if (mounted) {
      FriendlyError.showSuccess(context, 'Telegram settings saved successfully!');
    }
  }

  Future<void> _testAndSave() async {
    final token = _tokenCtrl.text.trim();
    final chat = _chatIdCtrl.text.trim();

    if (chat.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = 'Please enter your Telegram Channel / Group ID.';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
      _testSuccess = null;
    });

    final res = await TelegramBackupService.instance.testConnection(
      botToken: token,
      chatId: chat,
    );

    if (!mounted) return;

    if (res.success) {
      setState(() {
        _enabled = true;
        _isTesting = false;
        _isEditing = false;
        _testSuccess = true;
        _testMessage = res.message;
      });
      await _saveConfig(forceEnabled: true);
      if (mounted) {
        FriendlyError.showSuccess(context, 'Telegram storage connected! Receipts will back up automatically.');
      }
    } else {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testMessage = res.message;
      });
    }
  }

  void _showSetupGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.help_outline_rounded, color: Color(0xFF0088CC)),
          SizedBox(width: 8),
          Text('Telegram Setup Guide'),
        ]),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Store all receipt images completely free with unlimited cloud storage on Telegram:\n',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text('1. A single bot (like @Mela_platformbot) can serve multiple hotels and businesses with zero collision.'),
              SizedBox(height: 6),
              Text('2. Create a private Channel or Group for your business receipts (e.g. "My Hotel Receipts").'),
              SizedBox(height: 6),
              Text('3. Add the bot to your Channel as an Administrator with "Post Messages" permission.'),
              SizedBox(height: 6),
              Text('4. Paste your Bot Token (or platform bot) and Channel ID (@my_channel or -100...) here.'),
              SizedBox(height: 6),
              Text('5. Tap "Save" or "Test Connection" to activate!'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Panel(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0088CC).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.send_rounded, color: Color(0xFF0088CC), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Telegram Photo Storage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(
                      _enabled
                          ? 'Active · Uploads receipt photos to Telegram'
                          : 'Disabled · Free cloud image storage',
                      style: TextStyle(
                        fontSize: 12,
                        color: _enabled ? StatusColors.synced : cs.onSurfaceVariant,
                        fontWeight: _enabled ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: (val) async {
                  setState(() => _enabled = val);
                  await _saveConfig();
                },
              ),
            ],
          ),
          if (_enabled) ...[
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.hub_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Multi-Business Support: One platform bot can serve all businesses. Each business sets its own unique Channel ID with zero collision.',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tokenCtrl,
              readOnly: !_isEditing,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: 'Telegram Bot Token',
                hintText: 'Platform Bot Token or Custom Token',
                prefixIcon: const Icon(Icons.smart_toy_outlined),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      tooltip: _obscureToken ? 'Show Token' : 'Hide Token',
                      onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    ),
                    if (_isEditing)
                      IconButton(
                        icon: const Icon(Icons.paste_rounded),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _tokenCtrl.text = data!.text!.trim();
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _chatIdCtrl,
              readOnly: !_isEditing,
              decoration: InputDecoration(
                labelText: 'Channel / Group ID *',
                hintText: '@hotel_receipts or -100...',
                prefixIcon: const Icon(Icons.tag_rounded),
                suffixIcon: _isEditing
                    ? IconButton(
                        icon: const Icon(Icons.paste_rounded),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _chatIdCtrl.text = data!.text!.trim();
                          }
                        },
                      )
                    : null,
              ),
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _testSuccess == true
                      ? StatusColors.synced.withValues(alpha: 0.12)
                      : cs.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _testSuccess == true
                        ? StatusColors.synced.withValues(alpha: 0.4)
                        : cs.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess == true ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      size: 20,
                      color: _testSuccess == true ? StatusColors.synced : cs.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _testSuccess == true ? StatusColors.synced : cs.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _showSetupGuide,
                  icon: const Icon(Icons.help_outline_rounded, size: 16),
                  label: const Text('Guide'),
                ),
                if (!_isEditing) ...[
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _isEditing = true),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isTesting ? null : _testAndSave,
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_protected_setup_rounded, size: 16),
                    label: Text(_isTesting ? 'Testing…' : 'Test Connection'),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: () {
                      _loadSettings();
                      setState(() => _isEditing = false);
                    },
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testAndSave,
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_protected_setup_rounded, size: 16),
                    label: Text(_isTesting ? 'Testing…' : 'Test'),
                  ),
                  FilledButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SupportContactCard extends StatefulWidget {
  const SupportContactCard({super.key});

  @override
  State<SupportContactCard> createState() => _SupportContactCardState();
}

class _SupportContactCardState extends State<SupportContactCard> {
  PlatformConfig? _config;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await PlatformConfigService.instance.getConfig();
    if (mounted) setState(() => _config = cfg);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phone = _config?.supportPhone ?? PlatformConfigService.defaultPhone;
    final tg = _config?.supportTelegram ?? PlatformConfigService.defaultTelegram;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              const Text(
                'Super Admin Support & Renewals',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.phone_in_talk_rounded, size: 18, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phone,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.call_rounded, size: 16),
                tooltip: 'Call Support',
                onPressed: () => PlatformConfigService.instance.callPhone(phone),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy Phone',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phone));
                  FriendlyError.showSuccess(context, 'Support phone copied: $phone');
                },
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              const Icon(Icons.send_rounded, size: 18, color: Color(0xFF0088CC)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tg,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                tooltip: 'Open Telegram',
                onPressed: () => PlatformConfigService.instance.openTelegram(tg),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy Telegram',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: tg));
                  FriendlyError.showSuccess(context, 'Support Telegram copied: $tg');
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Contact for plan extensions, renewals, bank setup assistance & technical help.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

