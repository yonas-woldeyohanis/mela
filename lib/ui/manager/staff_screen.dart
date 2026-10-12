import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String _filter = 'all'; // all, waiter, cashier, manager

  void _showStaffPerformance(BuildContext context, Staff s, List<CloudTx> allTx) {
    final cs = Theme.of(context).colorScheme;
    final staffTx = allTx.where((t) => t.waiterId == s.id).toList();
    final totalRevenue = staffTx.fold<double>(0, (a, b) => a + b.amount);
    final flaggedCount = staffTx.where((t) => t.isFlagged).length;

    // Daily breakdown for this staff member (last 7 days)
    final now = DateTime.now();
    final last7Days = List.generate(7, (i) {
      final day = startOfDay(now.subtract(Duration(days: 6 - i)));
      final count = staffTx.where((t) => sameDay(t.createdAt, day)).length;
      final sum = staffTx.where((t) => sameDay(t.createdAt, day)).fold<double>(0, (a, b) => a + b.amount);
      return {'day': day, 'count': count, 'sum': sum};
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  s.fullName.isEmpty ? '?' : s.fullName[0].toUpperCase(),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  StatusPill(s.role.toUpperCase(), cs.primary),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: Panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total Scanned', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(fmtMoney(totalRevenue), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(AppConfig.currency, style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Receipt Count', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('${staffTx.length}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('Transactions', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Flagged', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('$flaggedCount', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: flaggedCount > 0 ? cs.error : cs.primary)),
                    Text('Duplicates', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            const Text('Recent 7 Days Shift Activity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(children: [
                for (final d in last7Days)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Text(fmtDate(d['day'] as DateTime), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      Text('${d['count']} scans', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                      const SizedBox(width: 14),
                      Text(
                        (d['sum'] as double) > 0 ? fmtMoney(d['sum'] as double) : '-',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('Latest Receipts Scanned', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            if (staffTx.isEmpty)
              const EmptyState(Icons.receipt_long_outlined, 'No receipts yet', 'Scans by this employee will show here.')
            else
              for (final t in staffTx.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      ProviderAvatar(t.provider, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.reference, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${t.provider ?? 'Transfer'} · ${t.sender ?? 'Customer'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                      Text(fmtCurrency(t.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeStaff(BuildContext context, Staff s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${s.fullName}?'),
        content: const Text('This will revoke their access to Mela for this business.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await sb.from('profiles').delete().eq('id', s.id);
      ref.invalidate(staffProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.fullName} was removed.'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider)!;
    final staffAsync = ref.watch(staffProvider);
    final allTx = ref.watch(cloudTxProvider).valueOrNull ?? const <CloudTx>[];
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Management'),
        actions: [
          IconButton(
            tooltip: 'Copy Join Code',
            icon: const Icon(Icons.share_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: user.joinCode));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Join code ${user.joinCode} copied!'), behavior: SnackBarBehavior.floating),
              );
            },
          ),
        ],
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(Icons.error_outline, 'Could not load team', '$e'),
        data: (list) {
          final owner = list.where((s) => s.role == 'owner').firstOrNull;
          final employees = list.where((s) => s.role != 'owner').toList();
          final filtered = _filter == 'all' ? employees : employees.where((s) => s.role == _filter).toList();

          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            // Business Owner Executive Card
            if (owner != null) ...[
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.shield_rounded, color: cs.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(owner.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text('Business Owner · System Executive', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                  const StatusPill('OWNER', StatusColors.synced),
                ]),
              ),
              const SizedBox(height: 14),
            ],

            // Join Code banner
            Panel(
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.key_rounded, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Business Join Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(user.joinCode, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    Text('Give this to employees to join as waiters or cashiers', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: user.joinCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Join code copied to clipboard'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // Role filter chips for employees
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in [
                  {'id': 'all', 'label': 'Staff (${employees.length})'},
                  {'id': 'waiter', 'label': 'Waiters (${employees.where((s) => s.role == 'waiter').length})'},
                  {'id': 'cashier', 'label': 'Cashiers (${employees.where((s) => s.role == 'cashier').length})'},
                  {'id': 'manager', 'label': 'Managers (${employees.where((s) => s.role == 'manager').length})'},
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _filter == f['id'],
                      label: Text(f['label']!),
                      onSelected: (_) => setState(() => _filter = f['id']!),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),

            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No staff members in this category.\nShare the join code above to add staff.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ),
              ),

            for (final s in filtered) ...[
              Builder(builder: (ctx) {
                final staffTx = allTx.where((t) => t.waiterId == s.id);
                final revenue = staffTx.fold<double>(0, (a, b) => a + b.amount);
                final count = staffTx.length;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Text(
                            s.fullName.isEmpty ? '?' : s.fullName[0].toUpperCase(),
                            style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(
                              '$count scans · ${fmtMoney(revenue)} ${AppConfig.currency}',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          ]),
                        ),
                        if (user.isOwner && s.role != 'owner')
                          DropdownButton<String>(
                            value: s.role,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 'waiter', child: Text('Waiter')),
                              DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                              DropdownMenuItem(value: 'manager', child: Text('Manager')),
                            ],
                            onChanged: (v) async {
                              if (v == null) return;
                              try {
                                await sb.rpc('set_staff_role', params: {'target': s.id, 'new_role': v});
                                ref.invalidate(staffProvider);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
                                  );
                                }
                              }
                            },
                          )
                        else
                          StatusPill(s.role.toUpperCase(), cs.primary),
                      ]),
                      const Divider(height: 18),
                      Row(children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () => _showStaffPerformance(context, s, allTx),
                          icon: const Icon(Icons.analytics_outlined, size: 18),
                          label: const Text('View Stats & Shifts'),
                        ),
                        const Spacer(),
                        if (user.isOwner && s.role != 'owner')
                          IconButton(
                            iconSize: 20,
                            tooltip: 'Remove employee',
                            color: cs.error,
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _removeStaff(context, s),
                          ),
                      ]),
                    ]),
                  ),
                );
              }),
            ],
          ]);
        },
      ),
    );
  }
}
