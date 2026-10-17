import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class LiveFeedScreen extends ConsumerStatefulWidget {
  const LiveFeedScreen({super.key});
  @override
  ConsumerState<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends ConsumerState<LiveFeedScreen> {
  bool _flaggedOnly = false;
  String? _staffId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = ref.watch(mgrDayProvider);
    final tx = ref.watch(cloudTxProvider);
    final staff = ref.watch(staffProvider).valueOrNull ?? const <Staff>[];
    final names = {for (final s in staff) s.id: s.fullName};

    final isOffline = ref.watch(isCloudOfflineProvider);

    return tx.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: Color(0xFFF59E0B)),
              const SizedBox(height: 16),
              const Text(
                'You are currently offline',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Transactions will update automatically once reconnected to Wi-Fi or mobile data.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry Connection'),
                onPressed: () => ref.invalidate(cloudTxProvider),
              ),
            ],
          ),
        ),
      ),
      data: (all) {
        final dayRows = all.where((t) => sameDay(t.createdAt, day)).toList();
        final rows = dayRows
            .where((t) => !_flaggedOnly || t.needsAttention)
            .where((t) => _staffId == null || t.waiterId == _staffId)
            .toList();
        final total = dayRows.fold<double>(0, (a, t) => a + t.amount);
        final attention = dayRows.where((t) => t.needsAttention).length;
        final active = dayRows.map((t) => t.waiterId).toSet().length;

        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          DayNavigator(day: day, onChanged: (d) => ref.read(mgrDayProvider.notifier).state = d),
          if (isOffline)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Offline mode · Showing cached transactions',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B)),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => ref.invalidate(cloudTxProvider),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(children: [
                      Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFF59E0B)),
                      SizedBox(width: 4),
                      Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                    ]),
                  ),
                ),
              ]),
            ),
          TotalHero(
            label: 'Digital revenue',
            total: total,
            chips: [
              HeroChip(Icons.receipt_long_rounded, '${dayRows.length} receipts'),
              HeroChip(Icons.people_alt_rounded, '$active staff active'),
              if (attention > 0) HeroChip(Icons.warning_amber_rounded, '$attention flagged'),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilterChip(
                label: const Text('Flagged only'),
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                selected: _flaggedOnly,
                onSelected: (v) => setState(() => _flaggedOnly = v),
              ),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('All staff'), selected: _staffId == null, onSelected: (_) => setState(() => _staffId = null)),
              for (final s in staff.where((s) => s.role != 'manager' && s.role != 'owner')) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(s.fullName.split(' ').first),
                  selected: _staffId == s.id,
                  onSelected: (_) => setState(() => _staffId = _staffId == s.id ? null : s.id),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(Icons.bolt_outlined, 'Nothing here yet', 'New scans appear instantly as staff capture them.'),
            ),
          for (final t in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                padding: const EdgeInsets.all(12),
                color: t.needsAttention
                    ? StatusColors.flagged.withValues(alpha: 0.07)
                    : (t.verificationStatus == 'mismatch'
                        ? StatusColors.flagged.withValues(alpha: 0.05)
                        : (t.verificationStatus == 'verified' ? StatusColors.synced.withValues(alpha: 0.04) : null)),
                onTap: () => _detail(context, t, names[t.waiterId] ?? 'Staff'),
                child: Row(children: [
                  ProviderAvatar(t.provider),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fmtCurrency(t.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      Text('${names[t.waiterId] ?? 'Staff'}${t.tableNumber != null ? ' · Table ${t.tableNumber}' : ''}',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      Text(
                        t.reference.startsWith('NO-REF') ? 'None (Cash / Manual)' : t.reference,
                        style: TextStyle(
                          color: t.reference.startsWith('NO-REF') ? cs.onSurfaceVariant.withValues(alpha: 0.7) : cs.onSurfaceVariant,
                          fontStyle: t.reference.startsWith('NO-REF') ? FontStyle.italic : FontStyle.normal,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (t.needsAttention)
                      const StatusPill('Flagged', StatusColors.flagged, icon: Icons.warning_amber_rounded)
                    else
                      StatusPill.verification(t.verificationStatus),
                    const SizedBox(height: 6),
                    Text(fmtTime(t.createdAt), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  void _detail(BuildContext context, CloudTx t, String who) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(fmtCurrency(t.amount), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
              if (t.needsAttention) ...[
                const StatusPill('Flagged', StatusColors.flagged, icon: Icons.warning_amber_rounded),
                const SizedBox(width: 6),
              ],
              StatusPill.verification(t.verificationStatus),
            ]),
            const SizedBox(height: 12),
            _row('Reference', t.reference),
            _row('Provider', t.provider ?? '—'),
            _row('Verification', t.verificationStatus.toUpperCase()),
            _row('Provider', t.provider ?? '—'),
            _row('Staff', who),
            _row('Table', t.tableNumber ?? '—'),
            _row('Sender', t.sender ?? '—'),
            _row('Scanned', fmtDateTime(t.createdAt)),
            if (t.receiptUrl != null && t.receiptUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF10B981),
                ),
                onPressed: () => launchUrl(Uri.parse(t.receiptUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open Official Bank Verification Slip', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
            if (t.needsAttention) ...[
              const SizedBox(height: 14),
              const Text('Another receipt with the same reference exists. Check both photos before dismissing.',
                  style: TextStyle(color: StatusColors.flagged, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await sb.from('transactions').update({'flag_resolved': true}).eq('id', t.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.verified_rounded),
                label: const Text('Mark as reviewed'),
              ),
            ],
            const SizedBox(height: 16),
            _image(t),
          ]),
        ),
      ),
    );
  }

  Widget _image(CloudTx t) {
    final path = t.imageUrl;
    if (path == null) return const Text('No photo attached.');
    if (path == AppConfig.purged) {
      return const Panel(
        child: Row(children: [
          Icon(Icons.auto_delete_rounded),
          SizedBox(width: 12),
          Expanded(child: Text('Photo removed after the 7-day retention window. The transaction record is kept.')),
        ]),
      );
    }
    return FutureBuilder<String>(
      future: sb.storage.from(AppConfig.receiptsBucket).createSignedUrl(path, 300),
      builder: (context, snap) {
        if (snap.hasError) return const Text('Photo could not be loaded.');
        if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(snap.data!, fit: BoxFit.cover,
              loadingBuilder: (c, w, p) => p == null ? w : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))),
        );
      },
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 96, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}
