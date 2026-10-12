import 'package:intl/intl.dart';
import 'config.dart';

final _money = NumberFormat('#,##0.00');
String fmtMoney(num v) => _money.format(v);
String fmtCurrency(num v) => '${AppConfig.currency} ${fmtMoney(v)}';
String fmtTime(DateTime d) => DateFormat('HH:mm').format(d.toLocal());
String fmtDate(DateTime d) => DateFormat('EEE, d MMM').format(d.toLocal());
String fmtDateTime(DateTime d) => DateFormat('d MMM, HH:mm').format(d.toLocal());
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}
