import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});
  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _days = 7; // default to 7 days for rich trend view
  int _chartTab = 0; // 0: Trends & Peaks, 1: Provider & Velocity, 2: Radar & Health

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txAsync = ref.watch(cloudTxProvider);
    final staffListRaw = ref.watch(staffProvider).valueOrNull ?? const <Staff>[];
    final staffNames = {for (final s in staffListRaw) s.id: s.fullName};

    return txAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(Icons.cloud_off_rounded, 'Insights unavailable', '$e'),
      data: (all) {
        final since = DateTime.now().subtract(Duration(days: _days - 1));
        final from = startOfDay(since);
        final rows = all.where((t) => !t.createdAt.isBefore(from)).toList();

        // Previous period calculation for % growth comparison
        final prevFrom = startOfDay(from.subtract(Duration(days: _days)));
        final prevRows = all.where((t) => !t.createdAt.isBefore(prevFrom) && t.createdAt.isBefore(from)).toList();
        final prevTotal = prevRows.fold<double>(0, (a, t) => a + t.amount);

        final total = rows.fold<double>(0, (a, t) => a + t.amount);
        final flaggedRows = rows.where((t) => t.isFlagged).toList();
        final flaggedAmount = flaggedRows.fold<double>(0, (a, t) => a + t.amount);

        // Revenue Growth %
        double? growthPct;
        if (prevTotal > 0) {
          growthPct = ((total - prevTotal) / prevTotal) * 100;
        }

        // Daily aggregated revenue (for Trend Line Chart)
        final dailyMap = <DateTime, double>{};
        final dailyCountMap = <DateTime, int>{};
        for (var i = 0; i < _days; i++) {
          final d = startOfDay(since.add(Duration(days: i)));
          dailyMap[d] = 0.0;
          dailyCountMap[d] = 0;
        }
        for (final t in rows) {
          final d = startOfDay(t.createdAt);
          if (dailyMap.containsKey(d)) {
            dailyMap[d] = (dailyMap[d] ?? 0) + t.amount;
            dailyCountMap[d] = (dailyCountMap[d] ?? 0) + 1;
          }
        }
        final dailyEntries = dailyMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

        // Group by staff
        final byStaff = <String, double>{};
        final staffCount = <String, int>{};
        for (final t in rows) {
          final name = staffNames[t.waiterId] ?? 'Staff';
          byStaff.update(name, (v) => v + t.amount, ifAbsent: () => t.amount);
          staffCount.update(name, (v) => v + 1, ifAbsent: () => 1);
        }
        final staffRank = byStaff.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        // Group by provider
        final byProvider = <String, double>{};
        for (final t in rows) {
          byProvider.update(t.provider ?? 'Other', (v) => v + t.amount, ifAbsent: () => t.amount);
        }
        final provList = byProvider.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        // Hourly distribution
        final byHour = List<double>.filled(24, 0);
        final byHourCount = List<int>.filled(24, 0);
        for (final t in rows) {
          byHour[t.createdAt.hour] += t.amount;
          byHourCount[t.createdAt.hour] += 1;
        }
        int peakHour = 0;
        double maxHourVal = 0;
        for (var h = 0; h < 24; h++) {
          if (byHour[h] > maxHourVal) {
            maxHourVal = byHour[h];
            peakHour = h;
          }
        }

        // Ticket size distributions (Bucketing)
        var microCount = 0; // < 100 ETB
        var smallCount = 0; // 100 - 500 ETB
        var medCount = 0;   // 500 - 2,000 ETB
        var largeCount = 0; // > 2,000 ETB
        for (final t in rows) {
          if (t.amount < 100) {
            microCount++;
          } else if (t.amount <= 500) {
            smallCount++;
          } else if (t.amount <= 2000) {
            medCount++;
          } else {
            largeCount++;
          }
        }

        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          // Time range selector
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 1, label: Text('Today')),
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 30, label: Text('30 days')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
          const SizedBox(height: 14),

          // Primary Executive KPI Cards
          Row(children: [
            Expanded(
              child: _kpi(
                context,
                'Total Volume',
                fmtMoney(total),
                Icons.payments_rounded,
                subtext: growthPct != null
                    ? '${growthPct >= 0 ? '+' : ''}${growthPct.toStringAsFixed(1)}% vs prev'
                    : '${AppConfig.currency} net',
                subColor: growthPct != null ? (growthPct >= 0 ? Colors.green : cs.error) : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpi(
                context,
                'Scanned Receipts',
                '${rows.length}',
                Icons.receipt_long_rounded,
                subtext: rows.isEmpty ? '0/day' : '${(rows.length / _days).toStringAsFixed(1)} avg/day',
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _kpi(
                context,
                'Avg Ticket',
                rows.isEmpty ? '0' : fmtMoney(total / rows.length),
                Icons.query_stats_rounded,
                subtext: 'per transaction',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpi(
                context,
                'Peak Hour',
                rows.isEmpty ? 'None' : '${peakHour.toString().padLeft(2, '0')}:00',
                Icons.access_time_filled_rounded,
                subtext: maxHourVal > 0 ? fmtMoney(maxHourVal) : 'No transactions',
                subColor: cs.tertiary,
              ),
            ),
          ]),
          if (flaggedRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            Panel(
              color: cs.errorContainer.withValues(alpha: 0.4),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: cs.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${flaggedRows.length} duplicate/flagged receipts detected',
                        style: TextStyle(fontWeight: FontWeight.w700, color: cs.onErrorContainer)),
                    Text('Totaling ${fmtCurrency(flaggedAmount)} requiring manager audit',
                        style: TextStyle(fontSize: 12, color: cs.onErrorContainer.withValues(alpha: 0.8))),
                  ]),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),

          // Sub-Tab Switcher for Specialized Visualizations
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Trends & Peaks')),
              ButtonSegment(value: 1, label: Text('Providers & Ticket')),
              ButtonSegment(value: 2, label: Text('Staff Radar & Health')),
            ],
            selected: {_chartTab},
            onSelectionChanged: (s) => setState(() => _chartTab = s.first),
          ),
          const SizedBox(height: 16),

          if (rows.isEmpty)
            const EmptyState(Icons.insights_outlined, 'No data in this period', 'Sync your first receipt to generate business intelligence.')
          else if (_chartTab == 0) ...[
            // ─── TAB 0: TRENDS & PEAKS ───
            _card(
              context,
              'Daily Revenue Momentum',
              subtitle: 'Track digital income flow over time',
              child: SizedBox(
                height: 220,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, top: 10),
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.25), strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            getTitlesWidget: (val, meta) => Text(
                              val >= 1000 ? '${(val / 1000).toStringAsFixed(1)}k' : val.toInt().toString(),
                              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, meta) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= dailyEntries.length) return const SizedBox();
                              if (_days > 7 && idx % (_days ~/ 5) != 0 && idx != dailyEntries.length - 1) return const SizedBox();
                              final date = dailyEntries[idx].key;
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          isCurved: true,
                          curveSmoothness: 0.35,
                          color: cs.primary,
                          barWidth: 3.5,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: _days <= 7),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [cs.primary.withValues(alpha: 0.35), cs.primary.withValues(alpha: 0.0)],
                            ),
                          ),
                          spots: [
                            for (var i = 0; i < dailyEntries.length; i++)
                              FlSpot(i.toDouble(), dailyEntries[i].value),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _card(
              context,
              'Hourly Rush Hours (24h Heatmap)',
              subtitle: 'Identify when staff needs maximum coverage',
              child: SizedBox(
                height: 190,
                child: BarChart(BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, meta) => v.toInt() % 3 == 0
                            ? SideTitleWidget(axisSide: meta.axisSide, child: Text('${v.toInt()}h', style: const TextStyle(fontSize: 10)))
                            : const SizedBox(),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var h = 0; h < 24; h++)
                      BarChartGroupData(x: h, barRods: [
                        BarChartRodData(
                          toY: byHour[h],
                          width: 8,
                          color: h == peakHour && byHour[h] > 0
                              ? cs.tertiary
                              : cs.primary.withValues(alpha: byHour[h] > 0 ? 0.75 : 0.15),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ]),
                  ],
                )),
              ),
            ),
          ] else if (_chartTab == 1) ...[
            // ─── TAB 1: PROVIDERS & TICKET SIZE ───
            _card(
              context,
              'Payment Provider Market Share',
              subtitle: 'Telebirr, CBE Birr & Banking splits',
              child: Row(children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: PieChart(PieChartData(
                    sectionsSpace: 2.5,
                    centerSpaceRadius: 36,
                    sections: [
                      for (final e in provList)
                        PieChartSectionData(
                          value: e.value,
                          color: providerColor(e.key),
                          title: '',
                          radius: 26,
                        ),
                    ],
                  )),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(children: [
                    for (final e in provList.take(6))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: providerColor(e.key), shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                          Text(fmtMoney(e.value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          const SizedBox(width: 6),
                          Text('${(e.value / (total == 0 ? 1 : total) * 100).round()}%',
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            _card(
              context,
              'Customer Ticket Size Distribution',
              subtitle: 'Spend concentration per customer order',
              child: Column(children: [
                _ticketRow(context, '< 100 ETB (Micro)', microCount, rows.length, cs.primary),
                _ticketRow(context, '100 – 500 ETB (Standard)', smallCount, rows.length, cs.secondary),
                _ticketRow(context, '500 – 2,000 ETB (Medium)', medCount, rows.length, cs.tertiary),
                _ticketRow(context, '> 2,000 ETB (VIP / Large)', largeCount, rows.length, Colors.deepPurple),
              ]),
            ),
          ] else ...[
            // ─── TAB 2: RADAR & OPERATIONAL HEALTH ───
            _card(
              context,
              'Multi-Axis Cafe Performance Radar',
              subtitle: 'Volume, Speed, Staff Balance, Provider Diversity, Cleanliness',
              child: Center(
                child: SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _CafeRadarPainter(
                      labels: const ['Revenue', 'Peak Speed', 'Staff Share', 'Diversity', 'No Dups'],
                      values: [
                        math.min(1.0, total / (5000 * _days)),
                        math.min(1.0, maxHourVal / (total == 0 ? 1 : total * 0.4)),
                        math.min(1.0, (staffRank.length >= 3 ? 1.0 : staffRank.length * 0.33)),
                        math.min(1.0, provList.length / 4.0),
                        flaggedRows.isEmpty ? 1.0 : math.max(0.2, 1.0 - (flaggedRows.length / rows.length)),
                      ],
                      primaryColor: cs.primary,
                      gridColor: cs.outlineVariant.withValues(alpha: 0.3),
                      labelColor: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _card(
              context,
              'Staff Contribution Leaderboard',
              subtitle: 'Scanned volume and receipt throughput per employee',
              child: Column(children: [
                for (var i = 0; i < staffRank.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == 0 ? Colors.amber.shade700 : cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Text('${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: i == 0 ? Colors.white : cs.onSurface,
                            )),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(staffRank[i].key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : staffRank[i].value / total,
                              minHeight: 6,
                              backgroundColor: cs.outlineVariant.withValues(alpha: 0.2),
                              color: cs.primary,
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(fmtMoney(staffRank[i].value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        Text('${staffCount[staffRank[i].key] ?? 0} scans', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                      ]),
                    ]),
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }

  Widget _ticketRow(BuildContext context, String label, int count, int total, Color color) {
    final pct = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Text('$count orders (${(pct * 100).round()}%)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 7,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ]),
    );
  }

  Widget _kpi(BuildContext context, String label, String value, IconData icon, {String? subtext, Color? subColor}) {
    final cs = Theme.of(context).colorScheme;
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: cs.primary),
          const Spacer(),
          if (subtext != null)
            Text(subtext, style: TextStyle(color: subColor ?? cs.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]),
    );
  }

  Widget _card(BuildContext context, String title, {required Widget child, String? subtitle}) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          child,
        ]),
      );
}

/// Custom Canvas Painter rendering a 5-point radar/spider chart
class _CafeRadarPainter extends CustomPainter {
  _CafeRadarPainter({
    required this.labels,
    required this.values,
    required this.primaryColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<String> labels;
  final List<double> values;
  final Color primaryColor, gridColor, labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2.6;
    final sides = labels.length;
    final angleStep = (2 * math.pi) / sides;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Draw concentric polygon rings (25%, 50%, 75%, 100%)
    for (var step = 1; step <= 4; step++) {
      final r = radius * (step / 4);
      final ringPath = Path();
      for (var i = 0; i < sides; i++) {
        final angle = i * angleStep - (math.pi / 2);
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle);
        if (i == 0) {
          ringPath.moveTo(x, y);
        } else {
          ringPath.lineTo(x, y);
        }
      }
      ringPath.close();
      canvas.drawPath(ringPath, gridPaint);
    }

    // Draw axis lines and labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < sides; i++) {
      final angle = i * angleStep - (math.pi / 2);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      canvas.drawLine(center, Offset(x, y), gridPaint);

      // Label at tip
      final labelX = center.dx + (radius + 20) * math.cos(angle);
      final labelY = center.dy + (radius + 14) * math.sin(angle);
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w700),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(labelX - textPainter.width / 2, labelY - textPainter.height / 2));
    }

    // Draw data polygon
    final polyPath = Path();
    for (var i = 0; i < sides; i++) {
      final val = (i < values.length ? values[i] : 0.5).clamp(0.1, 1.0);
      final r = radius * val;
      final angle = i * angleStep - (math.pi / 2);
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        polyPath.moveTo(x, y);
      } else {
        polyPath.lineTo(x, y);
      }
    }
    polyPath.close();

    final fillPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawPath(polyPath, fillPaint);

    final linePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(polyPath, linePaint);

    // Draw vertex dots
    final dotPaint = Paint()..color = primaryColor;
    for (var i = 0; i < sides; i++) {
      final val = (i < values.length ? values[i] : 0.5).clamp(0.1, 1.0);
      final r = radius * val;
      final angle = i * angleStep - (math.pi / 2);
      canvas.drawCircle(Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle)), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CafeRadarPainter old) => true;
}
