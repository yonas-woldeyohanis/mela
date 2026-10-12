import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config.dart';
import '../../data/local_db.dart';
import '../../state/providers.dart';
import '../settings_screen.dart';
import 'ledger_screen.dart';
import 'scan_screen.dart';

class WaiterShell extends ConsumerStatefulWidget {
  const WaiterShell({super.key});
  @override
  ConsumerState<WaiterShell> createState() => _WaiterShellState();
}

class _WaiterShellState extends ConsumerState<WaiterShell> {
  int _index = 1; // Opens into My Shift Ledger first (not camera)

  @override
  void initState() {
    super.initState();
    // Startup housekeeping: purge old local images, kick the outbox worker.
    LocalDb.instance.pruneImages(DateTime.now().subtract(const Duration(days: AppConfig.retentionDays)));
    Future.microtask(() => ref.read(syncProvider.notifier).sync());
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;
    final screens = <Widget>[
      const ScanScreen(),
      const LedgerScreen(),
      Scaffold(appBar: AppBar(title: const Text('Settings')), body: const SettingsScreen(showSync: true)),
    ];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_index), child: screens[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined), selectedIcon: Icon(Icons.document_scanner_rounded), label: 'Camera'),
          NavigationDestination(
            icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.receipt_long_rounded)),
            label: 'My Shift',
          ),
          const NavigationDestination(
              icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
