import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/local_db.dart';
import '../../data/models.dart';
import '../../services/ocr_parser.dart';
import '../../services/receipt_pipeline.dart';
import '../../services/telegram_service.dart';
import '../../state/providers.dart';
import '../widgets.dart';

/// Confirm / correct the OCR result, then write instantly to the local ledger.
class ReviewSheet extends ConsumerStatefulWidget {
  const ReviewSheet({super.key, required this.imagePath, required this.parsed});
  final String imagePath;
  final ParsedReceipt parsed;
  @override
  ConsumerState<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<ReviewSheet> {
  late final _amount = TextEditingController(text: widget.parsed.amount?.toStringAsFixed(2) ?? '');
  late final _ref = TextEditingController(text: widget.parsed.reference ?? '');
  late final _table = TextEditingController();
  late final _sender = TextEditingController(text: widget.parsed.sender ?? '');
  late String? _provider = widget.parsed.provider;
  late final String? _receiptUrl = widget.parsed.receiptUrl;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_amount, _ref, _table, _sender]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final settings = ref.read(settingsProvider);
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    final rawRef = _ref.text.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (amount == null || amount <= 0) return setState(() => _error = 'Enter a valid amount.');

    final user = ref.read(authProvider)!;
    final id = const Uuid().v4();
    // Reference is optional! If user leaves it blank, generate a unique local placeholder
    final reference = rawRef.isEmpty ? 'NO-REF-${id.substring(0, 8).toUpperCase()}' : rawRef;

    setState(() {
      _saving = true;
      _error = null;
    });

    if (rawRef.isNotEmpty && await LocalDb.instance.hasReferenceToday(user.orgId, reference)) {
      if (settings.haptics) HapticFeedback.heavyImpact();
      setState(() {
        _saving = false;
        _error = 'Duplicate: reference $reference was already scanned today on this device.';
      });
      return;
    }

    // Fast-path: Check if matching bank credit was already recorded locally on this phone
    var vStatus = 'awaiting';
    if (rawRef.isNotEmpty) {
      final localCredit = await LocalDb.instance.findMatchingCredit(user.orgId, reference, amount);
      if (localCredit != null) {
        vStatus = 'verified';
      }
    }

    final path = await ReceiptPipeline.compress(widget.imagePath, id);
    final receipt = Receipt(
      localId: id,
      orgId: user.orgId,
      waiterId: user.id,
      amount: amount,
      reference: reference,
      provider: _provider,
      sender: _sender.text.trim().isEmpty ? null : _sender.text.trim(),
      tableNumber: _table.text.trim().isEmpty ? null : _table.text.trim(),
      receiptTime: widget.parsed.timeText,
      receiptUrl: _receiptUrl,
      imagePath: path,
      verificationStatus: vStatus,
      createdAt: DateTime.now(),
    );
    await LocalDb.instance.insert(receipt);

    // Queue for background Telegram Cloud backup (non-blocking, silent, retries on internet)
    TelegramBackupService.instance.queueUpload(
      localId: id,
      orgId: user.orgId,
      imagePath: path,
      amount: amount,
      reference: rawRef.isEmpty ? 'None (Cash / Manual)' : reference,
      provider: _provider ?? 'Other',
      sender: _sender.text.trim().isEmpty ? null : _sender.text.trim(),
      waiterName: user.fullName,
      orgName: user.orgName,
      receiptUrl: _receiptUrl,
    );

    if (settings.haptics) HapticFeedback.lightImpact();
    if (settings.sound) SystemSound.play(SystemSoundType.click);
    ref.read(syncProvider.notifier).sync();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalImportant = [
      _amount.text.isNotEmpty,
      _ref.text.isNotEmpty,
      _provider != null,
      _sender.text.isNotEmpty,
    ].where((e) => e).length;
    final confColor = totalImportant >= 3 ? StatusColors.synced : totalImportant >= 1 ? StatusColors.pending : StatusColors.flagged;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(widget.imagePath), width: 64, height: 84, fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Image.asset('assets/images/logo.png', width: 22, height: 22),
                    const SizedBox(width: 8),
                    Text('Confirm payment', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                StatusPill(
                  totalImportant == 4
                      ? 'All fields detected'
                      : '$totalImportant key fields detected',
                  confColor,
                  icon: totalImportant >= 3 ? Icons.auto_awesome_rounded : Icons.edit_note_rounded,
                ),
              ]),
            ),
          ]),
          // Client-side fraud / sanity check:
          Builder(builder: (ctx) {
            final user = ref.watch(authProvider);
            final warnings = <String>[];

            // 1. Check receiver name against business name & registered account holder name
            if (widget.parsed.receiver != null && user != null) {
              final rec = widget.parsed.receiver!.toLowerCase().trim();
              final org = user.orgName.toLowerCase().trim();
              final holder = (user.accountHolderName ?? '').toLowerCase().trim();

              bool matches = false;
              // Check trade / business name
              if (org.isNotEmpty && (rec.contains(org) || org.contains(rec))) {
                matches = true;
              }

              // Check registered bank / wallet account holder name(s)
              if (!matches && holder.isNotEmpty) {
                final names = holder.split(RegExp(r'[,;/]')).map((s) => s.trim()).where((s) => s.isNotEmpty);
                for (final name in names) {
                  if (rec.contains(name) || name.contains(rec)) {
                    matches = true;
                    break;
                  }
                  final recTokens = rec.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
                  final nameTokens = name.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
                  if (recTokens.intersection(nameTokens).length >= 2) {
                    matches = true;
                    break;
                  }
                }
              }

              // Fallback check against owner full name
              if (!matches && user.fullName.isNotEmpty) {
                final ownerTokens = user.fullName.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
                final recTokens = rec.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
                if (recTokens.intersection(ownerTokens).length >= 2) {
                  matches = true;
                }
              }

              if (!matches && (org.isNotEmpty || holder.isNotEmpty)) {
                final expected = holder.isNotEmpty ? '${user.orgName} (Account: $holder)' : user.orgName;
                warnings.add('Receiver mismatch: receipt states "${widget.parsed.receiver}" instead of "$expected".');
              }
            }

            // 2. Check receipt timestamp freshness (if present)
            if (widget.parsed.timeText != null) {
              final tText = widget.parsed.timeText!.toLowerCase();
              final todayStr = '${DateTime.now().year}';
              if (!tText.contains(todayStr)) {
                warnings.add('Old timestamp: Receipt date does not match current year.');
              }
            }

            if (warnings.isEmpty) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade700, width: 1.5),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.gpp_maybe_rounded, color: Colors.amber.shade700, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'Potential Fraud Warning',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Colors.amber.shade300, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    for (final w in warnings)
                      Text(w, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ]),
                ),
              ]),
            );
          }),
          if (_provider == 'Telebirr' || widget.parsed.provider == 'Telebirr') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF005DAA).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF0072CE), width: 1.5),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFF0094FF), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Telebirr Transfer Warning',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0094FF)),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Check the customer slip carefully! Make sure to place the REAL TRANSFERRED / SENT amount (what entered the hotel account), NOT the Total Paid with transfer fee or customer balance.',
                          style: TextStyle(fontSize: 12, color: Colors.white, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_receiptUrl != null && _receiptUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: Color(0xFF10B981), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Official Bank Receipt Link', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF10B981))),
                        Text(_receiptUrl!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => launchUrl(Uri.parse(_receiptUrl!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Open & Check', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Amount (Net Received)', prefixText: '${AppConfig.currency}  '),
          ),
          if (widget.parsed.netAmount != null && widget.parsed.totalPaid != null && widget.parsed.netAmount != widget.parsed.totalPaid) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                  label: Text('Net: ${widget.parsed.netAmount!.toStringAsFixed(2)} ETB (Received)'),
                  selected: _amount.text == widget.parsed.netAmount!.toStringAsFixed(2),
                  onSelected: (sel) {
                    if (sel) setState(() => _amount.text = widget.parsed.netAmount!.toStringAsFixed(2));
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.receipt_outlined, size: 16),
                  label: Text('Gross: ${widget.parsed.totalPaid!.toStringAsFixed(2)} ETB (With fee)'),
                  selected: _amount.text == widget.parsed.totalPaid!.toStringAsFixed(2),
                  onSelected: (sel) {
                    if (sel) setState(() => _amount.text = widget.parsed.totalPaid!.toStringAsFixed(2));
                  },
                ),
              ],
            ),
          ],
          if (widget.parsed.fee != null && widget.parsed.fee! > 0 && widget.parsed.totalPaid != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Customer paid ${widget.parsed.totalPaid!.toStringAsFixed(2)} ETB (${widget.parsed.fee!.toStringAsFixed(2)} ETB fee deducted). Net received: ${widget.parsed.amount!.toStringAsFixed(2)} ETB',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _ref,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
            decoration: const InputDecoration(
              labelText: 'Transaction reference (Optional)',
              hintText: 'Leave blank if cash or unreferenced',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: AppConfig.providers.contains(_provider) ? _provider : null,
            decoration: const InputDecoration(labelText: 'Bank / provider', prefixIcon: Icon(Icons.account_balance_rounded)),
            items: [for (final p in AppConfig.providers) DropdownMenuItem(value: p, child: Text(p))],
            onChanged: (v) => setState(() => _provider = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _table,
                decoration: const InputDecoration(labelText: 'Table #', prefixIcon: Icon(Icons.table_restaurant_outlined)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _sender,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Sender name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
              ]),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.check_circle_rounded),
            label: const Text('Save to ledger'),
          ),
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Discard')),
        ]),
      ),
    );
  }
}
