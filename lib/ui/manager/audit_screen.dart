import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final _pos = TextEditingController();
  final _cash = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _pos.dispose();
    _cash.dispose();
    _note.dispose();
    super.dispose();
  }

  double _val(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  Future<void> _close(double digital) async {
    final user = ref.read(authProvider)!;
    final day = ref.read(mgrDayProvider);
    final pos = _val(_pos), cash = _val(_cash);
    setState(() => _saving = true);
    try {
      await sb.from('audits').insert({
        'org_id': user.orgId,
        'closed_by': user.id,
        'business_date': DateFormat('yyyy-MM-dd').format(day),
        'digital_total': digital,
        'pos_total': pos,
        'cash_total': cash,
        'difference': digital + cash - pos,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      HapticFeedback.mediumImpact();
      _pos.clear();
      _cash.clear();
      _note.clear();
      ref.invalidate(auditsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Shift closed and audit saved'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save audit: $e'), behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = ref.watch(mgrDayProvider);
    final tx = ref.watch(cloudTxProvider).valueOrNull ?? const [];
    final dayRows = tx.where((t) => sameDay(t.createdAt, day)).toList();
    final digital = dayRows.fold<double>(0, (a, t) => a + t.amount);
    final flagged = dayRows.where((t) => t.needsAttention).length;
    final pos = _val(_pos), cash = _val(_cash);
    final diff = digital + cash - pos;
    final balanced = pos > 0 && diff.abs() < 0.01;
    final diffColor = pos == 0 ? cs.outline : balanced ? StatusColors.synced : StatusColors.flagged;
    final audits = ref.watch(auditsProvider).valueOrNull ?? const [];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      DayNavigator(day: day, onChanged: (d) => ref.read(mgrDayProvider.notifier).state = d),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Digitized transfers', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(fmtCurrency(digital), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          Text('${dayRows.length} receipts${flagged > 0 ? ' · $flagged flagged duplicates' : ''}',
              style: TextStyle(color: flagged > 0 ? StatusColors.flagged : cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pos,
        onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Total billed (POS / order book)', prefixIcon: Icon(Icons.point_of_sale_rounded)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _cash,
        onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Physical cash collected', prefixIcon: Icon(Icons.payments_outlined)),
      ),
      const SizedBox(height: 12),
      TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)', prefixIcon: Icon(Icons.notes_rounded))),
      const SizedBox(height: 16),
      AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: diffColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: diffColor.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(pos == 0 ? Icons.calculate_rounded : balanced ? Icons.check_circle_rounded : Icons.error_rounded, color: diffColor, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pos == 0 ? 'Enter the billed total' : balanced ? 'Balanced' : diff > 0 ? 'Over by ${fmtCurrency(diff)}' : 'Short by ${fmtCurrency(-diff)}',
                  style: TextStyle(color: diffColor, fontWeight: FontWeight.w800, fontSize: 18)),
              Text('Transfers ${fmtMoney(digital)} + cash ${fmtMoney(cash)} vs billed ${fmtMoney(pos)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _saving || pos == 0 ? null : () => _close(digital),
        icon: _saving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
            : const Icon(Icons.lock_clock_rounded),
        label: const Text('Close shift & save audit'),
      ),
      if (audits.isNotEmpty) ...[
        const SizedBox(height: 28),
        Text('RECENT AUDITS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2, color: cs.primary)),
        const SizedBox(height: 10),
        for (final a in audits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fmtDate(a.date), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('Transfers ${fmtMoney(a.digital)} · Cash ${fmtMoney(a.cash)} · Billed ${fmtMoney(a.pos)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ]),
                ),
                StatusPill(a.difference.abs() < 0.01 ? 'Balanced' : '${a.difference > 0 ? '+' : ''}${fmtMoney(a.difference)}',
                    a.difference.abs() < 0.01 ? StatusColors.synced : StatusColors.flagged),
              ]),
            ),
          ),
      ],
    ]);
  }
}
