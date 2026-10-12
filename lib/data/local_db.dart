import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../core/utils.dart';
import 'models.dart';

/// Reactive local SQLite store (the offline shift ledger + sync outbox).
class LocalDb {
  LocalDb._();
  static final instance = LocalDb._();

  Database? _db;
  final _changes = StreamController<void>.broadcast();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'swiftreceipt.db'),
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE receipts(
            local_id TEXT PRIMARY KEY,
            org_id TEXT NOT NULL,
            waiter_id TEXT NOT NULL,
            table_number TEXT,
            amount REAL NOT NULL,
            reference_number TEXT NOT NULL,
            payment_provider TEXT,
            sender_name TEXT,
            receipt_time TEXT,
            image_path TEXT,
            image_url TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            verification_status TEXT NOT NULL DEFAULT 'awaiting',
            is_flagged INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_ref ON receipts(org_id, reference_number)');
        await db.execute('CREATE INDEX idx_day ON receipts(waiter_id, created_at)');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          try {
            await db.execute("ALTER TABLE receipts ADD COLUMN verification_status TEXT NOT NULL DEFAULT 'awaiting'");
          } catch (_) {}
        }
      },
    );
    return _db!;
  }

  void _notify() => _changes.add(null);

  Future<void> insert(Receipt r) async {
    final db = await _database;
    await db.insert('receipts', r.toMap());
    _notify();
  }

  Future<List<Receipt>> forDay(String waiterId, DateTime day) async {
    final db = await _database;
    final s = startOfDay(day);
    final e = DateTime(s.year, s.month, s.day + 1);
    final rows = await db.query(
      'receipts',
      where: 'waiter_id = ? AND created_at >= ? AND created_at < ?',
      whereArgs: [waiterId, s.millisecondsSinceEpoch, e.millisecondsSinceEpoch],
      orderBy: 'created_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  Stream<List<Receipt>> watchDay(String waiterId, DateTime day) async* {
    yield await forDay(waiterId, day);
    await for (final _ in _changes.stream) {
      yield await forDay(waiterId, day);
    }
  }

  Future<List<Receipt>> allForWaiter(String waiterId) async {
    final db = await _database;
    final rows = await db.query(
      'receipts',
      where: 'waiter_id = ?',
      whereArgs: [waiterId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Receipt.fromMap).toList();
  }

  Stream<List<Receipt>> watchAllForWaiter(String waiterId) async* {
    yield await allForWaiter(waiterId);
    await for (final _ in _changes.stream) {
      yield await allForWaiter(waiterId);
    }
  }

  Stream<int> watchPendingCount(String waiterId) async* {
    Future<int> q() async {
      final db = await _database;
      final r = await db.rawQuery(
        "SELECT COUNT(*) FROM receipts WHERE waiter_id = ? AND sync_status = 'pending'",
        [waiterId],
      );
      return Sqflite.firstIntValue(r) ?? 0;
    }

    yield await q();
    await for (final _ in _changes.stream) {
      yield await q();
    }
  }

  /// Duplicate guard: same reference already scanned today on this device.
  Future<bool> hasReferenceToday(String orgId, String reference) async {
    final db = await _database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) FROM receipts WHERE org_id = ? AND reference_number = ? AND created_at >= ?',
      [orgId, reference, startOfDay(DateTime.now()).millisecondsSinceEpoch],
    );
    return (Sqflite.firstIntValue(r) ?? 0) > 0;
  }

  Future<List<Receipt>> pending(String waiterId) async {
    final db = await _database;
    final rows = await db.query('receipts',
        where: "waiter_id = ? AND sync_status = 'pending'", whereArgs: [waiterId], orderBy: 'created_at ASC');
    return rows.map(Receipt.fromMap).toList();
  }

  Future<void> markSynced(String localId, String? imageUrl, bool flagged, {String verificationStatus = 'awaiting'}) async {
    final db = await _database;
    await db.update(
      'receipts',
      {
        'sync_status': 'synced',
        'image_url': imageUrl,
        'is_flagged': flagged ? 1 : 0,
        'verification_status': verificationStatus,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    _notify();
  }

  Future<void> markFailed(String localId) async {
    final db = await _database;
    await db.update('receipts', {'sync_status': 'failed'}, where: 'local_id = ?', whereArgs: [localId]);
    _notify();
  }

  /// Retention (client side): delete image files older than [cutoff] for rows
  /// that are already synced. Text records are kept forever.
  Future<int> pruneImages(DateTime cutoff) async {
    final db = await _database;
    final rows = await db.query(
      'receipts',
      columns: ['local_id', 'image_path'],
      where: "created_at < ? AND image_path IS NOT NULL AND sync_status != 'pending'",
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
    for (final r in rows) {
      try {
        final f = File(r['image_path'] as String);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      await db.update('receipts', {'image_path': null}, where: 'local_id = ?', whereArgs: [r['local_id']]);
    }
    if (rows.isNotEmpty) _notify();
    return rows.length;
  }
}
