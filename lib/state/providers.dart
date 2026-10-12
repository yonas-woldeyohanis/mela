import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../data/local_db.dart';
import '../data/models.dart';
import '../services/notification_service.dart';

SupabaseClient get sb => Supabase.instance.client;

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

// ───────────────────────── Settings ─────────────────────────
class AppSettings {
  const AppSettings({required this.themeMode, required this.seed, required this.sound, required this.haptics});
  final ThemeMode themeMode;
  final int seed;
  final bool sound, haptics;
  AppSettings copyWith({ThemeMode? themeMode, int? seed, bool? sound, bool? haptics}) => AppSettings(
        themeMode: themeMode ?? this.themeMode,
        seed: seed ?? this.seed,
        sound: sound ?? this.sound,
        haptics: haptics ?? this.haptics,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final p = ref.read(prefsProvider);
    final s = AppSettings(
      themeMode: ThemeMode.values[(p.getInt('theme') ?? 0).clamp(0, 2)],
      seed: (p.getInt('seed') ?? 0).clamp(0, seeds.length - 1),
      sound: p.getBool('sound') ?? true,
      haptics: p.getBool('haptics') ?? true,
    );
    NotificationService.instance.sound = s.sound;
    return s;
  }

  void setTheme(ThemeMode m) {
    ref.read(prefsProvider).setInt('theme', m.index);
    state = state.copyWith(themeMode: m);
  }

  void setSeed(int i) {
    ref.read(prefsProvider).setInt('seed', i);
    state = state.copyWith(seed: i);
  }

  void setSound(bool v) {
    ref.read(prefsProvider).setBool('sound', v);
    NotificationService.instance.sound = v;
    state = state.copyWith(sound: v);
  }

  void setHaptics(bool v) {
    ref.read(prefsProvider).setBool('haptics', v);
    state = state.copyWith(haptics: v);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ───────────────────────── Auth ─────────────────────────
class AuthNotifier extends Notifier<AppUser?> {
  static const _cacheKey = 'cached_user';
  StreamSubscription<AuthState>? _sub;

  @override
  AppUser? build() {
    _sub = sb.auth.onAuthStateChange.listen((e) {
      if (e.event == AuthChangeEvent.signedOut) {
        ref.read(prefsProvider).remove(_cacheKey);
        state = null;
      }
    });
    ref.onDispose(() => _sub?.cancel());

    final session = sb.auth.currentSession;
    final raw = ref.read(prefsProvider).getString(_cacheKey);
    AppUser? cached;
    if (session != null && raw != null) {
      try {
        final u = AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (u.id == session.user.id) cached = u;
      } catch (_) {}
    }
    if (session != null) Future.microtask(refresh);
    return cached;
  }

  /// Re-fetch the profile (works offline thanks to the cached copy).
  Future<void> refresh() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await sb
          .from('profiles')
          .select('id, org_id, full_name, role, organizations(name, join_code, status, expires_at)')
          .eq('id', uid)
          .single();
      final org = row['organizations'] as Map<String, dynamic>;
      final u = AppUser(
        id: row['id'] as String,
        orgId: row['org_id'] as String,
        fullName: row['full_name'] as String,
        role: row['role'] as String,
        orgName: org['name'] as String,
        joinCode: (org['join_code'] as String?) ?? '',
        orgStatus: (org['status'] as String?) ?? 'active',
        subscriptionExpiresAt: org['expires_at'] != null ? DateTime.tryParse(org['expires_at'] as String) : null,
      );
      ref.read(prefsProvider).setString(_cacheKey, jsonEncode(u.toJson()));
      state = u;
    } catch (e) {
      debugPrint('profile refresh failed: $e');
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      await sb.auth.signInWithPassword(email: email, password: password);
      await refresh();
      return state == null ? 'Signed in, but no staff profile was found for this account.' : null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  Future<String?> orgNameForCode(String code) async {
    try {
      final r = await sb.rpc('org_name_for_code', params: {'code': code});
      return r as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    String? orgName,
    String? joinCode,
  }) async {
    try {
      final res = await sb.auth.signUp(email: email, password: password, data: {
        'full_name': fullName,
        if (orgName != null) 'org_name': orgName,
        if (joinCode != null) 'join_code': joinCode,
      });
      if (res.session == null) return 'Account created. Confirm your email, then sign in.';
      await refresh();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Sign-up failed: $e';
    }
  }

  Future<void> signOut() async {
    try {
      await sb.auth.signOut();
    } catch (_) {}
    ref.read(prefsProvider).remove(_cacheKey);
    state = null;
  }
}

final authProvider = NotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);

// ───────────────────────── Sync (outbox worker) ─────────────────────────
class SyncState {
  const SyncState({this.online = true, this.syncing = false, this.lastSync});
  final bool online, syncing;
  final DateTime? lastSync;
  SyncState copyWith({bool? online, bool? syncing, DateTime? lastSync}) =>
      SyncState(online: online ?? this.online, syncing: syncing ?? this.syncing, lastSync: lastSync ?? this.lastSync);
}

class SyncNotifier extends Notifier<SyncState> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  bool _running = false;

  @override
  SyncState build() {
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      final on = r.any((e) => e != ConnectivityResult.none);
      state = state.copyWith(online: on);
      if (on) sync();
    });
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => sync());
    ref.onDispose(() {
      _sub?.cancel();
      _timer?.cancel();
    });
    Connectivity().checkConnectivity().then((r) {
      state = state.copyWith(online: r.any((e) => e != ConnectivityResult.none));
    });
    return const SyncState();
  }

  Future<void> sync() async {
    final user = ref.read(authProvider);
    if (_running || user == null || sb.auth.currentSession == null) return;
    _running = true;
    state = state.copyWith(syncing: true);
    var ok = 0, flagged = 0;
    try {
      final pending = await LocalDb.instance.pending(user.id);
      for (final r in pending) {
        try {
          String? cloudPath;
          final img = r.imagePath;
          if (img != null && File(img).existsSync()) {
            cloudPath = '${r.orgId}/${r.localId}.jpg';
            await sb.storage.from(AppConfig.receiptsBucket).upload(
                  cloudPath,
                  File(img),
                  fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
                );
          }
          final row = await sb
              .from('transactions')
              .upsert(r.toCloud(cloudPath), onConflict: 'org_id,local_id')
              .select('is_flagged, verification_status')
              .single();
          final f = row['is_flagged'] == true;
          final vStatus = (row['verification_status'] as String?) ?? 'awaiting';
          await LocalDb.instance.markSynced(r.localId, cloudPath, f, verificationStatus: vStatus);
          ok++;
          if (f) flagged++;
        } on PostgrestException catch (e) {
          debugPrint('permanent sync error for ${r.localId}: ${e.message}');
          await LocalDb.instance.markFailed(r.localId);
        } catch (e) {
          debugPrint('sync paused (network?): $e');
          break;
        }
      }
    } finally {
      _running = false;
      state = state.copyWith(syncing: false, lastSync: ok > 0 ? DateTime.now() : state.lastSync);
    }
    if (ok > 0) {
      NotificationService.instance.show('Receipts synced', '$ok receipt${ok == 1 ? '' : 's'} uploaded to the cloud.');
    }
    if (flagged > 0) {
      NotificationService.instance.show(
        'Duplicate reference flagged',
        '$flagged receipt${flagged == 1 ? ' was' : 's were'} flagged: the same reference exists already.',
        alert: true,
      );
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

// ───────────────────────── Data ─────────────────────────
final myReceiptsProvider = StreamProvider.autoDispose.family<List<Receipt>, DateTime>((ref, day) {
  final u = ref.watch(authProvider);
  if (u == null) return Stream.value(const <Receipt>[]);
  return LocalDb.instance.watchDay(u.id, day);
});

final myAllReceiptsProvider = StreamProvider.autoDispose<List<Receipt>>((ref) {
  final u = ref.watch(authProvider);
  if (u == null) return Stream.value(const <Receipt>[]);
  return LocalDb.instance.watchAllForWaiter(u.id);
});

final pendingCountProvider = StreamProvider.autoDispose<int>((ref) {
  final u = ref.watch(authProvider);
  if (u == null) return Stream.value(0);
  return LocalDb.instance.watchPendingCount(u.id);
});

final selectedDayProvider = StateProvider<DateTime>((_) => startOfDay(DateTime.now()));
final mgrDayProvider = StateProvider<DateTime>((_) => startOfDay(DateTime.now()));

final cloudTxProvider = StreamProvider.autoDispose<List<CloudTx>>((ref) {
  final u = ref.watch(authProvider);
  if (u == null) return Stream.value(const <CloudTx>[]);
  return sb
      .from('transactions')
      .stream(primaryKey: ['id'])
      .eq('org_id', u.orgId)
      .order('created_at', ascending: false)
      .limit(600)
      .map((rows) => rows.map(CloudTx.fromJson).toList());
});

final staffProvider = FutureProvider.autoDispose<List<Staff>>((ref) async {
  final u = ref.watch(authProvider);
  if (u == null) return [];
  final rows = await sb.from('profiles').select('id, full_name, role').eq('org_id', u.orgId).order('full_name');
  return (rows as List).map((e) => Staff.fromJson(e as Map<String, dynamic>)).toList();
});

final auditsProvider = FutureProvider.autoDispose<List<AuditRow>>((ref) async {
  final u = ref.watch(authProvider);
  if (u == null) return [];
  final rows = await sb.from('audits').select().eq('org_id', u.orgId).order('created_at', ascending: false).limit(20);
  return (rows as List).map((e) => AuditRow.fromJson(e as Map<String, dynamic>)).toList();
});
