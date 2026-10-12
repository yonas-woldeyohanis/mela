import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'state/providers.dart';
import 'state/security_provider.dart';
import 'ui/auth_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/manager/manager_shell.dart';
import 'ui/splash_screen.dart';
import 'ui/super_admin/super_admin_dashboard.dart';
import 'ui/waiter/waiter_shell.dart';

class MelaApp extends ConsumerStatefulWidget {
  const MelaApp({super.key});

  @override
  ConsumerState<MelaApp> createState() => _MelaAppState();
}

class _MelaAppState extends ConsumerState<MelaApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Mela',
      debugShowCheckedModeBanner: false,
      themeMode: s.themeMode,
      theme: buildTheme(Brightness.light, seeds[s.seed]),
      darkTheme: buildTheme(Brightness.dark, seeds[s.seed]),
      home: _showSplash
          ? SplashScreen(onFinished: () => setState(() => _showSplash = false))
          : (AppConfig.configured ? const Gate() : const SetupScreen()),
    );
  }
}

class Gate extends ConsumerWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final sec = ref.watch(securityProvider);

    if (user != null && sec.isLocked) {
      return const LockScreen(key: ValueKey('lock_screen'));
    }

    if (user == null) {
      return const AuthScreen(key: ValueKey('auth'));
    }

    // 1. Super Admin Portal
    if (user.isSuperAdmin) {
      return const SuperAdminDashboardScreen(key: ValueKey('super_admin'));
    }

    // 2. Suspended / Expired Business Denial Guard
    if (user.isSuspended) {
      return const SuspendedAccessScreen(key: ValueKey('suspended'));
    }

    // 3. Regular Owner/Manager or Waiter
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: user.isManager
          ? const ManagerShell(key: ValueKey('manager'))
          : const WaiterShell(key: ValueKey('waiter')),
    );
  }
}

class SuspendedAccessScreen extends ConsumerWidget {
  const SuspendedAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_clock_rounded, size: 64, color: cs.onErrorContainer),
              ),
              const SizedBox(height: 24),
              Text(
                'Service Suspended',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'The subscription for "${user?.orgName ?? "your business"}" is currently inactive or overdue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  const Text('To renew your service, please contact platform support:',
                      textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.phone_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    const SelectableText('+251 911 000 000', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ]),
                ]),
              ),
              const SizedBox(height: 32),
              FilledButton.tonalIcon(
                onPressed: () => ref.read(authProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Check Status Again'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(authProvider.notifier).signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.settings_suggest_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Connect Supabase', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text('Run the app with your project keys:\n'),
              const SelectableText(
                'flutter run \\\n  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \\\n  --dart-define=SUPABASE_ANON_KEY=your-anon-key',
                style: TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              const Text('See README.md for the full setup guide.'),
            ]),
          ),
        ),
      );
}
