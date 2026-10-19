import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';

enum ShiftFilter {
  allDay('All Day', null),
  morning('Day Shift', '07:00 – 15:30'),
  evening('Night Shift', '15:30 – 00:00');

  const ShiftFilter(this.label, this.timeRange);
  final String label;
  final String? timeRange;
}

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final _pos = TextEditingController();
  final _cash = TextEditingController();
  final _note = TextEditingController();

  ShiftFilter _selectedShift = ShiftFilter.allDay;
  bool _saving = false;

  // Individual waiter settlement inputs (waiterId -> billed order total controller)
  final Map<String, TextEditingController> _waiterPosCtrls = {};

  @override
  void dispose() {
    _pos.dispose();
    _cash.dispose();
    _note.dispose();
    for (final c in _waiterPosCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _val(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  List<CloudTx> _filterByShift(List<CloudTx> txs, DateTime day, ShiftFilter shift) {
    final dayRows = txs.where((t) => sameDay(t.createdAt, day)).toList();
    if (shift == ShiftFilter.allDay) return dayRows;

    return dayRows.where((t) {
      final hour = t.createdAt.hour;
      final min = t.createdAt.minute;
      final totalMins = hour * 60 + min;

      if (shift == ShiftFilter.morning) {
        return totalMins >= 7 * 60 && totalMins <= (15 * 60 + 30);
      } else {
        return totalMins > (15 * 60 + 30);
      }
    }).toList();
  }

  Future<void> _shareReport({
    required BuildContext context,
    required String orgName,
    required String managerName,
    required DateTime date,
    required ShiftFilter shift,
    required double digitalTotal,
    required double posTotal,
    required double cashTotal,
    required double diff,
    required Map<String, double> providerTotals,
    required Map<String, int> providerCounts,
    required Map<String, double> waiterTotals,
    required Map<String, int> waiterCounts,
    required Map<String, String> staffNames,
    required int verifiedCount,
    required int flaggedCount,
    String? note,
  }) async {
    final df = DateFormat('EEE, d MMM yyyy');
    final shiftStr = shift == ShiftFilter.allDay ? 'Full Day' : '${shift.label} (${shift.timeRange})';
    final varStr = diff.abs() < 0.01
        ? 'BALANCED ✅ (ETB 0.00)'
        : diff > 0
            ? 'OVER by +${fmtCurrency(diff)} ⚠️'
            : 'SHORT by -${fmtCurrency(-diff)} 🔴';

    final sb = StringBuffer();
    sb.writeln('📊 *Mela Shift Closing Report*');
    sb.writeln('🏢 *Business:* $orgName');
    sb.writeln('📅 *Date:* ${df.format(date)} · $shiftStr');
    sb.writeln('👤 *Closed by:* $managerName');
    sb.writeln();
    sb.writeln('💰 *FINANCIAL OVERVIEW*');
    sb.writeln('• Total Billed (POS):  ${fmtCurrency(posTotal)}');
    sb.writeln('• Digital Transfers:   ${fmtCurrency(digitalTotal)}');
    sb.writeln('• Cash Collected:      ${fmtCurrency(cashTotal)}');
    sb.writeln('• Shift Variance:      $varStr');
    sb.writeln();

    if (providerTotals.isNotEmpty) {
      sb.writeln('📱 *PAYMENT CHANNELS*');
      for (final e in providerTotals.entries) {
        final count = providerCounts[e.key] ?? 0;
        sb.writeln('• ${e.key}: ${fmtCurrency(e.value)} ($count tx)');
      }
      sb.writeln();
    }

    if (waiterTotals.isNotEmpty) {
      sb.writeln('👥 *STAFF COLLECTIONS*');
      for (final e in waiterTotals.entries) {
        final name = staffNames[e.key] ?? 'Staff';
        final count = waiterCounts[e.key] ?? 0;
        sb.writeln('• $name: ${fmtCurrency(e.value)} ($count receipts)');
      }
      sb.writeln();
    }

    sb.writeln('🛡️ *SECURITY & RECONCILIATION*');
    sb.writeln('• Bank SMS Verified: $verifiedCount');
    if (flaggedCount > 0) {
      sb.writeln('• Flagged / Suspicious: $flaggedCount duplicate alerts');
    } else {
      sb.writeln('• Flagged / Suspicious: 0');
    }

    if (note != null && note.isNotEmpty) {
      sb.writeln();
      sb.writeln('📝 *NOTE:* $note');
    }

    final reportText = sb.toString();

    try {
      const channel = MethodChannel('com.swiftreceipt/sms_listener');
      await channel.invokeMethod('shareText', {
        'text': reportText,
        'title': 'Share Daily Shift Closing Report',
      });
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: reportText));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift report copied to clipboard! Paste into Telegram or WhatsApp.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _close(double digital) async {
    final user = ref.read(authProvider)!;
    final day = ref.read(mgrDayProvider);
    final pos = _val(_pos), cash = _val(_cash);
    setState(() => _saving = true);
    try {
      final shiftSuffix = _selectedShift == ShiftFilter.allDay ? '' : ' [${_selectedShift.label}]';
      final noteText = '${_note.text.trim()}$shiftSuffix'.trim();

      await sb.from('audits').insert({
        'org_id': user.orgId,
        'closed_by': user.id,
        'business_date': DateFormat('yyyy-MM-dd').format(day),
        'digital_total': digital,
        'pos_total': pos,
        'cash_total': cash,
        'difference': digital + cash - pos,
        'note': noteText.isEmpty ? null : noteText,
      });
      HapticFeedback.mediumImpact();
      _pos.clear();
      _cash.clear();
      _note.clear();
      ref.invalidate(auditsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift closed and audit saved successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save audit: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(authProvider);
    final day = ref.watch(mgrDayProvider);
    final txAll = ref.watch(cloudTxProvider).valueOrNull ?? const [];
    final staffList = ref.watch(staffProvider).valueOrNull ?? const <Staff>[];
    final staffNames = {for (final s in staffList) s.id: s.fullName};

    // Filter by date and selected shift
    final filteredRows = _filterByShift(txAll, day, _selectedShift);

    final digital = filteredRows.fold<double>(0, (a, t) => a + t.amount);
    final flagged = filteredRows.where((t) => t.needsAttention).length;
    final verified = filteredRows.where((t) => t.verificationStatus.toLowerCase() == 'verified' || t.verificationStatus.toLowerCase() == 'matched').length;
    final awaiting = filteredRows.length - verified - flagged;

    // Payment provider aggregation
    final providerTotals = <String, double>{};
    final providerCounts = <String, int>{};
    for (final t in filteredRows) {
      final p = (t.provider == null || t.provider!.trim().isEmpty) ? 'Other' : t.provider!.trim();
      providerTotals[p] = (providerTotals[p] ?? 0) + t.amount;
      providerCounts[p] = (providerCounts[p] ?? 0) + 1;
    }

    // Waiter collection aggregation
    final waiterTotals = <String, double>{};
    final waiterCounts = <String, int>{};
    for (final t in filteredRows) {
      waiterTotals[t.waiterId] = (waiterTotals[t.waiterId] ?? 0) + t.amount;
      waiterCounts[t.waiterId] = (waiterCounts[t.waiterId] ?? 0) + 1;
    }

    final pos = _val(_pos), cash = _val(_cash);
    final diff = digital + cash - pos;
    final balanced = pos > 0 && diff.abs() < 0.01;
    final diffColor = pos == 0 ? cs.outline : balanced ? StatusColors.synced : diff > 0 ? StatusColors.pending : StatusColors.flagged;
    final audits = ref.watch(auditsProvider).valueOrNull ?? const [];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      DayNavigator(day: day, onChanged: (d) => ref.read(mgrDayProvider.notifier).state = d),

      // ─── 1. SHIFT SELECTOR ───
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegmentedButton<ShiftFilter>(
          segments: [
            for (final s in ShiftFilter.values)
              ButtonSegment<ShiftFilter>(
                value: s,
                label: Text(s.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                icon: Icon(
                  s == ShiftFilter.allDay ? Icons.today_rounded : s == ShiftFilter.morning ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
                  size: 16,
                ),
              ),
          ],
          selected: {_selectedShift},
          onSelectionChanged: (set) {
            setState(() => _selectedShift = set.first);
          },
        ),
      ),

      // ─── 2. SHIFT REVENUE OVERVIEW CARD ───
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedShift == ShiftFilter.allDay
                    ? 'Digitized Transfers (Full Day)'
                    : 'Transfers · ${_selectedShift.label}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              if (_selectedShift.timeRange != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _selectedShift.timeRange!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(fmtCurrency(digital), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(
            '${filteredRows.length} digital receipts recorded',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Divider(height: 24),
          // 3-way Reconciliation Health Pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _auditMetricChip(
                icon: Icons.verified_rounded,
                label: '$verified SMS Verified',
                color: StatusColors.synced,
              ),
              if (awaiting > 0)
                _auditMetricChip(
                  icon: Icons.hourglass_top_rounded,
                  label: '$awaiting Awaiting Confirmation',
                  color: StatusColors.pending,
                ),
              if (flagged > 0)
                _auditMetricChip(
                  icon: Icons.warning_amber_rounded,
                  label: '$flagged Flagged / Duplicates',
                  color: StatusColors.flagged,
                ),
            ],
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // ─── 3. PAYMENT PROVIDER BREAKDOWN CARD ───
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Payment Channel Breakdown', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text(
                '${providerTotals.length} active',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (providerTotals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('No digital transactions in this shift.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
            )
          else
            for (final entry in providerTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) ...[
              Builder(builder: (context) {
                final pName = entry.key;
                final pAmt = entry.value;
                final pCount = providerCounts[pName] ?? 0;
                final pShare = digital > 0 ? (pAmt / digital) : 0.0;
                final pColor = providerColor(pName);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      Row(children: [
                        ProviderAvatar(pName, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(pName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text('$pCount receipts · ${(pShare * 100).toStringAsFixed(0)}% of digital total',
                                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                          ]),
                        ),
                        Text(fmtCurrency(pAmt), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pShare,
                          minHeight: 5,
                          backgroundColor: cs.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(pColor),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
        ]),
      ),
      const SizedBox(height: 14),

      // ─── 4. STAFF / WAITER SETTLEMENT BREAKDOWN ───
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Waiter Shift Settlements', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text(
                '${waiterTotals.length} staff',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Calculate how much cash each waiter owes for their tables',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (waiterTotals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('No waiter transactions logged for this shift.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
            )
          else
            for (final entry in waiterTotals.entries) ...[
              Builder(builder: (context) {
                final wId = entry.key;
                final wTransfers = entry.value;
                final wCount = waiterCounts[wId] ?? 0;
                final wName = staffNames[wId] ?? 'Staff (${wId.substring(0, 5)})';

                final ctrl = _waiterPosCtrls.putIfAbsent(wId, () => TextEditingController());
                final wBilled = double.tryParse(ctrl.text.replaceAll(',', '').trim()) ?? 0.0;
                final wCashOwed = wBilled > 0 ? (wBilled - wTransfers) : 0.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: cs.primaryContainer,
                        child: Text(wName.isNotEmpty ? wName[0].toUpperCase() : 'W',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(wName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          Text('Transfers: ${fmtCurrency(wTransfers)} ($wCount tx)',
                              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: ctrl,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            labelText: 'Billed orders (POS)',
                            labelStyle: const TextStyle(fontSize: 11),
                            prefixText: 'ETB ',
                            prefixStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: wBilled == 0
                                ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
                                : wCashOwed.abs() < 0.01
                                    ? StatusColors.synced.withValues(alpha: 0.12)
                                    : wCashOwed > 0
                                        ? StatusColors.pending.withValues(alpha: 0.15)
                                        : StatusColors.flagged.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              wBilled == 0
                                  ? 'Cash to hand in'
                                  : wCashOwed.abs() < 0.01
                                      ? 'Settled (All Digital)'
                                      : wCashOwed > 0
                                          ? 'Owes Cash'
                                          : 'Surplus',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: wBilled == 0
                                    ? cs.onSurfaceVariant
                                    : wCashOwed.abs() < 0.01
                                        ? StatusColors.synced
                                        : wCashOwed > 0
                                            ? StatusColors.pending
                                            : StatusColors.flagged,
                              ),
                            ),
                            Text(
                              wBilled == 0 ? 'Enter billed' : fmtCurrency(wCashOwed > 0 ? wCashOwed : -wCashOwed),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: wBilled == 0 ? cs.onSurfaceVariant : cs.onSurface,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ]),
                  ]),
                );
              }),
            ],
        ]),
      ),
      const SizedBox(height: 14),

      // ─── 5. SHIFT RECONCILIATION & CLOSING ───
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Shift Total Reconciliation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _pos,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Total billed (POS / register / book)',
              prefixIcon: Icon(Icons.point_of_sale_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cash,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Physical cash collected in drawer',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Closing note (optional)',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 16),
          // Difference Banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: diffColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: diffColor.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Icon(
                pos == 0 ? Icons.calculate_rounded : balanced ? Icons.check_circle_rounded : diff > 0 ? Icons.info_outline_rounded : Icons.error_rounded,
                color: diffColor,
                size: 32,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    pos == 0
                        ? 'Enter the billed total'
                        : balanced
                            ? 'Balanced'
                            : diff > 0
                                ? 'Over by ${fmtCurrency(diff)}'
                                : 'Short by ${fmtCurrency(-diff)}',
                    style: TextStyle(color: diffColor, fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  Text(
                    'Transfers ${fmtMoney(digital)} + cash ${fmtMoney(cash)} vs billed ${fmtMoney(pos)}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          // Closing & Sharing Buttons
          Row(children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: _saving || pos == 0 ? null : () => _close(digital),
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock_clock_rounded, size: 18),
                label: const Text('Close Shift', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: () => _shareReport(
                  context: context,
                  orgName: user?.orgName ?? 'Restaurant',
                  managerName: user?.fullName ?? 'Manager',
                  date: day,
                  shift: _selectedShift,
                  digitalTotal: digital,
                  posTotal: pos,
                  cashTotal: cash,
                  diff: diff,
                  providerTotals: providerTotals,
                  providerCounts: providerCounts,
                  waiterTotals: waiterTotals,
                  waiterCounts: waiterCounts,
                  staffNames: staffNames,
                  verifiedCount: verified,
                  flaggedCount: flagged,
                  note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                ),
                icon: const Icon(Icons.share_rounded, size: 17),
                label: const Text('Share', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),

      // ─── 6. RECENT AUDITS HISTORY ───
      if (audits.isNotEmpty) ...[
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RECENT AUDITS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2, color: cs.primary)),
            Text('${audits.length} recorded', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        for (final a in audits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fmtDate(a.date), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        'Transfers ${fmtMoney(a.digital)} · Cash ${fmtMoney(a.cash)} · Billed ${fmtMoney(a.pos)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ]),
                  ),
                  StatusPill(
                    a.difference.abs() < 0.01 ? 'Balanced' : '${a.difference > 0 ? '+' : ''}${fmtMoney(a.difference)}',
                    a.difference.abs() < 0.01 ? StatusColors.synced : StatusColors.flagged,
                  ),
                ]),
                if (a.note != null && a.note!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Note: ${a.note}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  ),
                ],
              ]),
            ),
          ),
      ],
    ]);
  }

  Widget _auditMetricChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
