import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/business_settings.dart';
import '../../state/business_settings_provider.dart';

class ShiftConfigDialog extends ConsumerStatefulWidget {
  const ShiftConfigDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ShiftConfigDialog(),
    );
  }

  @override
  ConsumerState<ShiftConfigDialog> createState() => _ShiftConfigDialogState();
}

class _ShiftConfigDialogState extends ConsumerState<ShiftConfigDialog> {
  late ShiftMode _shiftMode;
  late ShiftDefinition _shift1;
  late ShiftDefinition _shift2;
  late ShiftDefinition _shift3;
  late TextEditingController _contactCtrl;
  late TextEditingController _toleranceCtrl;
  late TextEditingController _highValCtrl;
  late int _rolloverHour;

  @override
  void initState() {
    super.initState();
    final s = ref.read(businessSettingsProvider);
    _shiftMode = s.shiftMode;
    _shift1 = s.shift1;
    _shift2 = s.shift2;
    _shift3 = s.shift3;
    _contactCtrl = TextEditingController(text: s.ownerReportContact);
    _toleranceCtrl = TextEditingController(text: s.varianceTolerance > 0 ? s.varianceTolerance.toStringAsFixed(0) : '0');
    _highValCtrl = TextEditingController(text: s.highValueAlertAmount.toStringAsFixed(0));
    _rolloverHour = s.businessRolloverHour;
  }

  @override
  void dispose() {
    _contactCtrl.dispose();
    _toleranceCtrl.dispose();
    _highValCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime({
    required BuildContext context,
    required TimeOfDay initial,
    required Function(TimeOfDay) onSelected,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) {
      setState(() => onSelected(picked));
    }
  }

  void _save() {
    final tol = double.tryParse(_toleranceCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
    final highVal = double.tryParse(_highValCtrl.text.replaceAll(',', '').trim()) ?? 5000.0;

    final updated = BusinessSettings(
      shiftMode: _shiftMode,
      shift1: _shift1,
      shift2: _shift2,
      shift3: _shift3,
      ownerReportContact: _contactCtrl.text.trim(),
      varianceTolerance: tol,
      highValueAlertAmount: highVal,
      businessRolloverHour: _rolloverHour,
    );

    ref.read(businessSettingsProvider.notifier).updateSettings(updated);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Shift & audit configuration saved successfully'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyboardSpace = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Shift & Audit Settings',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + keyboardSpace),
              children: [
                // 1. Shift Mode
                const Text('Shift Schedule Mode', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                for (final mode in ShiftMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _shiftMode = mode),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _shiftMode == mode
                              ? cs.primaryContainer.withValues(alpha: 0.35)
                              : cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _shiftMode == mode ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
                            width: _shiftMode == mode ? 1.8 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _shiftMode == mode ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              color: _shiftMode == mode ? cs.primary : cs.onSurfaceVariant,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  mode.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: _shiftMode == mode ? cs.primary : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(mode.subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (_shiftMode != ShiftMode.none) ...[
                  const SizedBox(height: 16),
                  const Text('Custom Shift Hours', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),

                  // Shift 1
                  _shiftTimeTile(
                    title: 'Shift 1',
                    shift: _shift1,
                    onNameChanged: (val) => _shift1 = _shift1.copyWith(name: val),
                    onStartPicked: (t) => setState(() => _shift1 = _shift1.copyWith(startHour: t.hour, startMinute: t.minute)),
                    onEndPicked: (t) => setState(() => _shift1 = _shift1.copyWith(endHour: t.hour, endMinute: t.minute)),
                    color: cs.primary,
                  ),
                  const SizedBox(height: 10),

                  // Shift 2
                  _shiftTimeTile(
                    title: 'Shift 2',
                    shift: _shift2,
                    onNameChanged: (val) => _shift2 = _shift2.copyWith(name: val),
                    onStartPicked: (t) => setState(() => _shift2 = _shift2.copyWith(startHour: t.hour, startMinute: t.minute)),
                    onEndPicked: (t) => setState(() => _shift2 = _shift2.copyWith(endHour: t.hour, endMinute: t.minute)),
                    color: const Color(0xFF0F766E),
                  ),

                  // Shift 3 (if active)
                  if (_shiftMode == ShiftMode.threeShifts) ...[
                    const SizedBox(height: 10),
                    _shiftTimeTile(
                      title: 'Shift 3',
                      shift: _shift3,
                      onNameChanged: (val) => _shift3 = _shift3.copyWith(name: val),
                      onStartPicked: (t) => setState(() => _shift3 = _shift3.copyWith(startHour: t.hour, startMinute: t.minute)),
                      onEndPicked: (t) => setState(() => _shift3 = _shift3.copyWith(endHour: t.hour, endMinute: t.minute)),
                      color: const Color(0xFF7C3AED),
                    ),
                  ],
                ],

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 14),

                // 2. Owner Report Contact (WhatsApp / Telegram)
                const Text('Owner Closing Report Recipient', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'Phone number or Telegram handle where managers send daily closing reports',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contactCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Owner Phone or Telegram Handle',
                    hintText: 'e.g. +251911223344 or @hotel_owner',
                    prefixIcon: Icon(Icons.send_rounded),
                  ),
                ),

                const SizedBox(height: 20),

                // 3. Audit Variance Tolerance
                const Text('Cash Discrepancy Tolerance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'Acceptable small difference in ETB before marking audit as unbalanced/short',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _toleranceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Variance Tolerance (ETB)',
                    hintText: '0 for strict, or e.g. 10 or 20 ETB',
                    prefixIcon: Icon(Icons.tune_rounded),
                    suffixText: 'ETB',
                  ),
                ),

                const SizedBox(height: 20),

                // 4. Night Venue Business Rollover Hour
                const Text('Night Venue Day Rollover Hour', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'For late-night bars & lounges: transactions after midnight before this hour count toward yesterday\'s night shift',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Midnight (00:00)'),
                      selected: _rolloverHour == 0,
                      onSelected: (s) => setState(() => _rolloverHour = 0),
                    ),
                    ChoiceChip(
                      label: const Text('03:00 AM (Lounges)'),
                      selected: _rolloverHour == 3,
                      onSelected: (s) => setState(() => _rolloverHour = 3),
                    ),
                    ChoiceChip(
                      label: const Text('04:00 AM (Clubs/Hotels)'),
                      selected: _rolloverHour == 4,
                      onSelected: (s) => setState(() => _rolloverHour = 4),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save Shift Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shiftTimeTile({
    required String title,
    required ShiftDefinition shift,
    required Function(String) onNameChanged,
    required Function(TimeOfDay) onStartPicked,
    required Function(TimeOfDay) onEndPicked,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
              const Spacer(),
              Text(
                shift.timeRangeString,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: shift.name,
            onChanged: onNameChanged,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              labelText: 'Shift Name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(
                    context: context,
                    initial: shift.startTime,
                    onSelected: onStartPicked,
                  ),
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(
                    'Start: ${shift.startHour.toString().padLeft(2, '0')}:${shift.startMinute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(
                    context: context,
                    initial: shift.endTime,
                    onSelected: onEndPicked,
                  ),
                  icon: const Icon(Icons.access_time_filled_rounded, size: 16),
                  label: Text(
                    'End: ${shift.endHour.toString().padLeft(2, '0')}:${shift.endMinute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
