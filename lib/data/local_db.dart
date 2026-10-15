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
      version: 3,
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

        await db.execute('''
          CREATE TABLE IF NOT EXISTS local_bank_credits(
            id TEXT PRIMARY KEY,
            org_id TEXT NOT NULL,
            reference_number TEXT NOT NULL,
            amount REAL NOT NULL,
            provider TEXT,
            sender_name TEXT,
            receiver_phone TEXT,
            balance REAL,
            raw_sms TEXT NOT NULL,
            received_at INTEGER NOT NULL,
            synced_to_cloud INTEGER NOT NULL DEFAULT 0,
            matched_local_id TEXT
          )''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_lbc_ref ON local_bank_credits(org_id, reference_number)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_lbc_time ON local_bank_credits(received_at)');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS cached_cloud_tx(
            id TEXT PRIMARY KEY,
            org_id TEXT NOT NULL,
            waiter_id TEXT NOT NULL,
            table_number TEXT,
            amount REAL NOT NULL,
            reference_number TEXT NOT NULL,
            payment_provider TEXT,
            sender_name TEXT,
            image_url TEXT,
            sync_status TEXT,
            verification_status TEXT,
            is_flagged INTEGER NOT NULL DEFAULT 0,
            flag_resolved INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_cctx_org_time ON cached_cloud_tx(org_id, created_at DESC)');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS telegram_queue(
            local_id TEXT PRIMARY KEY,
            org_id TEXT NOT NULL,
            image_path TEXT NOT NULL,
            caption TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            retries INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          try {
            await db.execute("ALTER TABLE receipts ADD COLUMN verification_status TEXT NOT NULL DEFAULT 'awaiting'");
          } catch (_) {}
        }
        if (oldV < 3) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS local_bank_credits(
                id TEXT PRIMARY KEY,
                org_id TEXT NOT NULL,
                reference_number TEXT NOT NULL,
                amount REAL NOT NULL,
                provider TEXT,
                sender_name TEXT,
                receiver_phone TEXT,
                balance REAL,
                raw_sms TEXT NOT NULL,
                received_at INTEGER NOT NULL,
                synced_to_cloud INTEGER NOT NULL DEFAULT 0,
                matched_local_id TEXT
              )''');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_lbc_ref ON local_bank_credits(org_id, reference_number)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_lbc_time ON local_bank_credits(received_at)');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS cached_cloud_tx(
                id TEXT PRIMARY KEY,
                org_id TEXT NOT NULL,
                waiter_id TEXT NOT NULL,
                table_number TEXT,
                amount REAL NOT NULL,
                reference_number TEXT NOT NULL,
                payment_provider TEXT,
                sender_name TEXT,
                image_url TEXT,
                sync_status TEXT,
                verification_status TEXT,
                is_flagged INTEGER NOT NULL DEFAULT 0,
                flag_resolved INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
              )''');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_cctx_org_time ON cached_cloud_tx(org_id, created_at DESC)');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS telegram_queue(
                local_id TEXT PRIMARY KEY,
                org_id TEXT NOT NULL,
                image_path TEXT NOT NULL,
                caption TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                retries INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
              )''');
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

  // ───────────────────────── Local Bank Credits Store ─────────────────────────

  /// Saves incoming bank SMS credit locally on device (persisted for 3+ days).
  Future<void> saveLocalBankCredit({
    required String id,
    required String orgId,
    required String reference,
    required double amount,
    String? provider,
    String? senderName,
    String? receiverPhone,
    double? balance,
    required String rawSms,
    required DateTime receivedAt,
    bool syncedToCloud = false,
  }) async {
    final db = await _database;
    await db.insert(
      'local_bank_credits',
      {
        'id': id,
        'org_id': orgId,
        'reference_number': reference.trim().toUpperCase(),
        'amount': amount,
        'provider': provider,
        'sender_name': senderName,
        'receiver_phone': receiverPhone,
        'balance': balance,
        'raw_sms': rawSms,
        'received_at': receivedAt.millisecondsSinceEpoch,
        'synced_to_cloud': syncedToCloud ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Finds if a matching bank credit exists locally from the last 3 days.
  Future<Map<String, dynamic>?> findMatchingCredit(String orgId, String reference, double amount) async {
    if (reference.isEmpty || reference.startsWith('NO-REF')) return null;
    final db = await _database;
    final cleanRef = reference.trim().toUpperCase();
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    final rows = await db.query(
      'local_bank_credits',
      where: 'org_id = ? AND reference_number = ? AND received_at >= ?',
      whereArgs: [orgId, cleanRef, threeDaysAgo],
      orderBy: 'received_at DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final r = rows.first;
      final creditAmount = (r['amount'] as num).toDouble();
      final diff = (creditAmount - amount).abs();
      // 1. Exact amount match (within 5 cents)
      if (diff < 0.05) {
        return r;
      }
      // 2. Smart fee tolerance:
      // If the reference matches, and the scanned amount is higher by a known transfer fee tier (0.50 to 20.00 ETB)
      // e.g. receipt recorded gross 51.00 ETB while bank SMS recorded net 50.00 ETB
      if (amount > creditAmount && (amount - creditAmount) <= 20.0) {
        return r;
      }
    }
    return null;
  }

  /// Get all unsynced local bank credits to upload to Supabase
  Future<List<Map<String, dynamic>>> getUnsyncedBankCredits() async {
    final db = await _database;
    return await db.query(
      'local_bank_credits',
      where: 'synced_to_cloud = 0',
      orderBy: 'received_at ASC',
    );
  }

  Future<void> markBankCreditSynced(String id) async {
    final db = await _database;
    await db.update('local_bank_credits', {'synced_to_cloud': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ───────────────────────── Cloud Transactions Cache ─────────────────────────

  Future<void> cacheCloudTransactions(String orgId, List<CloudTx> list) async {
    final db = await _database;
    final batch = db.batch();
    for (final tx in list) {
      batch.insert(
        'cached_cloud_tx',
        tx.toDbMap(orgId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CloudTx>> getCachedCloudTransactions(String orgId) async {
    final db = await _database;
    final rows = await db.query(
      'cached_cloud_tx',
      where: 'org_id = ?',
      whereArgs: [orgId],
      orderBy: 'created_at DESC',
      limit: 600,
    );
    return rows.map(CloudTx.fromDbMap).toList();
  }

  // ───────────────────────── Telegram Backup Queue ─────────────────────────

  Future<void> queueTelegramUpload({
    required String localId,
    required String orgId,
    required String imagePath,
    required String caption,
  }) async {
    final db = await _database;
    await db.insert(
      'telegram_queue',
      {
        'local_id': localId,
        'org_id': orgId,
        'image_path': imagePath,
        'caption': caption,
        'status': 'pending',
        'retries': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingTelegramUploads() async {
    final db = await _database;
    return await db.query(
      'telegram_queue',
      where: "status = 'pending' AND retries < 5",
      orderBy: 'created_at ASC',
      limit: 5,
    );
  }

  Future<void> markTelegramUploaded(String localId) async {
    final db = await _database;
    await db.delete('telegram_queue', where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<void> incrementTelegramRetry(String localId) async {
    final db = await _database;
    await db.rawUpdate(
      'UPDATE telegram_queue SET retries = retries + 1 WHERE local_id = ?',
      [localId],
    );
  }
}
