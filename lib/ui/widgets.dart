import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/utils.dart';

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.color, {super.key, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  factory StatusPill.sync(String status, bool flagged, {Key? key}) {
    if (flagged) return StatusPill('Flagged', StatusColors.flagged, icon: Icons.warning_amber_rounded, key: key);
    switch (status) {
      case 'synced':
        return StatusPill('Synced', StatusColors.synced, icon: Icons.cloud_done_rounded, key: key);
      case 'failed':
        return StatusPill('Failed', StatusColors.flagged, icon: Icons.error_outline_rounded, key: key);
      default:
        return StatusPill('Pending', StatusColors.pending, icon: Icons.schedule_rounded, key: key);
    }
  }

  factory StatusPill.verification(String vStatus, {Key? key}) {
    switch (vStatus.toLowerCase()) {
      case 'verified':
        return StatusPill('SMS Verified', const Color(0xFF10B981), icon: Icons.verified_rounded, key: key);
      case 'mismatch':
        return StatusPill('Amount Mismatch', const Color(0xFFEF4444), icon: Icons.gpp_bad_rounded, key: key);
      case 'unverified':
        return StatusPill('No Bank SMS', const Color(0xFFF59E0B), icon: Icons.help_outline_rounded, key: key);
      default:
        return StatusPill('Awaiting SMS', const Color(0xFF6B7280), icon: Icons.hourglass_top_rounded, key: key);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

Color providerColor(String? name) {
  const palette = [
    Color(0xFF0F766E), Color(0xFF4F46E5), Color(0xFFDB2777), Color(0xFFEA580C),
    Color(0xFF0284C7), Color(0xFF7C3AED), Color(0xFF65A30D), Color(0xFFB45309),
  ];
  if (name == null || name.isEmpty) return Colors.blueGrey;
  return palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length];
}

class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar(this.name, {super.key, this.size = 44});
  final String? name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = providerColor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(size / 3)),
      child: Text(
        (name == null || name!.isEmpty ? '?' : name!.substring(0, 1)).toUpperCase(),
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: size * 0.42),
      ),
    );
  }
}

class Panel extends StatefulWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.border});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final BoxBorder? border;

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 100), lowerBound: 0.0, upperBound: 1.0);
    _scale = Tween<double>(begin: 1.0, end: 0.985).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? (isDark ? const Color(0xFF151E2E) : Colors.white),
        borderRadius: BorderRadius.circular(22),
        border: widget.border ?? Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: widget.child,
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTapDown: (_) => _anim.forward(),
        onTapUp: (_) => _anim.reverse(),
        onTapCancel: () => _anim.reverse(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(
            scale: _scale.value,
            child: child,
          ),
          child: content,
        ),
      );
    }

    return content;
  }
}


/// Gradient hero card with a large, high-contrast currency figure.
class TotalHero extends StatelessWidget {
  const TotalHero({super.key, required this.label, required this.total, required this.chips});
  final String label;
  final double total;
  final List<Widget> chips;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.55)!],
        ),
        boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(fmtCurrency(total),
              style: TextStyle(color: cs.onPrimary, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1)),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ]),
    );
  }
}

class HeroChip extends StatelessWidget {
  const HeroChip(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: cs.onPrimary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: cs.onPrimary),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.title, this.subtitle, {super.key});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class DayNavigator extends StatelessWidget {
  const DayNavigator({super.key, required this.day, required this.onChanged});
  final DateTime day;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) {
    final today = sameDay(day, DateTime.now());
    return Row(children: [
      IconButton(
        onPressed: () => onChanged(DateTime(day.year, day.month, day.day - 1)),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(
        child: TextButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: day,
              firstDate: DateTime(2023),
              lastDate: DateTime.now(),
            );
            if (d != null) onChanged(startOfDay(d));
          },
          child: Text(today ? 'Today · ${fmtDate(day)}' : fmtDate(day),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ),
      IconButton(
        onPressed: today ? null : () => onChanged(DateTime(day.year, day.month, day.day + 1)),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ]);
  }
}
