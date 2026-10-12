import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../services/notification_service.dart';
import '../../state/providers.dart';
import '../settings_screen.dart';
import 'audit_screen.dart';
import 'insights_screen.dart';
import 'live_feed_screen.dart';
import 'staff_screen.dart';

class ManagerShell extends ConsumerStatefulWidget {
  const ManagerShell({super.key});
  @override
  ConsumerState<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends ConsumerState<ManagerShell> {
  int _index = 0;
  final _seen = <String>{};
  final _alerted = <String>{};
  bool _primed = false;

  static const _titles = ['Live feed', 'Insights', 'End-of-day audit', 'Settings'];

  /// Realtime → local notification (with sound). The first emission only primes
  /// the seen-set so opening the app doesn't replay the whole day.
  void _onRows(List<CloudTx> rows) {
    final names = {for (final s in ref.read(staffProvider).valueOrNull ?? const <Staff>[]) s.id: s.fullName};
    final settings = ref.read(settingsProvider);
    final newest = rows.reversed;
    for (final t in newest) {
      final isNew = _seen.add(t.id);
      final who = names[t.waiterId] ?? 'Staff';
      if (_primed && isNew) {
        NotificationService.instance.show(
          'New payment · ${fmtCurrency(t.amount)}',
          '$who · ${t.provider ?? 'Transfer'} · ${t.reference}',
        );
        if (settings.haptics) HapticFeedback.mediumImpact();
      }
      if (t.needsAttention && _alerted.add(t.id) && _primed) {
        NotificationService.instance.show(
          'Duplicate reference flagged',
          '${fmtCurrency(t.amount)} · ${t.reference} · scanned by $who',
          alert: true,
        );
      } else if (!_primed && t.needsAttention) {
        _alerted.add(t.id);
      }
    }
    _primed = true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<CloudTx>>>(cloudTxProvider, (_, next) => next.whenData(_onRows));
    final user = ref.watch(authProvider)!;
    final flagged = ref.watch(cloudTxProvider).maybeWhen(
        data: (l) => l.where((t) => t.needsAttention && sameDay(t.createdAt, DateTime.now())).length, orElse: () => 0);

    final screens = <Widget>[
      const LiveFeedScreen(),
      const InsightsScreen(),
      const AuditScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (user.isManager)
            IconButton(
              tooltip: 'Team',
              icon: const Icon(Icons.groups_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffScreen())),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_index), child: screens[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Badge(isLabelVisible: flagged > 0, label: Text('$flagged'), child: const Icon(Icons.bolt_outlined)),
            selectedIcon: Badge(isLabelVisible: flagged > 0, label: Text('$flagged'), child: const Icon(Icons.bolt_rounded)),
            label: 'Live',
          ),
          const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Insights'),
          const NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check_rounded), label: 'Audit'),
          const NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
