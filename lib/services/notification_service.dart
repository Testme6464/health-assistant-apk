// System notifications — reminders that fire even when the app is closed.
//
// The Reminders tab's in-app Timer + toast only works while the app is
// open; that is why users reported "notification က အလုပ်မလုပ်ဘူး".
// This service schedules REAL system notifications with
// flutter_local_notifications (exact alarms, Doze-proof) and re-schedules
// them whenever reminder settings change.
//
// Scheduling rules (all times Asia/Bangkok):
// - Water: waterStart, then every waterInterval minutes until waterEnd.
// - Meds: every dose time of every med of the active profile.
// - Bedtime: one notification at bedtime.
// - Meal plans: today's planned meals for the active profile.
// A time already passed today is scheduled for tomorrow, so there is
// always a next notification. IDs live in fixed ranges (water 1000+,
// meds 2000+, bedtime 3000, meals 4000+) so cancelling reminders never
// touches anything else.
//
// Ringtone: the bundled Energetic Rock clip (the user's file,
// amplified 3x and looped to 1 minute). It ships as a Flutter asset
// (assets/sounds/energetic_rock.mp3) and is copied once to the app's
// external files dir, where the system notification service can read
// it even when the app is closed — a file:// URI the system can open.
// (res/raw/ was tried first: the release build's resource optimizer
// strips it because it is only referenced by string name, and
// keep.xml did not keep it — v1.0.5/v1.0.6.) Tapping a notification
// dismisses it, which stops the sound.
//
// Everything here is guarded: a failure to init/schedule must never
// crash the app — reminders simply degrade to the in-app toasts.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/health_data.dart';
import 'local_store.dart';

// ---------------------------------------------------------------------------
// Pure, testable helpers (no plugin calls — unit-testable).
// ---------------------------------------------------------------------------

/// 'HH:MM' -> minutes since midnight, or null when invalid.
int? parseHmMinutes(String hm) {
  final p = hm.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0].trim());
  final m = int.tryParse(p[1].trim());
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}

String _fmtMinutes(int minutes) {
  final m = ((minutes % 1440) + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Water reminder times: [startHm], then every [intervalMinutes] until
/// [endHm] inclusive. E.g. 08:00 / 21:00 / 120 ->
/// 08:00, 10:00, 12:00, 14:00, 16:00, 18:00, 20:00.
List<String> waterTimes(
  String startHm,
  String endHm,
  int intervalMinutes,
) {
  final start = parseHmMinutes(startHm);
  final end = parseHmMinutes(endHm);
  if (start == null || end == null || intervalMinutes <= 0) return [];
  final out = <String>[];
  var m = start;
  while (m <= end) {
    out.add(_fmtMinutes(m));
    m += intervalMinutes;
  }
  return out;
}

/// Next occurrence of a 'HH:MM' time: today if still ahead, else tomorrow.
/// Null when the time is invalid.
tz.TZDateTime? nextOccurrence(String hhmm, tz.TZDateTime now) {
  final mins = parseHmMinutes(hhmm);
  if (mins == null) return null;
  var t = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    mins ~/ 60,
    mins % 60,
  );
  if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
  return t;
}

// ---------------------------------------------------------------------------
// Service.
// ---------------------------------------------------------------------------

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  static const String channelId = 'health_reminders_v2';
  static const String channelName = 'ကျန်းမာရေး သတိပေးချက်များ';
  static const String _idsPref = 'healthassistant_notif_ids_v1';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final LocalStore _local = LocalStore();

  bool _initialized = false;
  tz.Location? _bangkok;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Initialise timezone data + the plugin and ask for the
  /// POST_NOTIFICATIONS runtime permission (Android 13+). Safe to call
  /// repeatedly; never throws.
  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      _bangkok = tz.getLocation('Asia/Bangkok');
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(
        settings: settings,
        // Tapping a notification cancels it, which stops its sound.
        // (The plugin also auto-cancels on tap; this makes it explicit
        // so the 1-minute Energetic Rock clip stops immediately.)
        onDidReceiveNotificationResponse: (resp) async {
          final id = resp.id;
          if (id != null) {
            try {
              await _plugin.cancel(id: id);
            } catch (_) {}
          }
        },
      );
      _initialized = true;
      // Runtime permission dialog (Android 13+). If the user declines,
      // scheduled notifications simply never appear — no crash.
      await _android?.requestNotificationsPermission();
    } catch (_) {
      // Notifications unavailable on this device/build — degrade to the
      // in-app toasts.
    }
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  /// Whether exact alarms are allowed (Android 12+ "Alarms & reminders").
  /// When denied, [scheduleAll] falls back to inexact scheduling.
  Future<bool> canScheduleExactAlarms() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open the system "Alarms & reminders" settings page so the user can
  /// allow exact alarms. Call from a settings button, never at startup.
  Future<void> requestExactAlarmsPermission() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  /// Ask for the POST_NOTIFICATIONS runtime permission (Android 13+).
  /// Returns true when granted.
  Future<bool> requestNotificationsPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cancel every reminder notification this service scheduled.
  Future<void> cancelAllReminders() async {
    try {
      await _ensureInit();
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_idsPref) ?? [];
      for (final raw in ids) {
        final id = int.tryParse(raw);
        if (id != null) await _plugin.cancel(id: id);
      }
      await prefs.remove(_idsPref);
    } catch (_) {}
  }

  /// Send a test notification 5 seconds from now (same channel and
  /// ringtone as the real reminders) so the user can verify on the
  /// phone that notifications actually appear and sound. Never throws.
  Future<void> sendTestNotification() async {
    try {
      await _ensureInit();
      if (_bangkok == null) return;
      final soundPath = await _bundledSoundPath();
      final details = _details(soundPath);
      final exact = await canScheduleExactAlarms();
      final mode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final when = tz.TZDateTime.now(_bangkok!).add(
        const Duration(seconds: 5),
      );
      await _plugin.zonedSchedule(
        id: 9999,
        title: '🔔 စမ်းသပ်ချက်',
        body: 'Notification အလုပ်လုပ်ပါတယ် ✅',
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: mode,
      );
    } catch (_) {}
  }

  /// (Re)schedule all reminders from the current LocalStore data.
  /// Cancels the previous set first. Never throws.
  Future<void> scheduleAll() async {
    try {
      await _ensureInit();
      if (_bangkok == null) return;
      await _local.load();
      await cancelAllReminders();

      final r = _local.map('reminders');
      final now = tz.TZDateTime.now(_bangkok!);

      final exact = await canScheduleExactAlarms();
      final mode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final soundPath = await _bundledSoundPath();
      final details = _details(soundPath);

      final scheduledIds = <int>[];

      // ---- Water ----
      if (toBool(r['waterEnabled'], true)) {
        final interval = toInt(r['waterInterval']) ?? 120;
        final start = strVal(r['waterStart']).isEmpty
            ? '08:00'
            : strVal(r['waterStart']);
        final end = strVal(r['waterEnd']).isEmpty
            ? '21:00'
            : strVal(r['waterEnd']);
        // Cap: a 1-minute interval over 08:00-21:00 would be 781 alarms.
        // Scheduling that many exact alarms is slow and can hit the
        // system limit, so schedule at most 150 (2.5h at 1-min).
        const maxWater = 150;
        var i = 0;
        for (final t in waterTimes(start, end, interval)) {
          if (i >= maxWater) break;
          final when = nextOccurrence(t, now);
          if (when == null) continue;
          final id = 1000 + i++;
          await _plugin.zonedSchedule(
            id: id,
            title: '💧 ရေသောက်ရန်',
            body: 'ရေသောက်ဖို့ အချိန်ရောက်ပြီ',
            scheduledDate: when,
            notificationDetails: details,
            androidScheduleMode: mode,
          );
          scheduledIds.add(id);
        }
      }

      final p = _local.activeProfile;

      // ---- Meds (active profile only) ----
      if (toBool(r['medEnabled'], true) && p != null) {
        var j = 0;
        for (final med in _local.list('meds').where(
              (m) =>
                  m['profileId'] == p.id && m['deleted'] != true,
            )) {
          final name = strVal(med['name']);
          if (name.isEmpty) continue;
          final dosage = strVal(med['dosage']);
          for (final t in _medTimesOf(med)) {
            final when = nextOccurrence(t, now);
            if (when == null) continue;
            final id = 2000 + j++;
            await _plugin.zonedSchedule(
              id: id,
              title: '💊 ဆေးသောက်ရန်',
              body:
                  '$name${dosage.isNotEmpty ? ' ($dosage)' : ''} သောက်ဖို့ အချိန်ရောက်ပါပြီ',
              scheduledDate: when,
              notificationDetails: details,
              androidScheduleMode: mode,
            );
            scheduledIds.add(id);
          }
        }
      }

      // ---- Bedtime ----
      if (toBool(r['sleepEnabled'], true)) {
        final bedtime = strVal(r['bedtime']).isEmpty
            ? '22:30'
            : strVal(r['bedtime']);
        final when = nextOccurrence(bedtime, now);
        if (when != null) {
          await _plugin.zonedSchedule(
            id: 3000,
            title: '😴 အိပ်ရာဝင်ချိန် ရောက်ပြီ',
            body: 'အိပ်ရာဝင်ဖို့ ပြင်ဆင်လိုက်ပါ — မနက်ဖြန် လန်းဆန်းပါစေ',
            scheduledDate: when,
            notificationDetails: details,
            androidScheduleMode: mode,
          );
          scheduledIds.add(3000);
        }
      }

      // ---- Today's meal plans (active profile only) ----
      if (p != null) {
        final today = todayStr();
        var k = 0;
        for (final m in _local.list('mealPlans').where(
              (m) =>
                  m['profileId'] == p.id &&
                  m['deleted'] != true &&
                  strVal(m['date']) == today,
            )) {
          final what = strVal(m['what']);
          final time = strVal(m['time']);
          if (what.isEmpty) continue;
          final when = nextOccurrence(time, now);
          if (when == null) continue;
          final id = 4000 + k++;
          await _plugin.zonedSchedule(
            id: id,
            title: '🍽️ အစားအသောက် အချိန်ရောက်ပါပြီ',
            body: '$what စားဖို့ အချိန်ရောက်ပါပြီ',
            scheduledDate: when,
            notificationDetails: details,
            androidScheduleMode: mode,
          );
          scheduledIds.add(id);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _idsPref,
        scheduledIds.map((e) => '$e').toList(),
      );
    } catch (_) {
      // Scheduling failed (e.g. exact-alarm permission revoked mid-run):
      // in-app toasts remain the fallback.
    }
  }

  // ---------------- internals ----------------

  /// Path of the bundled Energetic Rock clip, copied once from the
  /// Flutter asset into the app's external files dir so the system
  /// notification service can read it even when the app is closed.
  /// Returns '' when the copy is unavailable (callers fall back to
  /// the system default sound). Never throws.
  Future<String> _bundledSoundPath() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext == null) return '';
      final dir = Directory('${ext.path}/notification_sounds');
      await dir.create(recursive: true);
      final dest = File('${dir.path}/energetic_rock.mp3');
      if (!await dest.exists()) {
        final bytes = await rootBundle.load(
          'assets/sounds/energetic_rock.mp3',
        );
        await dest.writeAsBytes(bytes.buffer.asUint8List());
      }
      return dest.path;
    } catch (_) {
      return '';
    }
  }

  /// Every reminder uses the bundled Energetic Rock clip. When its
  /// copied file is available the notification plays it (the system
  /// reads the file:// URI even with the app closed); otherwise the
  /// system default sound is used.
  NotificationDetails _details(String soundPath) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.high,
        priority: Priority.high,
        sound: soundPath.isNotEmpty
            ? UriAndroidNotificationSound('file://$soundPath')
            : null,
      ),
    );
  }

  /// A med's dose times, tolerating List or comma-String shapes and
  /// dropping invalid entries (same tolerance as tab_common medTimes).
  List<String> _medTimesOf(Map<String, dynamic> med) {
    final raw = med['times'];
    final items = strList(raw);
    return items.where((t) => parseHmMinutes(t) != null).toList();
  }
}
