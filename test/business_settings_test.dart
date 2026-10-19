import 'package:flutter_test/flutter_test.dart';
import 'package:swiftreceipt/data/business_settings.dart';

void main() {
  group('ShiftDefinition', () {
    test('containsTime handles standard daytime shift', () {
      const morning = ShiftDefinition(
        id: 'morning',
        name: 'Morning Shift',
        startHour: 6,
        startMinute: 0,
        endHour: 15,
        endMinute: 0,
      );

      expect(morning.containsTime(DateTime(2026, 10, 19, 6, 0)), isTrue);
      expect(morning.containsTime(DateTime(2026, 10, 19, 10, 30)), isTrue);
      expect(morning.containsTime(DateTime(2026, 10, 19, 14, 59)), isTrue);
      expect(morning.containsTime(DateTime(2026, 10, 19, 15, 1)), isFalse);
      expect(morning.containsTime(DateTime(2026, 10, 19, 5, 59)), isFalse);
    });

    test('containsTime handles overnight shift crossing midnight', () {
      const night = ShiftDefinition(
        id: 'night',
        name: 'Night Shift',
        startHour: 22,
        startMinute: 0,
        endHour: 6,
        endMinute: 0,
      );

      // Late night before midnight
      expect(night.containsTime(DateTime(2026, 10, 19, 22, 0)), isTrue);
      expect(night.containsTime(DateTime(2026, 10, 19, 23, 45)), isTrue);
      // Early morning after midnight
      expect(night.containsTime(DateTime(2026, 10, 19, 0, 15)), isTrue);
      expect(night.containsTime(DateTime(2026, 10, 19, 5, 30)), isTrue);
      expect(night.containsTime(DateTime(2026, 10, 19, 6, 0)), isTrue);
      // Daytime outside shift
      expect(night.containsTime(DateTime(2026, 10, 19, 12, 0)), isFalse);
      expect(night.containsTime(DateTime(2026, 10, 19, 21, 59)), isFalse);
      expect(night.containsTime(DateTime(2026, 10, 19, 6, 1)), isFalse);
    });

    test('toJson and fromMap serialization round-trip', () {
      const original = ShiftDefinition(
        id: 'afternoon',
        name: 'Afternoon Shift',
        startHour: 14,
        startMinute: 30,
        endHour: 22,
        endMinute: 0,
      );

      final map = original.toMap();
      final restored = ShiftDefinition.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.startHour, 14);
      expect(restored.startMinute, 30);
      expect(restored.endHour, 22);
      expect(restored.endMinute, 0);
    });
  });

  group('BusinessSettings', () {
    test('serializes and deserializes correctly', () {
      const settings = BusinessSettings(
        shiftMode: ShiftMode.twoShifts,
        shift1: ShiftDefinition(
          id: 's1',
          name: 'Day',
          startHour: 8,
          startMinute: 0,
          endHour: 17,
          endMinute: 0,
        ),
        shift2: ShiftDefinition(
          id: 's2',
          name: 'Night',
          startHour: 17,
          startMinute: 0,
          endHour: 2,
          endMinute: 0,
        ),
        ownerReportContact: '@manager_telegram',
        varianceTolerance: 75.0,
        highValueAlertAmount: 15000.0,
        businessRolloverHour: 4,
      );

      final jsonStr = settings.toJson();
      final decoded = BusinessSettings.fromJson(jsonStr);

      expect(decoded.shiftMode, ShiftMode.twoShifts);
      expect(decoded.shift1.name, 'Day');
      expect(decoded.shift2.name, 'Night');
      expect(decoded.ownerReportContact, '@manager_telegram');
      expect(decoded.varianceTolerance, 75.0);
      expect(decoded.highValueAlertAmount, 15000.0);
      expect(decoded.businessRolloverHour, 4);
    });

    test('activeShifts returns correct list based on shiftMode', () {
      const noneSettings = BusinessSettings(shiftMode: ShiftMode.none);
      expect(noneSettings.activeShifts.isEmpty, isTrue);

      const twoSettings = BusinessSettings(shiftMode: ShiftMode.twoShifts);
      expect(twoSettings.activeShifts.length, 2);

      const threeSettings = BusinessSettings(shiftMode: ShiftMode.threeShifts);
      expect(threeSettings.activeShifts.length, 3);
    });
  });
}
