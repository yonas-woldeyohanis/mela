import 'dart:convert';
import 'package:flutter/material.dart';

enum ShiftMode {
  none('Single Full Day (No Shifts)', 'Hospitality locations with single daily closing'),
  twoShifts('2 Shifts (Day & Night)', 'Standard restaurant with lunch & dinner staff rotations'),
  threeShifts('3 Shifts (Morning, Afternoon, Night)', '24/7 hotels, airport cafes, and round-the-clock lounges');

  const ShiftMode(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

class ShiftDefinition {
  const ShiftDefinition({
    required this.id,
    required this.name,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  final String id;
  final String name;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  String get timeRangeString {
    final sH = startHour.toString().padLeft(2, '0');
    final sM = startMinute.toString().padLeft(2, '0');
    final eH = endHour.toString().padLeft(2, '0');
    final eM = endMinute.toString().padLeft(2, '0');
    return '$sH:$sM – $eH:$eM';
  }

  TimeOfDay get startTime => TimeOfDay(hour: startHour, minute: startMinute);
  TimeOfDay get endTime => TimeOfDay(hour: endHour, minute: endMinute);

  bool containsTime(DateTime dt) {
    final currentMins = dt.hour * 60 + dt.minute;
    final startMins = startHour * 60 + startMinute;
    final endMins = endHour * 60 + endMinute;

    if (startMins <= endMins) {
      return currentMins >= startMins && currentMins <= endMins;
    } else {
      // Overnight shift (e.g. 22:00 to 06:00)
      return currentMins >= startMins || currentMins <= endMins;
    }
  }

  ShiftDefinition copyWith({
    String? name,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
  }) {
    return ShiftDefinition(
      id: id,
      name: name ?? this.name,
      startHour: startHour ?? this.startHour,
      startMinute: startMinute ?? this.startMinute,
      endHour: endHour ?? this.endHour,
      endMinute: endMinute ?? this.endMinute,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start_hour': startHour,
        'start_minute': startMinute,
        'end_hour': endHour,
        'end_minute': endMinute,
      };

  factory ShiftDefinition.fromMap(Map<String, dynamic> m) => ShiftDefinition(
        id: (m['id'] as String?) ?? 'shift',
        name: (m['name'] as String?) ?? 'Shift',
        startHour: (m['start_hour'] as num?)?.toInt() ?? 7,
        startMinute: (m['start_minute'] as num?)?.toInt() ?? 0,
        endHour: (m['end_hour'] as num?)?.toInt() ?? 15,
        endMinute: (m['end_minute'] as num?)?.toInt() ?? 30,
      );
}

class BusinessSettings {
  const BusinessSettings({
    this.shiftMode = ShiftMode.twoShifts,
    this.shift1 = const ShiftDefinition(
      id: 'shift_1',
      name: 'Day Shift',
      startHour: 7,
      startMinute: 0,
      endHour: 15,
      endMinute: 30,
    ),
    this.shift2 = const ShiftDefinition(
      id: 'shift_2',
      name: 'Night Shift',
      startHour: 15,
      startMinute: 30,
      endHour: 23,
      endMinute: 59,
    ),
    this.shift3 = const ShiftDefinition(
      id: 'shift_3',
      name: 'Late Shift',
      startHour: 23,
      startMinute: 0,
      endHour: 7,
      endMinute: 0,
    ),
    this.ownerReportContact = '',
    this.varianceTolerance = 0.0,
    this.highValueAlertAmount = 5000.0,
    this.businessRolloverHour = 0,
  });

  final ShiftMode shiftMode;
  final ShiftDefinition shift1;
  final ShiftDefinition shift2;
  final ShiftDefinition shift3;
  final String ownerReportContact; // phone or @handle
  final double varianceTolerance;
  final double highValueAlertAmount;
  final int businessRolloverHour; // 0 for midnight, 3 or 4 for late-night lounges

  List<ShiftDefinition> get activeShifts {
    switch (shiftMode) {
      case ShiftMode.none:
        return const [];
      case ShiftMode.twoShifts:
        return [shift1, shift2];
      case ShiftMode.threeShifts:
        return [shift1, shift2, shift3];
    }
  }

  BusinessSettings copyWith({
    ShiftMode? shiftMode,
    ShiftDefinition? shift1,
    ShiftDefinition? shift2,
    ShiftDefinition? shift3,
    String? ownerReportContact,
    double? varianceTolerance,
    double? highValueAlertAmount,
    int? businessRolloverHour,
  }) {
    return BusinessSettings(
      shiftMode: shiftMode ?? this.shiftMode,
      shift1: shift1 ?? this.shift1,
      shift2: shift2 ?? this.shift2,
      shift3: shift3 ?? this.shift3,
      ownerReportContact: ownerReportContact ?? this.ownerReportContact,
      varianceTolerance: varianceTolerance ?? this.varianceTolerance,
      highValueAlertAmount: highValueAlertAmount ?? this.highValueAlertAmount,
      businessRolloverHour: businessRolloverHour ?? this.businessRolloverHour,
    );
  }

  Map<String, dynamic> toMap() => {
        'shift_mode': shiftMode.name,
        'shift_1': shift1.toMap(),
        'shift_2': shift2.toMap(),
        'shift_3': shift3.toMap(),
        'owner_report_contact': ownerReportContact,
        'variance_tolerance': varianceTolerance,
        'high_value_alert_amount': highValueAlertAmount,
        'business_rollover_hour': businessRolloverHour,
      };

  factory BusinessSettings.fromMap(Map<String, dynamic> m) {
    ShiftMode mode = ShiftMode.twoShifts;
    final modeStr = m['shift_mode'] as String?;
    if (modeStr != null) {
      for (final sm in ShiftMode.values) {
        if (sm.name == modeStr) {
          mode = sm;
          break;
        }
      }
    }

    return BusinessSettings(
      shiftMode: mode,
      shift1: m['shift_1'] is Map<String, dynamic>
          ? ShiftDefinition.fromMap(m['shift_1'] as Map<String, dynamic>)
          : const ShiftDefinition(id: 'shift_1', name: 'Day Shift', startHour: 7, startMinute: 0, endHour: 15, endMinute: 30),
      shift2: m['shift_2'] is Map<String, dynamic>
          ? ShiftDefinition.fromMap(m['shift_2'] as Map<String, dynamic>)
          : const ShiftDefinition(id: 'shift_2', name: 'Night Shift', startHour: 15, startMinute: 30, endHour: 23, endMinute: 59),
      shift3: m['shift_3'] is Map<String, dynamic>
          ? ShiftDefinition.fromMap(m['shift_3'] as Map<String, dynamic>)
          : const ShiftDefinition(id: 'shift_3', name: 'Late Shift', startHour: 23, startMinute: 0, endHour: 7, endMinute: 0),
      ownerReportContact: (m['owner_report_contact'] as String?) ?? '',
      varianceTolerance: (m['variance_tolerance'] as num?)?.toDouble() ?? 0.0,
      highValueAlertAmount: (m['high_value_alert_amount'] as num?)?.toDouble() ?? 5000.0,
      businessRolloverHour: (m['business_rollover_hour'] as num?)?.toInt() ?? 0,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory BusinessSettings.fromJson(String str) => BusinessSettings.fromMap(jsonDecode(str) as Map<String, dynamic>);
}
