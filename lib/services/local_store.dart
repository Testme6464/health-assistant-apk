import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/health_data.dart';

/// Local JSON cache — the offline half of the offline-first design.
///
/// The whole health DB (same shape as the web app's localStorage
/// `healthAppV1`) lives in SharedPreferences as one JSON blob, so the app
/// works fully offline. [SyncService] pushes/pulls this cache to Firestore
/// whenever the phone is online.
///
/// Change tracking: every write marks the collection dirty (a set of
/// collection names in [_dirtyKey]); the sync layer clears entries once
/// they are uploaded.
class LocalStore {
  LocalStore._();
  static final LocalStore _instance = LocalStore._();
  factory LocalStore() => _instance;

  static const _dbKey = 'healthassistant_db_v1';
  static const _dirtyKey = 'healthassistant_dirty_v1';
  static const _lastSyncKey = 'healthassistant_last_sync_v1';

  Map<String, dynamic> _db = {};
  bool _loaded = false;

  /// All collections the sync layer knows about. Each holds a list of
  /// record maps, except `settings` / `reminders` / `plans` (single maps).
  static const List<String> collections = [
    'profiles',
    'meds',
    'medLog',
    'foodLog',
    'waterLog',
    'sleepLog',
    'activityLog',
    'weightLog',
    'symptoms',
    'emergencyContacts',
    'periodLog',
    'mealPlans',
    'plans',
    'reminders',
    'settings',
  ];

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dbKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _db = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        _db = _emptyDb();
      }
    } else {
      _db = _emptyDb();
    }
    _loaded = true;
  }

  Map<String, dynamic> _emptyDb() => {
        'version': 1,
        'activeProfileId': '',
        'profiles': <Map<String, dynamic>>[],
        'meds': <Map<String, dynamic>>[],
        'medLog': <String, dynamic>{},
        'foodLog': <Map<String, dynamic>>[],
        'waterLog': <String, dynamic>{},
        'sleepLog': <Map<String, dynamic>>[],
        'activityLog': <Map<String, dynamic>>[],
        'weightLog': <Map<String, dynamic>>[],
        'symptoms': <Map<String, dynamic>>[],
        'emergencyContacts': <Map<String, dynamic>>[],
        'periodLog': <Map<String, dynamic>>[],
        'mealPlans': <Map<String, dynamic>>[],
        'plans': <String, dynamic>{},
        'reminders': <String, dynamic>{
          'waterEnabled': true,
          'waterInterval': 120,
          'waterStart': '08:00',
          'waterEnd': '21:00',
          'medEnabled': true,
          'sleepEnabled': true,
          'bedtime': '22:30',
        },
        'settings': <String, dynamic>{
          'geminiModel': 'gemini-3.8-flash',
          'calorieTargetMode': 'auto',
          'calorieTarget': 2000,
          'waterTargetMl': 2000,
        },
      };

  Map<String, dynamic> get db => _db;

  /// Replace the whole local DB (used by backup import / wipe).
  Future<void> resetDb() async {
    _db = _emptyDb();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dirtyKey);
    await prefs.remove(_lastSyncKey);
    await save();
  }

  List<Map<String, dynamic>> list(String collection) {
    final v = _db[collection];
    if (v is List) return v.cast<Map<String, dynamic>>();
    return [];
  }

  Map<String, dynamic> map(String collection) {
    final v = _db[collection];
    if (v is Map) return v.cast<String, dynamic>();
    return {};
  }

  String get activeProfileId => (_db['activeProfileId'] as String?) ?? '';

  HealthProfile? get activeProfile {
    final profiles = list('profiles');
    final id = activeProfileId;
    final found = profiles.where((p) => p['id'] == id);
    if (found.isNotEmpty) return HealthProfile.fromJson(found.first);
    if (profiles.isNotEmpty) return HealthProfile.fromJson(profiles.first);
    return null;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dbKey, jsonEncode(_db));
  }

  /// Replace a whole collection and mark it dirty for sync.
  Future<void> setCollection(String collection, List<Map<String, dynamic>> items) async {
    _db[collection] = items;
    await markDirty(collection);
    await save();
  }

  /// Upsert one record (by id) in a list collection.
  Future<void> upsert(String collection, Map<String, dynamic> record) async {
    final items = list(collection);
    final i = items.indexWhere((e) => e['id'] == record['id']);
    if (i >= 0) {
      items[i] = record;
    } else {
      items.add(record);
    }
    _db[collection] = items;
    await markDirty(collection);
    await save();
  }

  /// Soft-delete one record (tombstone — sync propagates the delete).
  Future<void> softDelete(String collection, String id) async {
    final items = list(collection);
    final i = items.indexWhere((e) => e['id'] == id);
    if (i >= 0) {
      items[i]['deleted'] = true;
      items[i]['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      _db[collection] = items;
      await markDirty(collection);
      await save();
    }
  }

  Future<void> markDirty(String collection) async {
    final prefs = await SharedPreferences.getInstance();
    final dirty = prefs.getStringList(_dirtyKey) ?? [];
    if (!dirty.contains(collection)) {
      dirty.add(collection);
      await prefs.setStringList(_dirtyKey, dirty);
    }
  }

  Future<List<String>> get dirtyCollections async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_dirtyKey) ?? [];
  }

  Future<void> clearDirty(List<String> collections) async {
    final prefs = await SharedPreferences.getInstance();
    final dirty = prefs.getStringList(_dirtyKey) ?? [];
    dirty.removeWhere((c) => collections.contains(c));
    await prefs.setStringList(_dirtyKey, dirty);
  }

  Future<int?> get lastSyncAt async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastSyncKey);
  }

  Future<void> setLastSyncAt(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncKey, ms);
  }

  /// Import a web-app JSON export (localStorage healthAppV1) into the
  /// local cache. Existing data is kept; imported records win on id clash
  /// when their updatedAt is newer (web records have no updatedAt, so they
  /// are stamped with the import time).
  Future<void> importWebExport(Map<String, dynamic> webDb) async {
    await load();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in ['profiles', 'meds', 'foodLog', 'sleepLog', 'activityLog',
        'weightLog', 'symptoms', 'emergencyContacts', 'periodLog', 'mealPlans']) {
      final incoming = webDb[c];
      if (incoming is List) {
        final items = list(c);
        for (final raw in incoming) {
          if (raw is! Map) continue;
          final rec = Map<String, dynamic>.from(raw);
          rec['updatedAt'] ??= now;
          final i = items.indexWhere((e) => e['id'] == rec['id']);
          if (i >= 0) {
            final oldAt = (items[i]['updatedAt'] as num?)?.toInt() ?? 0;
            if ((rec['updatedAt'] as num).toInt() >= oldAt) items[i] = rec;
          } else {
            items.add(rec);
          }
        }
        _db[c] = items;
        await markDirty(c);
      }
    }
    if (webDb['waterLog'] is Map) {
      final wl = map('waterLog');
      (webDb['waterLog'] as Map).forEach((k, v) => wl['$k'] = v);
      _db['waterLog'] = wl;
      await markDirty('waterLog');
    }
    if (webDb['activeProfileId'] is String &&
        (_db['activeProfileId'] as String? ?? '').isEmpty) {
      _db['activeProfileId'] = webDb['activeProfileId'];
    }
    await save();
  }
}
