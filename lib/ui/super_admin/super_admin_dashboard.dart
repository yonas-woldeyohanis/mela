import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config.dart';
import '../../core/friendly_error.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../services/platform_config_service.dart';
import '../settings_screen.dart';
import '../widgets.dart';

final tenantsProvider = FutureProvider.autoDispose<List<TenantOverview>>((ref) async {
  final res = await sb.rpc('super_admin_get_overview');
  List raw = [];
  if (res is Map && res['businesses'] is List) {
    raw = res['businesses'] as List;
  } else if (res is List) {
    raw = res;
  }

  // Deduplicate by business id so each registered business appears only once
  final Map<String, TenantOverview> unique = {};
  for (final item in raw) {
    if (item is Map) {
      final t = TenantOverview.fromJson(Map<String, dynamic>.from(item));
      if (!unique.containsKey(t.id)) {
        unique[t.id] = t;
      }
    }
  }
  return unique.values.toList();
});

class SuperAdminDashboardScreen extends ConsumerStatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  ConsumerState<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends ConsumerState<SuperAdminDashboardScreen> {
  String _filter = 'all'; // 'all', 'active', 'suspended'
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tenantsAsync = ref.watch(tenantsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            const Text('Super Admin Platform', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Support & Bot Config',
            icon: const Icon(Icons.support_agent_rounded),
            onPressed: () => _openPlatformSupportDialog(context),
          ),
          IconButton(
            tooltip: 'Platform Settings & Security',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Admin Settings')),
                    body: const SettingsScreen(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh Data',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(tenantsProvider),
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateBusinessDialog(context),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Register Business'),
      ),
      body: tenantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(Icons.error_outline_rounded, 'Failed to load businesses', '$e'),
        data: (tenants) {
          final activeCount = tenants.where((t) => t.isActive).length;
          final dueSoonCount = tenants.where((t) => t.isDueSoon).length;
          final overdueCount = tenants.where((t) => t.isOverdue).length;
          final pausedCount = tenants.where((t) => t.isPaused).length;
          final suspendedCount = tenants.where((t) => t.isSuspended).length;
          final totalMonthlyRevenue = tenants.where((t) => t.isActive).fold<double>(0, (a, t) => a + t.subscriptionFee);

          final filtered = tenants.where((t) {
            if (_search.isNotEmpty) {
              final q = _search.toLowerCase();
              final matchesName = t.name.toLowerCase().contains(q);
              final matchesOwner = t.ownerEmail?.toLowerCase().contains(q) ?? false;
              final matchesPhone = t.contactPhone?.contains(q) ?? false;
              if (!matchesName && !matchesOwner && !matchesPhone) return false;
            }
            if (_filter == 'active') return t.isActive;
            if (_filter == 'due_soon') return t.isDueSoon;
            if (_filter == 'overdue') return t.isOverdue;
            if (_filter == 'paused') return t.isPaused;
            if (_filter == 'suspended') return t.isSuspended;
            return true;
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              TotalHero(
                label: 'Monthly Rental Revenue',
                total: totalMonthlyRevenue,
                chips: [
                  HeroChip(Icons.domain_rounded, '${tenants.length} Total Businesses'),
                  HeroChip(Icons.check_circle_outline_rounded, '$activeCount Active Renters'),
                  if (dueSoonCount > 0)
                    HeroChip(Icons.timelapse_rounded, '$dueSoonCount Due Soon', color: const Color(0xFFF59E0B)),
                  if (overdueCount > 0)
                    HeroChip(Icons.warning_amber_rounded, '$overdueCount Overdue', color: cs.error),
                  if (pausedCount > 0)
                    HeroChip(Icons.pause_circle_outline_rounded, '$pausedCount Paused'),
                  if (suspendedCount > 0)
                    HeroChip(Icons.block_rounded, '$suspendedCount Suspended'),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar
              TextField(
                onChanged: (v) => setState(() => _search = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search business, owner, or phone...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => setState(() => _search = ''))
                      : null,
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ChoiceChip(
                    label: Text('All (${tenants.length})'),
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Active ($activeCount)'),
                    selected: _filter == 'active',
                    onSelected: (_) => setState(() => _filter = 'active'),
                  ),
                  if (dueSoonCount > 0) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Due Soon ($dueSoonCount)'),
                      selected: _filter == 'due_soon',
                      onSelected: (_) => setState(() => _filter = 'due_soon'),
                    ),
                  ],
                  if (overdueCount > 0) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Overdue ($overdueCount)'),
                      selected: _filter == 'overdue',
                      onSelected: (_) => setState(() => _filter = 'overdue'),
                    ),
                  ],
                  if (pausedCount > 0) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Paused ($pausedCount)'),
                      selected: _filter == 'paused',
                      onSelected: (_) => setState(() => _filter = 'paused'),
                    ),
                  ],
                  if (suspendedCount > 0) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Suspended ($suspendedCount)'),
                      selected: _filter == 'suspended',
                      onSelected: (_) => setState(() => _filter = 'suspended'),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 14),

              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    Icons.store_mall_directory_outlined,
                    'No businesses found',
                    'Tap "Register Business" below to onboard your first hotel, cafe or restaurant.',
                  ),
                ),

              for (final t in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    padding: const EdgeInsets.all(14),
                    color: t.isSuspended || t.isOverdue
                        ? cs.errorContainer.withValues(alpha: 0.12)
                        : (t.isPaused ? cs.surfaceContainerHighest.withValues(alpha: 0.3) : null),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          backgroundColor: t.isActive
                              ? cs.primaryContainer
                              : (t.isPaused ? cs.surfaceContainerHighest : cs.errorContainer),
                          child: Icon(
                            t.isActive
                                ? Icons.store_rounded
                                : (t.isPaused ? Icons.pause_rounded : Icons.lock_outline_rounded),
                            color: t.isActive
                                ? cs.onPrimaryContainer
                                : (t.isPaused ? cs.onSurfaceVariant : cs.onErrorContainer),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                            if (t.accountHolderName != null && t.accountHolderName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, bottom: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.account_balance_rounded, size: 13, color: cs.primary),
                                    const SizedBox(width: 4),
                                    Text('Account: ${t.accountHolderName}',
                                        style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            Text('Join Code: ${t.joinCode}  ·  Staff: ${t.staffCount}  ·  ${t.txCount} receipts',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          ]),
                        ),
                        _buildStatusPill(t, cs),
                      ]),

                      // Subscription Alerts: Overdue, Due Soon, or Paused
                      if (t.isOverdue) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Expired on ${fmtDate(t.expiresAt!)} · Overdue by ${DateTime.now().difference(t.expiresAt!).inDays} days',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.error),
                              ),
                            ),
                            if (!t.isSuspended)
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: cs.error,
                                ),
                                onPressed: () => _toggleSuspend(context, t, true),
                                child: const Text('Suspend Access', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                              ),
                          ]),
                        ),
                      ] else if (t.isDueSoon) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.notifications_active_rounded, size: 18, color: Color(0xFFD97706)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Due ${t.daysRemaining == 0 ? "today" : "in ${t.daysRemaining} days"} (${fmtDate(t.expiresAt!)})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                              ),
                            ),
                          ]),
                        ),
                      ] else if (t.isPaused) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            Icon(Icons.pause_circle_outline_rounded, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Service is currently paused by administrator.',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                        ),
                      ],

                      const Divider(height: 22),

                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Monthly Rent: ${fmtCurrency(t.subscriptionFee)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (t.expiresAt != null)
                          Text('Expires: ${fmtDateTime(t.expiresAt!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: t.isOverdue ? cs.error : cs.onSurfaceVariant,
                                fontWeight: t.isOverdue ? FontWeight.w700 : FontWeight.normal,
                              )),
                      ]),
                      if (t.ownerEmail != null) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.person_outline, size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${t.contactPerson ?? "Owner"}: ${t.ownerEmail}${t.contactPhone != null ? " · ${t.contactPhone}" : ""}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 14),

                      // Action Controls: Tier 1 (Renew & Suspend) and Tier 2 (Pause & Management)
                      Row(children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            icon: const Icon(Icons.more_time_rounded, size: 18),
                            label: const Text('Renew / Extend', maxLines: 1),
                            onPressed: () => _openRenewSubscriptionDialog(context, t),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              foregroundColor: t.isSuspended ? cs.primary : cs.error,
                            ),
                            icon: Icon(
                              t.isSuspended ? Icons.check_circle_outline_rounded : Icons.block_rounded,
                              size: 18,
                            ),
                            label: Text(t.isSuspended ? 'Restore' : 'Suspend', maxLines: 1),
                            onPressed: () => _toggleSuspend(context, t, !t.isSuspended),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                              t.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                              size: 18,
                            ),
                            label: Text(t.isPaused ? 'Resume Service' : 'Pause Service', maxLines: 1),
                            onPressed: () => _togglePause(context, t, !t.isPaused),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Edit Business',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _openEditBusinessDialog(context, t),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: 'Reset Password',
                          icon: const Icon(Icons.key_rounded, size: 18),
                          onPressed: () => _resetOwnerPasswordDialog(context, t),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: 'Delete Business',
                          style: IconButton.styleFrom(foregroundColor: cs.error),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          onPressed: () => _confirmDeleteBusiness(context, t),
                        ),
                      ]),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusPill(TenantOverview t, ColorScheme cs) {
    if (t.isSuspended) {
      return const StatusPill('SUSPENDED', StatusColors.flagged, icon: Icons.block_rounded);
    }
    if (t.isPaused) {
      return const StatusPill('PAUSED', Color(0xFF6B7280), icon: Icons.pause_circle_rounded);
    }
    if (t.isOverdue) {
      return const StatusPill('EXPIRED', StatusColors.flagged, icon: Icons.error_outline_rounded);
    }
    if (t.isDueSoon) {
      return StatusPill(
        t.daysRemaining == 0 ? 'DUE TODAY' : 'DUE IN ${t.daysRemaining}D',
        const Color(0xFFF59E0B),
        icon: Icons.timelapse_rounded,
      );
    }
    return const StatusPill('ACTIVE', StatusColors.synced, icon: Icons.check_circle_rounded);
  }

  Future<void> _toggleSuspend(BuildContext context, TenantOverview t, bool suspend) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(suspend ? 'Suspend ${t.name}?' : 'Restore ${t.name}?'),
        content: Text(suspend
            ? 'This will immediately deny system access for staff and managers of "${t.name}". Existing subscription days remain intact.'
            : 'This will restore active system access for "${t.name}". No additional subscription days are consumed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: suspend ? Theme.of(context).colorScheme.error : null,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(suspend ? 'Suspend Access' : 'Restore Access'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await sb.rpc('super_admin_set_business_status', params: {
          'p_org_id': t.id,
          'p_status': suspend ? 'suspended' : 'active',
        });
        ref.invalidate(tenantsProvider);
        if (context.mounted) {
          FriendlyError.showSuccess(
            context,
            suspend ? 'Business "${t.name}" suspended.' : 'Business "${t.name}" access restored.',
          );
        }
      } catch (e) {
        if (context.mounted) {
          FriendlyError.show(context, e, title: 'Action Failed');
        }
      }
    }
  }

  Future<void> _togglePause(BuildContext context, TenantOverview t, bool pause) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(pause ? 'Pause Service for ${t.name}?' : 'Resume Service for ${t.name}?'),
        content: Text(pause
            ? 'This temporarily freezes service for "${t.name}" (e.g. renovation or break). Staff access is paused.'
            : 'This will resume active service for "${t.name}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(pause ? 'Pause Service' : 'Resume Service'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Attempt 'paused' status; if check constraint not yet updated in DB, fallback to 'suspended'
        try {
          await sb.rpc('super_admin_set_business_status', params: {
            'p_org_id': t.id,
            'p_status': pause ? 'paused' : 'active',
          });
        } catch (_) {
          await sb.rpc('super_admin_set_business_status', params: {
            'p_org_id': t.id,
            'p_status': pause ? 'suspended' : 'active',
          });
        }
        ref.invalidate(tenantsProvider);
        if (context.mounted) {
          FriendlyError.showSuccess(
            context,
            pause ? 'Service for "${t.name}" paused.' : 'Service for "${t.name}" resumed.',
          );
        }
      } catch (e) {
        if (context.mounted) {
          FriendlyError.show(context, e, title: 'Action Failed');
        }
      }
    }
  }

  Future<void> _openRenewSubscriptionDialog(BuildContext context, TenantOverview t) async {
    int selectedDays = 30;
    final customDaysCtrl = TextEditingController(text: '30');
    bool isCustom = false;
    bool loading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final cs = Theme.of(context).colorScheme;
          final effectiveDays = isCustom ? (int.tryParse(customDaysCtrl.text.trim()) ?? 30) : selectedDays;
          final baseDate = t.isOverdue || t.expiresAt == null ? DateTime.now() : t.expiresAt!;
          final newExpiry = baseDate.add(Duration(days: effectiveDays));

          return AlertDialog(
            title: Text('Renew ${t.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Extend business subscription upon payment confirmation.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Current Expiry:', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        Text(
                          t.expiresAt != null ? fmtDate(t.expiresAt!) : 'No active date',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: t.isOverdue ? cs.error : null),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('New Expiry (+${effectiveDays}d):', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        Text(
                          fmtDate(newExpiry),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: StatusColors.synced),
                        ),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Extension Term:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('+30 Days (1 Mo)'),
                        selected: !isCustom && selectedDays == 30,
                        onSelected: (_) => setModalState(() {
                          isCustom = false;
                          selectedDays = 30;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('+60 Days (2 Mo)'),
                        selected: !isCustom && selectedDays == 60,
                        onSelected: (_) => setModalState(() {
                          isCustom = false;
                          selectedDays = 60;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('+90 Days (3 Mo)'),
                        selected: !isCustom && selectedDays == 90,
                        onSelected: (_) => setModalState(() {
                          isCustom = false;
                          selectedDays = 90;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('+180 Days (6 Mo)'),
                        selected: !isCustom && selectedDays == 180,
                        onSelected: (_) => setModalState(() {
                          isCustom = false;
                          selectedDays = 180;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('+365 Days (1 Yr)'),
                        selected: !isCustom && selectedDays == 365,
                        onSelected: (_) => setModalState(() {
                          isCustom = false;
                          selectedDays = 365;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('Custom'),
                        selected: isCustom,
                        onSelected: (_) => setModalState(() => isCustom = true),
                      ),
                    ],
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: customDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Custom Days to Add',
                        prefixIcon: Icon(Icons.date_range_rounded),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: loading ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        setModalState(() => loading = true);
                        try {
                          await sb.rpc('super_admin_set_business_status', params: {
                            'p_org_id': t.id,
                            'p_status': 'active',
                            'p_extend_days': effectiveDays,
                          });
                          ref.invalidate(tenantsProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            FriendlyError.showSuccess(
                              context,
                              'Subscription for "${t.name}" renewed (+$effectiveDays days)!',
                            );
                          }
                        } catch (e) {
                          setModalState(() => loading = false);
                          if (context.mounted) {
                            FriendlyError.show(context, e, title: 'Renewal Failed');
                          }
                        }
                      },
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Confirm Renewal (+${effectiveDays}d)'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEditBusinessDialog(BuildContext context, TenantOverview t) async {
    final nameCtrl = TextEditingController(text: t.name);
    final accountHolderCtrl = TextEditingController(text: t.accountHolderName ?? '');
    final contactPersonCtrl = TextEditingController(text: t.contactPerson ?? '');
    final contactPhoneCtrl = TextEditingController(text: t.contactPhone ?? '');
    final feeCtrl = TextEditingController(text: t.subscriptionFee.toStringAsFixed(0));
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit ${t.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Business Name', prefixIcon: Icon(Icons.storefront_rounded)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: accountHolderCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Bank Account Holder Name(s)',
                    hintText: 'e.g. BETELHEM FKADU CHALA',
                    helperText: 'Registered merchant name (prevents false fraud warnings)',
                    prefixIcon: Icon(Icons.account_balance_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactPersonCtrl,
                  decoration: const InputDecoration(labelText: 'Contact Person', prefixIcon: Icon(Icons.person_rounded)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Contact Phone', prefixIcon: Icon(Icons.phone_rounded)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: feeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Monthly Rent (ETB)', prefixIcon: Icon(Icons.attach_money_rounded)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: loading ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      setState(() => loading = true);
                      try {
                        final fee = double.tryParse(feeCtrl.text.trim()) ?? t.subscriptionFee;
                        final holder = accountHolderCtrl.text.trim();
                        try {
                          await sb.rpc('super_admin_edit_business', params: {
                            'p_org_id': t.id,
                            'p_business_name': nameCtrl.text.trim(),
                            'p_contact_person': contactPersonCtrl.text.trim(),
                            'p_contact_phone': contactPhoneCtrl.text.trim(),
                            'p_subscription_fee': fee,
                            'p_account_holder_name': holder,
                          });
                        } catch (_) {
                          await sb.rpc('super_admin_edit_business', params: {
                            'p_org_id': t.id,
                            'p_business_name': nameCtrl.text.trim(),
                            'p_contact_person': contactPersonCtrl.text.trim(),
                            'p_contact_phone': contactPhoneCtrl.text.trim(),
                            'p_subscription_fee': fee,
                          });
                        }
                        try {
                          await sb.from('organizations').update({'account_holder_name': holder}).eq('id', t.id);
                        } catch (_) {}

                        ref.invalidate(tenantsProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          FriendlyError.showSuccess(context, 'Business updated successfully!');
                        }
                      } catch (e) {
                        setState(() => loading = false);
                        if (context.mounted) {
                          FriendlyError.show(context, e, title: 'Update Failed');
                        }
                      }
                    },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteBusiness(BuildContext context, TenantOverview t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${t.name}?'),
        content: Text(
          'Warning: This will permanently delete "${t.name}", including its owner account, all staff members, and receipt records.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Permanently Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await sb.rpc('super_admin_delete_business', params: {'p_org_id': t.id});
        ref.invalidate(tenantsProvider);
        if (context.mounted) {
          FriendlyError.showSuccess(context, '"${t.name}" deleted successfully.');
        }
      } catch (e) {
        if (context.mounted) {
          FriendlyError.show(context, e, title: 'Delete Failed');
        }
      }
    }
  }

  Future<void> _resetOwnerPasswordDialog(BuildContext context, TenantOverview t) async {
    final passCtrl = TextEditingController(text: 'Pass1234');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset Password for ${t.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Owner Login: ${t.ownerEmail ?? "N/A"}'),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(labelText: 'New Temporary Password', prefixIcon: Icon(Icons.key_rounded)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await sb.rpc('super_admin_reset_owner_password', params: {
                  'p_org_id': t.id,
                  'p_owner_id': t.ownerId,
                  'p_new_temporary_password': passCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  FriendlyError.showSuccess(context, 'Password updated to "${passCtrl.text.trim()}"!');
                }
              } catch (e) {
                if (context.mounted) {
                  FriendlyError.show(context, e, title: 'Password Reset Failed');
                }
              }
            },
            child: const Text('Save Password'),
          ),
        ],
      ),
    );
  }

  Future<String?> _signupOwnerAccount(String email, String pass, String name) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('${AppConfig.supabaseUrl}/auth/v1/signup'));
      req.headers.set('apikey', AppConfig.supabaseAnonKey);
      req.headers.set('Content-Type', 'application/json');
      req.add(utf8.encode(jsonEncode({
        'email': email,
        'password': pass,
        'data': {'full_name': name, 'role': 'owner'},
      })));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final json = jsonDecode(body);
        if (json is Map) {
          final userMap = json['user'] as Map<String, dynamic>?;
          return (userMap?['id'] as String?) ?? (json['id'] as String?);
        }
        return null;
      } else if (resp.statusCode == 422) {
        // User is already registered in Auth, proceed to link
        return null;
      } else {
        final json = jsonDecode(body);
        final msg = json is Map ? (json['msg'] ?? json['message'] ?? 'Signup failed (HTTP ${resp.statusCode})') : 'Signup failed';
        throw msg.toString();
      }
    } finally {
      client.close();
    }
  }

  Future<void> _openCreateBusinessDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final accountHolderCtrl = TextEditingController();
    final ownerNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: 'Owner1234');
    final phoneCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: '1000');
    final customDaysCtrl = TextEditingController(text: '30');
    int durationDays = 30;
    bool isCustom = false;
    bool loading = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('Register Hotel / Cafe'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dialogError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.error.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dialogError!,
                              style: TextStyle(color: cs.error, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Business Name *', prefixIcon: Icon(Icons.storefront_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: accountHolderCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Bank Account Holder Name(s)',
                      hintText: 'e.g. BETELHEM FKADU CHALA (Name on slips)',
                      helperText: 'Prevents fraud warnings when customers transfer',
                      prefixIcon: Icon(Icons.account_balance_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ownerNameCtrl,
                    decoration: const InputDecoration(labelText: 'Owner Full Name *', prefixIcon: Icon(Icons.person_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Owner Email (Sign-in) *', prefixIcon: Icon(Icons.email_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(labelText: 'Temporary Password *', prefixIcon: Icon(Icons.lock_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Contact Phone', prefixIcon: Icon(Icons.phone_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: feeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Monthly Rent (ETB)', prefixIcon: Icon(Icons.attach_money_rounded)),
                  ),
                  const SizedBox(height: 14),
                  const Text('Initial Subscription Plan:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('1 Month (30d)'),
                        selected: !isCustom && durationDays == 30,
                        onSelected: (_) => setState(() {
                          isCustom = false;
                          durationDays = 30;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('3 Months (90d)'),
                        selected: !isCustom && durationDays == 90,
                        onSelected: (_) => setState(() {
                          isCustom = false;
                          durationDays = 90;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('6 Months (180d)'),
                        selected: !isCustom && durationDays == 180,
                        onSelected: (_) => setState(() {
                          isCustom = false;
                          durationDays = 180;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('1 Year (365d)'),
                        selected: !isCustom && durationDays == 365,
                        onSelected: (_) => setState(() {
                          isCustom = false;
                          durationDays = 365;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('Custom'),
                        selected: isCustom,
                        onSelected: (_) => setState(() => isCustom = true),
                      ),
                    ],
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Custom Days (e.g. 14, 60)', prefixIcon: Icon(Icons.date_range_rounded)),
                      onChanged: (v) => setState(() {
                        durationDays = int.tryParse(v.trim()) ?? 30;
                      }),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: loading ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passCtrl.text.trim().isEmpty) {
                          setState(() => dialogError = 'Please fill in Business Name, Owner Email, and Password.');
                          return;
                        }
                        setState(() {
                          loading = true;
                          dialogError = null;
                        });
                        try {
                          final fee = double.tryParse(feeCtrl.text.trim()) ?? 1000.0;
                          final email = emailCtrl.text.trim().toLowerCase();
                          final pass = passCtrl.text.trim();
                          final ownerName = ownerNameCtrl.text.trim().isNotEmpty ? ownerNameCtrl.text.trim() : 'Owner';
                          final finalDays = isCustom ? (int.tryParse(customDaysCtrl.text.trim()) ?? 30) : durationDays;

                          final accountHolder = accountHolderCtrl.text.trim();

                          // 1. Provision account via GoTrue HTTP API
                          final ownerUid = await _signupOwnerAccount(email, pass, ownerName);

                          // 2. Link business and owner in Supabase DB
                          dynamic rpcRes;
                          try {
                            rpcRes = await sb.rpc('super_admin_create_business', params: {
                              'p_business_name': nameCtrl.text.trim(),
                              'p_owner_id': ownerUid,
                              'p_owner_email': email,
                              'p_owner_name': ownerName,
                              'p_temporary_password': pass,
                              'p_contact_phone': phoneCtrl.text.trim(),
                              'p_subscription_fee': fee,
                              'p_duration_days': finalDays,
                              'p_account_holder_name': accountHolder.isNotEmpty ? accountHolder : null,
                            });
                          } catch (_) {
                            rpcRes = await sb.rpc('super_admin_create_business', params: {
                              'p_business_name': nameCtrl.text.trim(),
                              'p_owner_id': ownerUid,
                              'p_owner_email': email,
                              'p_owner_name': ownerName,
                              'p_temporary_password': pass,
                              'p_contact_phone': phoneCtrl.text.trim(),
                              'p_subscription_fee': fee,
                              'p_duration_days': finalDays,
                            });
                          }

                          if (accountHolder.isNotEmpty && rpcRes is Map && rpcRes['org_id'] != null) {
                            try {
                              await sb.from('organizations').update({'account_holder_name': accountHolder}).eq('id', rpcRes['org_id']);
                            } catch (_) {}
                          }

                          ref.invalidate(tenantsProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            FriendlyError.showSuccess(
                              context,
                              'Business "${nameCtrl.text.trim()}" onboarded successfully for $finalDays days!',
                            );
                          }
                        } catch (e) {
                          setState(() {
                            loading = false;
                            dialogError = FriendlyError.toMessage(e);
                          });
                        }
                      },
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Register & Provision'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPlatformSupportDialog(BuildContext context) async {
    final cfg = await PlatformConfigService.instance.getConfig();
    final phoneCtrl = TextEditingController(text: cfg.supportPhone);
    final tgCtrl = TextEditingController(text: cfg.supportTelegram);
    final botCtrl = TextEditingController(text: cfg.defaultBotToken);
    bool saving = false;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.support_agent_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Support & Platform Bot'),
            ]),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Control support contact information shown to business owners, and set the default bot for multi-business Telegram receipt storage.',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Support Phone Number *',
                      hintText: '0996246990',
                      prefixIcon: Icon(Icons.phone_in_talk_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Support Telegram Username *',
                      hintText: '@jonas_wjohn',
                      prefixIcon: Icon(Icons.send_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: botCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Default Platform Bot Token (Optional)',
                      hintText: 'Token from @BotFather for @Mela_platformbot',
                      helperText: 'Allows all businesses to use one bot without collision',
                      prefixIcon: Icon(Icons.smart_toy_outlined),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final phone = phoneCtrl.text.trim();
                        final tg = tgCtrl.text.trim();
                        final bot = botCtrl.text.trim();
                        if (phone.isEmpty || tg.isEmpty) {
                          FriendlyError.show(context, 'Please enter both phone and Telegram handle.');
                          return;
                        }
                        setState(() => saving = true);
                        await PlatformConfigService.instance.updateConfig(
                          phone: phone,
                          telegram: tg,
                          botToken: bot,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          FriendlyError.showSuccess(context, 'Support and platform configuration updated!');
                        }
                      },
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Settings'),
              ),
            ],
          );
        },
      ),
    );
  }
}
