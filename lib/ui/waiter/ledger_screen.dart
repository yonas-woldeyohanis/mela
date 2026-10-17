import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  int _viewMode = 0; // 0: Daily Shift List, 1: Self-Analytics & Performance

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = ref.watch(selectedDayProvider);
    final dayList = ref.watch(myReceiptsProvider(day));
    final allList = ref.watch(myAllReceiptsProvider);
    final pending = ref.watch(pendingCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            const Text('My Shift & Analytics'),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.receipt_long_rounded), label: Text('Shift Receipts')),
                ButtonSegment(value: 1, icon: Icon(Icons.insights_rounded), label: Text('My Insights')),
              ],
              selected: {_viewMode},
              onSelectionChanged: (s) => setState(() => _viewMode = s.first),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).sync(),
        child: _viewMode == 0
            ? dayList.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (rows) => _buildShiftList(context, rows, day, pending),
              )
            : allList.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (allRows) => _buildSelfAnalytics(context, allRows, cs),
              ),
      ),
    );
  }

  Widget _buildShiftList(BuildContext context, List<Receipt> rows, DateTime day, int pending) {
    final total = rows.fold<double>(0, (a, r) => a + r.amount);
    final byProvider = <String, double>{};
    for (final r in rows) {
      byProvider.update(r.provider ?? 'Other', (v) => v + r.amount, ifAbsent: () => r.amount);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DayNavigator(day: day, onChanged: (d) => ref.read(selectedDayProvider.notifier).state = d),
        TotalHero(
          label: 'Digital transfers collected',
          total: total,
          chips: [
            HeroChip(Icons.receipt_long_rounded, '${rows.length} receipts'),
            if (pending > 0) HeroChip(Icons.schedule_rounded, '$pending to sync'),
            for (final e in byProvider.entries.take(3))
              HeroChip(Icons.account_balance_wallet_outlined, '${e.key} ${fmtMoney(e.value)}'),
          ],
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(Icons.receipt_long_outlined, 'No receipts today', 'Tap the Scan tab or camera to record your first payment.'),
          ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              padding: const EdgeInsets.all(12),
              onTap: () => _detail(context, r),
              child: Row(children: [
                ProviderAvatar(r.provider),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fmtCurrency(r.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(
                      '${r.provider ?? 'Unknown'} · ${r.reference}${r.sender != null ? ' · ${r.sender}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  StatusPill.verification(r.verificationStatus),
                  const SizedBox(height: 4),
                  StatusPill.sync(r.syncStatus, r.isFlagged),
                  const SizedBox(height: 6),
                  Text(
                    '${r.tableNumber != null ? 'T${r.tableNumber} · ' : ''}${fmtTime(r.createdAt)}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ]),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildSelfAnalytics(BuildContext context, List<Receipt> all, ColorScheme cs) {
    if (all.isEmpty) {
      return const EmptyState(
        Icons.insights_outlined,
        'No historical data',
        'Your personal performance stats, hourly speed, and weekly velocity will appear once you scan receipts.',
      );
    }

    final totalVolume = all.fold<double>(0, (a, r) => a + r.amount);
    final avgTicket = totalVolume / all.length;

    // Last 7 days breakdown for the waiter
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = startOfDay(now.subtract(Duration(days: 6 - i)));
      final dayReceipts = all.where((r) => sameDay(r.createdAt, d)).toList();
      final sum = dayReceipts.fold<double>(0, (a, r) => a + r.amount);
      return {'day': d, 'sum': sum, 'count': dayReceipts.length};
    });

    // Hourly peak distribution for waiter
    final hourlySum = List<double>.filled(24, 0);
    for (final r in all) {
      hourlySum[r.createdAt.hour] += r.amount;
    }
    int bestHour = 0;
    double maxHourVal = 0;
    for (var h = 0; h < 24; h++) {
      if (hourlySum[h] > maxHourVal) {
        maxHourVal = hourlySum[h];
        bestHour = h;
      }
    }

    // Provider distribution for waiter
    final provMap = <String, double>{};
    for (final r in all) {
      provMap.update(r.provider ?? 'Other', (v) => v + r.amount, ifAbsent: () => r.amount);
    }
    final provList = provMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // Personal Performance Score Cards
        Row(children: [
          Expanded(
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.workspace_premium_rounded, size: 22, color: cs.primary),
                const SizedBox(height: 8),
                Text(fmtMoney(totalVolume), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('My Lifetime Scans (${AppConfig.currency})', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.speed_rounded, size: 22, color: cs.secondary),
                const SizedBox(height: 8),
                Text('${bestHour.toString().padLeft(2, '0')}:00', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('My Peak Rush Hour', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.query_stats_rounded, size: 22, color: cs.tertiary),
                const SizedBox(height: 8),
                Text(fmtMoney(avgTicket), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('Avg Order Size', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // 7-Day Performance Bar Chart
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('My 7-Day Shift Momentum', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('Daily digital totals collected on this device', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: BarChart(BarChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= days.length) return const SizedBox();
                        final d = days[idx]['day'] as DateTime;
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: days[i]['sum'] as double,
                        width: 18,
                        color: cs.primary,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ]),
                ],
              )),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Provider Share for this Waiter
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('My Provider Distribution', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('Breakdown of customer payments scanned by you', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            for (final p in provList.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  ProviderAvatar(p.key, size: 28),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  Text(fmtMoney(p.value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(width: 6),
                  Text('${(p.value / (totalVolume == 0 ? 1 : totalVolume) * 100).round()}%',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                ]),
              ),
          ]),
        ),
      ],
    );
  }

  void _detail(BuildContext context, Receipt r) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(fmtCurrency(r.amount), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
              StatusPill.verification(r.verificationStatus),
              const SizedBox(width: 6),
              StatusPill.sync(r.syncStatus, r.isFlagged),
            ]),
            const SizedBox(height: 12),
            _row('Reference', r.reference),
            _row('Provider', r.provider ?? '—'),
            if (r.sender != null) _row('Sender', r.sender!),
            if (r.tableNumber != null) _row('Table', r.tableNumber!),
            _row('Scanned at', '${fmtDate(r.createdAt)} · ${fmtTime(r.createdAt)}'),
            if (r.receiptTime != null) _row('Receipt timestamp', r.receiptTime!),
            if (r.receiptUrl != null && r.receiptUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF10B981),
                ),
                onPressed: () => launchUrl(Uri.parse(r.receiptUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open Official Bank Verification Slip', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 14),
            if (r.imagePath != null && File(r.imagePath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(r.imagePath!), fit: BoxFit.cover, height: 260, width: double.infinity),
              )
            else
              Text('Image purged after 7-day retention policy.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}
