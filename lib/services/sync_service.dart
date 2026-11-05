import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'local_store.dart';

/// Offline-first Firestore sync.
///
/// Data model (project "Health Assistant", health-assistant-65709):
///   users/{uid}/{collection}/{docId}   — list collections
///     (profiles, meds, foodLog, sleepLog, activityLog, weightLog,
///      symptoms, emergencyContacts, periodLog, mealPlans)
///   users/{uid}/meta/{collection}      — single docs
///     (settings, reminders, plans, waterLog)
///
/// Rules (firestore.rules): a user can only read/write their own subtree.
///
/// How it works:
/// 1. The app ALWAYS reads/writes the local cache ([LocalStore]) — it works
///    fully offline.
/// 2. Every local write marks its collection dirty.
/// 3. [syncNow] pushes dirty collections, then pulls every collection's
///    changes newer than [LocalStore.lastSyncAt]. Newer `updatedAt` wins.
/// 4. Sync runs automatically on app start, when connectivity returns,
///    and when the user taps "Sync now" in Settings.
/// 5. Firestore's own offline persistence is also on, so even a direct
///    Firestore read works while offline — but the local cache is the
///    source of truth for the UI.
///
/// [status] is a [ValueNotifier] the UI watches for
/// "synced / pending N / syncing / error" display.
class SyncService {
  SyncService._();
  static final SyncService _instance = SyncService._();
  factory SyncService() => _instance;

  final LocalStore _local = LocalStore();
  final AuthService _auth = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final ValueNotifier<SyncStatus> status =
      ValueNotifier(const SyncStatus(state: SyncState.idle));

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _syncing = false;

  static const List<String> listCollections = [
    'profiles',
    'meds',
    'foodLog',
    'sleepLog',
    'activityLog',
    'weightLog',
    'symptoms',
    'emergencyContacts',
    'periodLog',
    'mealPlans',
  ];

  static const List<String> singleCollections = [
    'settings',
    'reminders',
    'plans',
    'waterLog',
  ];

  /// Start listening for connectivity changes; run an initial sync.
  Future<void> start() async {
    await _local.load();
    _connSub?.cancel();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(syncNow());
      }
    });
    unawaited(syncNow());
  }

  void dispose() {
    _connSub?.cancel();
  }

  CollectionReference<Map<String, dynamic>> _col(String uid, String name) =>
      _db.collection('users').doc(uid).collection(name);

  DocumentReference<Map<String, dynamic>> _single(String uid, String name) =>
      _db.collection('users').doc(uid).collection('meta').doc(name);

  /// Push dirty collections, then pull remote changes. Safe to call any
  /// time; concurrent calls are coalesced into one run.
  Future<void> syncNow() async {
    if (_syncing) return;
    final uid = _auth.uid;
    if (uid == null) {
      status.value = const SyncStatus(
          state: SyncState.idle, message: 'Login မဝင်ရသေးပါ');
      return;
    }
    _syncing = true;
    status.value = const SyncStatus(state: SyncState.syncing);
    try {
      await _local.load();
      final dirty = await _local.dirtyCollections;
      final pushed = <String>[];
      for (final c in dirty) {
        await _pushCollection(uid, c);
        pushed.add(c);
      }
      if (pushed.isNotEmpty) await _local.clearDirty(pushed);

      final lastSync = await _local.lastSyncAt ?? 0;
      var pulled = 0;
      for (final c in [...listCollections, ...singleCollections]) {
        pulled += await _pullCollection(uid, c, lastSync);
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _local.setLastSyncAt(now);
      await _local.save();
      final pending = (await _local.dirtyCollections).length;
      status.value = SyncStatus(
        state: pending > 0 ? SyncState.pending : SyncState.synced,
        message: pulled > 0 ? 'အသစ် $pulled ခု ဆွဲယူပြီးပါပြီ' : null,
        pendingCount: pending,
        lastSyncAt: now,
      );
    } catch (e) {
      status.value = SyncStatus(
        state: SyncState.error,
        message: 'Sync မရပါ: $e',
      );
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pushCollection(String uid, String collection) async {
    if (listCollections.contains(collection)) {
      final items = _local.list(collection);
      final batch = _db.batch();
      final toRemove = <Map<String, dynamic>>[];
      for (final item in items) {
        final id = item['id'] as String?;
        if (id == null || id.isEmpty) continue;
        final doc = _col(uid, collection).doc(id);
        if (item['deleted'] == true) {
          batch.delete(doc);
          toRemove.add(item);
        } else {
          batch.set(doc, _cleanForFirestore(item), SetOptions(merge: true));
        }
      }
      await batch.commit();
      if (toRemove.isNotEmpty) {
        final remaining =
            items.where((e) => e['deleted'] != true).toList();
        _local.db[collection] = remaining;
      }
    } else if (singleCollections.contains(collection)) {
      final data = _local.map(collection);
      await _single(uid, collection)
          .set(_cleanForFirestore(data), SetOptions(merge: true));
    }
  }

  /// Pull docs changed since [lastSyncMs]; merge newer-wins into local.
  /// Returns the number of records merged.
  Future<int> _pullCollection(String uid, String collection, int lastSyncMs) async {
    var merged = 0;
    if (listCollections.contains(collection)) {
      final snap = await _col(uid, collection)
          .where('updatedAt', isGreaterThan: lastSyncMs)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) return 0;
      final items = _local.list(collection);
      for (final doc in snap.docs) {
        final remote = doc.data();
        remote['id'] = doc.id;
        final i = items.indexWhere((e) => e['id'] == doc.id);
        final remoteAt = (remote['updatedAt'] as num?)?.toInt() ?? 0;
        if (remote['deleted'] == true) {
          if (i >= 0) items.removeAt(i);
          merged++;
          continue;
        }
        if (i >= 0) {
          final localAt = (items[i]['updatedAt'] as num?)?.toInt() ?? 0;
          if (remoteAt > localAt) {
            items[i] = remote;
            merged++;
          }
        } else {
          items.add(remote);
          merged++;
        }
      }
      _local.db[collection] = items;
    } else if (singleCollections.contains(collection)) {
      final doc = await _single(uid, collection)
          .get(const GetOptions(source: Source.server));
      final data = doc.data();
      if (data == null) return 0;
      final remoteAt = (data['updatedAt'] as num?)?.toInt() ?? 0;
      if (remoteAt > lastSyncMs) {
        final local = _local.map(collection);
        final mergedMap = {...local, ...data};
        _local.db[collection] = mergedMap;
        merged = 1;
      }
    }
    return merged;
  }

  /// Firestore rejects null values in some contexts and nested maps with
  /// non-string keys — strip nulls one level deep.
  Map<String, dynamic> _cleanForFirestore(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (v != null) out[k] = v;
    });
    return out;
  }
}

enum SyncState { idle, syncing, synced, pending, error }

class SyncStatus {
  const SyncStatus({
    required this.state,
    this.message,
    this.pendingCount = 0,
    this.lastSyncAt,
  });

  final SyncState state;
  final String? message;
  final int pendingCount;
  final int? lastSyncAt;

  String get labelMm {
    switch (state) {
      case SyncState.idle:
        return 'Sync မလုပ်ရသေးပါ';
      case SyncState.syncing:
        return 'Sync လုပ်နေသည်…';
      case SyncState.synced:
        return '✅ Server နဲ့ တူညီနေပါပြီ';
      case SyncState.pending:
        return '⏳ ပို့ဖို့ ကျန်နေသည် ($pendingCount)';
      case SyncState.error:
        return '❌ Sync မရပါ';
    }
  }
}
