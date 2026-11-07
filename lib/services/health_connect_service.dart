// Health Connect (Stage 3) — read the phone's step count and workouts
// from Google Health Connect into the app's activity log.
//
// Flow: Settings > ချိတ်ဆက်မှုများ > "Health Connect ချိတ်မယ်" asks for
// READ permission (steps, workouts, calories). Once granted, today's
// steps + workouts are pulled into activityLog (source 'health_connect')
// and the normal auto-sync pushes them to Firestore.
//
// Merge rule for today: Health Connect steps win when larger (the phone
// pedometer counts all day); a manual minutes/exercise entry the user
// typed keeps its minutes and type, only its steps are topped up.
//
// If the in-app permission prompt does not appear (some devices), the
// Settings card offers "Health Connect settings ဖွင့်မယ်" which opens
// the system Health Connect App-permissions screen so the user can
// grant the permission manually.
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../data/static_data.dart';
import '../models/health_data.dart';
import 'local_store.dart';

enum HCStatus {
  /// Health Connect is not available on this device / OS.
  unavailable,

  /// Health Connect app/SDK is missing or needs an update.
  notInstalled,

  /// Available but the user has not granted READ permission yet.
  noPermission,

  /// Available and READ permission granted — ready to sync.
  ready,
}

class HealthConnectService {
  HealthConnectService._();
  static final HealthConnectService _instance = HealthConnectService._();
  factory HealthConnectService() => _instance;

  final Health _health = Health();
  final LocalStore _local = LocalStore();

  static const List<HealthDataType> _types = [
    HealthDataType.STEPS,
    HealthDataType.WORKOUT,
    HealthDataType.TOTAL_CALORIES_BURNED,
  ];

  /// Map a Health Connect workout type to the app's exerciseBurn index.
  /// Unknown types fall back to index 9 (အိမ်အလုပ်, the 'other' bucket).
  static int hcWorkoutToExerciseIndex(HealthWorkoutActivityType t) {
    switch (t) {
      case HealthWorkoutActivityType.WALKING:
        return 1;
      case HealthWorkoutActivityType.HIKING:
        return 2;
      case HealthWorkoutActivityType.RUNNING:
        return 3;
      case HealthWorkoutActivityType.BIKING:
      case HealthWorkoutActivityType.BIKING_STATIONARY:
        return 4;
      case HealthWorkoutActivityType.SWIMMING:
      case HealthWorkoutActivityType.SWIMMING_POOL:
      case HealthWorkoutActivityType.SWIMMING_OPEN_WATER:
        return 5;
      case HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING:
      case HealthWorkoutActivityType.PILATES:
      case HealthWorkoutActivityType.CROSS_TRAINING:
        return 6;
      case HealthWorkoutActivityType.YOGA:
        return 8;
      default:
        return 9;
    }
  }

  /// Current connection state. Never throws — returns [HCStatus.unavailable]
  /// when the platform call fails.
  Future<HCStatus> status() async {
    try {
      final sdk = await _health.getHealthConnectSdkStatus();
      if (sdk != HealthConnectSdkStatus.sdkAvailable) {
        return sdk == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired
            ? HCStatus.notInstalled
            : HCStatus.unavailable;
      }
      final granted = await _health.hasPermissions(_types);
      if (granted == true) return HCStatus.ready;
      return HCStatus.noPermission;
    } catch (_) {
      return HCStatus.unavailable;
    }
  }

  /// Ask the user for READ permission (steps, workouts, calories).
  /// Tries the direct MainActivity channel first (official Health Connect
  /// API — this is what makes the app appear in Health Connect's App
  /// permissions list), and falls back to the `health` plugin when the
  /// direct channel is unavailable. Returns true when granted (verified
  /// with hasPermissions afterwards, because the prompt can close
  /// without granting).
  Future<bool> requestPermissions() async {
    try {
      const channel = MethodChannel('health_connect_direct');
      final granted = await channel.invokeMethod<bool>('requestPermissions');
      if (granted == true) return true;
      // Direct request did not grant — verify before falling back, in
      // case the user granted it in the system screen meanwhile.
      if (await _health.hasPermissions(_types) == true) return true;
    } catch (_) {
      // Direct channel unavailable (e.g. older build) — fall through.
    }
    try {
      await _health.requestAuthorization(_types);
      final granted = await _health.hasPermissions(_types);
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Open the system Health Connect settings (App permissions screen) so
  /// the user can grant the permission manually when the in-app prompt
  /// does not appear. Launches the Health Connect app itself first (the
  /// reliable path on MIUI, where the system settings action can open
  /// an unrelated settings page instead), then the system settings
  /// action (Android 14+), then the Play Store page.
  Future<void> openHealthConnectSettings() async {
    try {
      await const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.google.android.apps.healthdata',
      ).launch();
      return;
    } catch (_) {
      // Fall through to the next option.
    }
    const settingsAction = 'android.settings.HEALTH_CONNECT_SETTINGS';
    try {
      await const AndroidIntent(action: settingsAction).launch();
      return;
    } catch (_) {
      // Fall through to the Play Store page.
    }
    await installApp();
  }

  /// Open the Play Store page for the Health Connect app.
  Future<void> installApp() async {
    try {
      await _health.installHealthConnect();
    } catch (_) {
      // No-op: nothing to install from (e.g. no Play Store).
    }
  }

  /// Pull today's steps + workouts from Health Connect into the local
  /// activityLog for [profileId]. Returns a short Burmese summary, or
  /// null when nothing could be read (not connected / no data).
  Future<String?> syncToday(String profileId, double weightKg) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final t = todayStr();
    try {
      final steps = await _health.getTotalStepsInInterval(start, now) ?? 0;
      var minutes = 0;
      var exType = 1;
      var bestMinutes = 0;
      final workouts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT],
        startTime: start,
        endTime: now,
      );
      for (final point in workouts) {
        final v = point.value;
        if (v is! WorkoutHealthValue) continue;
        final mins =
            point.dateTo.difference(point.dateFrom).inMinutes;
        if (mins <= 0) continue;
        minutes += mins;
        if (mins > bestMinutes) {
          bestMinutes = mins;
          exType = hcWorkoutToExerciseIndex(v.workoutActivityType);
        }
      }
      if (steps <= 0 && minutes <= 0) return null;

      final k = activityKcal(
        steps: steps,
        exerciseType: exType,
        minutes: minutes,
        weightKg: weightKg,
      );
      await _local.load();
      final items = _local.list('activityLog');
      final existing = items.where((e) =>
          e['profileId'] == profileId && strVal(e['date']) == t);
      if (existing.isNotEmpty) {
        final rec = Map<String, dynamic>.from(existing.first);
        final prevSteps = toInt(rec['steps']) ?? 0;
        // Keep a manual entry's minutes/type; only top up its steps.
        if (rec['source'] == 'manual') {
          rec['steps'] = steps > prevSteps ? steps : prevSteps;
        } else {
          rec['steps'] = steps;
          rec['minutes'] = minutes;
          rec['exerciseType'] = exType;
        }
        final rk = activityKcal(
          steps: toInt(rec['steps']) ?? 0,
          exerciseType: toInt(rec['exerciseType']) ?? 1,
          minutes: toInt(rec['minutes']) ?? 0,
          weightKg: weightKg,
        );
        rec['stepsKcal'] = rk.stepsKcal;
        rec['exKcal'] = rk.exKcal;
        rec['kcal'] = rk.total;
        rec['source'] = 'health_connect';
        await _local.upsert('activityLog', rec);
      } else {
        await _local.upsert('activityLog', {
          'id': newId(),
          'profileId': profileId,
          'date': t,
          'steps': steps,
          'minutes': minutes,
          'exerciseType': exType,
          'stepsKcal': k.stepsKcal,
          'exKcal': k.exKcal,
          'kcal': k.total,
          'source': 'health_connect',
        });
      }
      await _local.save();
      final parts = <String>['ခြေလှမ်း $steps'];
      if (minutes > 0) parts.add('လေ့ကျင့်ခန်း $minutes မိနစ်');
      return '${parts.join(' · ')} ဆွဲယူပြီးပါပြီ ✅';
    } catch (_) {
      return null;
    }
  }
}
