import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/friendly_error.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../settings_screen.dart';
import '../widgets.dart';

final tenantsProvider = FutureProvider.autoDispose<List<TenantOverview>>((ref) async {
  final res = await sb.rpc('super_admin_get_overview');
  if (res is Map && res['businesses'] is List) {
    final list = res['businesses'] as List;
    return list.map((e) => TenantOverview.fromJson(e as Map<String, dynamic>)).toList();
  }
  if (res is List) {
    return res.map((e) => TenantOverview.fromJson(e as Map<String, dynamic>)).toList();
  }
  return [];
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
        title: const Text('Super Admin Platform', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
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
          final suspendedCount = tenants.where((t) => t.isSuspended || t.isExpired).length;
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
            if (_filter == 'suspended') return !t.isActive;
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
                  if (suspendedCount > 0)
                    HeroChip(Icons.block_rounded, '$suspendedCount Suspended / Expired'),
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
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Suspended / Expired ($suspendedCount)'),
                    selected: _filter == 'suspended',
                    onSelected: (_) => setState(() => _filter = 'suspended'),
                  ),
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
                    color: !t.isActive ? cs.errorContainer.withValues(alpha: 0.15) : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          backgroundColor: t.isActive ? cs.primaryContainer : cs.errorContainer,
                          child: Icon(
                            t.isActive ? Icons.store_rounded : Icons.lock_outline_rounded,
                            color: t.isActive ? cs.onPrimaryContainer : cs.onErrorContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                            Text('Join Code: ${t.joinCode}  ·  Staff: ${t.staffCount}  ·  ${t.txCount} receipts',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          ]),
                        ),
                        StatusPill(
                          t.status.toUpperCase(),
                          t.isActive ? StatusColors.synced : StatusColors.flagged,
                          icon: t.isActive ? Icons.check_circle_rounded : Icons.block_rounded,
                        ),
                      ]),
                      const Divider(height: 22),

                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Monthly Rent: ${fmtCurrency(t.subscriptionFee)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (t.expiresAt != null)
                          Text('Expires: ${fmtDateTime(t.expiresAt!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: t.isExpired ? cs.error : cs.onSurfaceVariant,
                                fontWeight: t.isExpired ? FontWeight.w700 : FontWeight.normal,
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

                      // Action Controls: Suspend/Activate, Edit, Reset Password, Delete
                      Row(children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              foregroundColor: t.isActive ? cs.error : cs.primary,
                            ),
                            onPressed: () => _toggleTenantStatus(context, t),
                            icon: Icon(t.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded, size: 18),
                            label: Text(t.isActive ? 'Suspend Access' : 'Activate (+30 Days)'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Edit Business',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _openEditBusinessDialog(context, t),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Reset Owner Password',
                          icon: const Icon(Icons.key_rounded, size: 18),
                          onPressed: () => _resetOwnerPasswordDialog(context, t),
                        ),
                        const SizedBox(width: 6),
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

  Future<void> _toggleTenantStatus(BuildContext context, TenantOverview t) async {
    final newStatus = t.isActive ? 'suspended' : 'active';
    final extendDays = t.isActive ? null : 30;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.isActive ? 'Suspend ${t.name}?' : 'Activate ${t.name}?'),
        content: Text(t.isActive
            ? 'This will immediately deny access for all staff and managers of "${t.name}" until payment is received.'
            : 'This will activate the business for 30 days and restore staff access.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.isActive ? 'Suspend Access' : 'Activate (+30 Days)'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await sb.rpc('super_admin_set_business_status', params: {
          'p_org_id': t.id,
          'p_status': newStatus,
          if (extendDays != null) 'p_extend_days': extendDays,
        });
        ref.invalidate(tenantsProvider);
        if (context.mounted) {
          FriendlyError.showSuccess(context, t.isActive ? 'Business suspended.' : 'Business activated (+30 days).');
        }
      } catch (e) {
        if (context.mounted) {
          FriendlyError.show(context, e, title: 'Action Failed');
        }
      }
    }
  }

  Future<void> _openEditBusinessDialog(BuildContext context, TenantOverview t) async {
    final nameCtrl = TextEditingController(text: t.name);
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
                        await sb.rpc('super_admin_edit_business', params: {
                          'p_org_id': t.id,
                          'p_business_name': nameCtrl.text.trim(),
                          'p_contact_person': contactPersonCtrl.text.trim(),
                          'p_contact_phone': contactPhoneCtrl.text.trim(),
                          'p_subscription_fee': fee,
                        });
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
    if (t.ownerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Owner record not found.')));
      return;
    }
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

  Future<void> _openCreateBusinessDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final ownerNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: 'Owner1234');
    final phoneCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: '1000');
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Register Hotel / Cafe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Business Name *', prefixIcon: Icon(Icons.storefront_rounded)),
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
                        FriendlyError.show(context, 'Please fill in all required fields (Business Name, Owner Email, Password).');
                        return;
                      }
                      setState(() => loading = true);
                      try {
                        final fee = double.tryParse(feeCtrl.text.trim()) ?? 1000.0;
                        await sb.rpc('super_admin_create_business', params: {
                          'p_business_name': nameCtrl.text.trim(),
                          'p_owner_email': emailCtrl.text.trim(),
                          'p_owner_name': ownerNameCtrl.text.trim().isNotEmpty ? ownerNameCtrl.text.trim() : 'Owner',
                          'p_temporary_password': passCtrl.text.trim(),
                          'p_contact_phone': phoneCtrl.text.trim(),
                          'p_subscription_fee': fee,
                          'p_duration_days': 30,
                        });
                        ref.invalidate(tenantsProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          FriendlyError.showSuccess(
                            context,
                            'Business "${nameCtrl.text.trim()}" onboarded successfully!',
                          );
                        }
                      } catch (e) {
                        setState(() => loading = false);
                        if (context.mounted) {
                          FriendlyError.show(context, e, title: 'Registration Failed');
                        }
                      }
                    },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Register & Provision'),
            ),
          ],
        ),
      ),
    );
  }
}
