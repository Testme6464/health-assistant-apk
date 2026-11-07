// Shared helpers for the stage-2 tabs — faithful ports of the web app's
// utils and shared logic (~/workspace/health-app/app.js). Every Burmese
// string here is copied from app.js, never typed from memory.
// Blue theme only; all dates are 'yyyy-MM-dd', all times 'HH:mm'.
import 'package:flutter/material.dart';

import '../../data/plan_data.dart';
import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../services/local_store.dart';

/// Mixin for tab screens: loads the LocalStore once, exposes [local],
/// [loaded] and [activeProfile], and [refresh]/[saveAndRefresh] helpers.
mixin TabLoader<T extends StatefulWidget> on State<T> {
  final LocalStore local = LocalStore();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    local.load().then((_) {
      if (mounted) setState(() => loaded = true);
    });
  }

  HealthProfile? get activeProfile => local.activeProfile;

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> saveAndRefresh() async {
    await local.save();
    refresh();
  }
}

/// Toast (web: toast()).
void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(milliseconds: 2500)),
  );
}

/// Confirm dialog (web: confirm()). Returns true when the user confirms.
Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String content,
) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('မလုပ်ဘူး'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('လုပ်မယ်'),
        ),
      ],
    ),
  );
  return r ?? false;
}

// ---------------- dates & times (web: todayStr/addDays/nowHM/...) ----------------

const List<String> mmMonths = [
  'ဇန်နဝါရီ',
  'ဖေဖော်ဝါရီ',
  'မတ်',
  'ဧပြီ',
  'မေ',
  'ဇွန်',
  'ဇူလိုင်',
  'ဩဂုတ်',
  'စက်တင်ဘာ',
  'အောက်တိုဘာ',
  'နိုဝင်ဘာ',
  'ဒီဇင်ဘာ',
];

DateTime parseDate(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// '2026-11-06' -> '6 နိုဝင်ဘာ 2026' (web: fmtDateMm).
/// Never throws: a malformed date string is returned as-is.
String fmtDateMm(String dateStr) {
  if (dateStr.isEmpty) return '';
  try {
    final p = dateStr.split('-');
    if (p.length < 3) return dateStr;
    final day = p[2].replaceFirst(RegExp(r'^0'), '');
    return '$day ${mmMonths[int.parse(p[1]) - 1]} ${p[0]}';
  } catch (_) {
    return dateStr;
  }
}

String nowHm() {
  final n = DateTime.now();
  return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
}

/// 'HH:mm' -> minutes since midnight. Never throws: a missing,
/// empty or non-numeric time reads as 00:00 instead of crashing the
/// caller (Reminders checker, sleep duration, meal-plan times).
int hmToMin(String hm) {
  final p = hm.split(':');
  final h = int.tryParse(p[0].trim()) ?? 0;
  final m = p.length > 1 ? (int.tryParse(p[1].trim()) ?? 0) : 0;
  return h * 60 + m;
}

String minToHm(int m) {
  m = ((m % 1440) + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String addDaysStr(String dateStr, int n) =>
    fmtDate(parseDate(dateStr).add(Duration(days: n)));

/// 24h -> Burmese 12h label (web: fmtTimeMm).
/// Never throws: a malformed time is returned as-is.
String fmtTimeMm(String hm) {
  if (hm.isEmpty) return '';
  final parts = hm.split(':');
  final h = int.tryParse(parts[0].trim());
  if (h == null) return hm;
  final m = parts.length > 1 ? parts[1] : '00';
  final ap = h < 12
      ? 'နံနက်'
      : (h < 17 ? 'နေ့လယ်' : (h < 20 ? 'ညနေ' : 'ည'));
  var h12 = h % 12;
  if (h12 == 0) h12 = 12;
  return '$ap $h12:$m';
}

/// Time-of-day bucket label (web: timeOfDayMm).
String timeOfDayMm(int h) {
  if (h < 5) return 'ညနက်ပိုင်း';
  if (h < 11) return 'မနက်ပိုင်း';
  if (h < 17) return 'နေ့လည်ပိုင်း';
  if (h < 22) return 'ညနေပိုင်း';
  return 'ညပိုင်း';
}

String currentMonthKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

/// Pick a date; returns 'yyyy-MM-dd' or null when cancelled.
Future<String?> pickDateStr(BuildContext context, String initial) async {
  final d = await showDatePicker(
    context: context,
    initialDate: parseDate(initial),
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
  return d == null ? null : fmtDate(d);
}

/// Pick a time; returns 'HH:mm' or null when cancelled.
Future<String?> pickTimeStr(BuildContext context, String initial) async {
  final parts = initial.split(':');
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    ),
  );
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ---------------- meds (web: todaysMedSchedule / medSupplyLeft / medLog) ----------------

/// One scheduled dose for a day.
typedef MedDose = ({
  Map<String, dynamic> med,
  String time,
  String key,
  String status, // 'taken' | 'missed' | 'pending'
});

/// A med's dose times, tolerating the shapes real data arrives in:
/// a List (normal), a comma-separated String ("08:00, 20:00"), or
/// missing/other (no times). Used by the schedule, the Meds tab rows
/// and the report — one bad med must not blank every tab that reads it.
List<String> medTimes(Map<String, dynamic> m) => strList(m['times']);

/// Today's med schedule for a profile, sorted by time (web: todaysMedSchedule).
/// Tolerant of hostile shapes: `times` as a String, the day's medLog as
/// a non-map, or a log value that is not a String — each degrades to
/// "no dose" / "pending" instead of throwing and blanking the tab.
List<MedDose> todaysMedSchedule(
  LocalStore local,
  String profileId,
  String dateStr,
) {
  final out = <MedDose>[];
  final dayRaw = local.map('medLog')[dateStr];
  final dayLog = <String, String>{};
  if (dayRaw is Map) {
    for (final e in dayRaw.entries) {
      if (e.key is String && e.value is String) {
        dayLog[e.key as String] = e.value as String;
      }
    }
  }
  for (final m
      in local.list('meds').where((m) => m['profileId'] == profileId)) {
    for (final tm in medTimes(m)) {
      final key = "${m['id']}@$tm";
      out.add((
        med: m,
        time: tm,
        key: key,
        status: dayLog[key] ?? 'pending',
      ));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// Days of supply left (web: medSupplyLeft). Null when not tracked.
/// Never throws: a non-string or malformed start date reads as untracked.
int? medSupplyLeft(Map<String, dynamic> m) {
  final days = toInt(m['supplyDays']);
  final start = strVal(m['supplyStartDate']);
  if (days == null || start.isEmpty) return null;
  try {
    final end = parseDate(addDaysStr(start, days));
    final today = parseDate(todayStr());
    return end.difference(today).inDays;
  } catch (_) {
    return null;
  }
}

/// Toggle a dose status (web: clicking the same status reverts to pending).
Future<void> toggleMedStatus(
  LocalStore local,
  String dateStr,
  String key,
  String status,
) async {
  final medLog = local.map('medLog');
  final day = <String, dynamic>{};
  final dayRaw = medLog[dateStr];
  if (dayRaw is Map) {
    for (final e in dayRaw.entries) {
      if (e.key is String) day[e.key as String] = e.value;
    }
  }
  day[key] = (day[key] == status) ? 'pending' : status;
  medLog[dateStr] = day;
  local.db['medLog'] = medLog;
  await local.markDirty('medLog');
  await local.save();
}

/// Local (offline) drug-interaction check (web: checkLocalInteractions).
/// Returns matches: each is (entry, matched med names).
List<({DrugInteraction entry, List<String> meds})> checkLocalInteractions(
  List<String> medNames,
) {
  final found = <({DrugInteraction entry, List<String> meds})>[];
  final norms = medNames.map((n) => n.toLowerCase().trim()).toList();
  for (final entry in drugInteractions) {
    final matchedIdx = <int>{};
    final matchedMeds = <String>[];
    for (final d in entry.drugs) {
      final i = norms.indexWhere((n) => n.contains(d) || d.contains(n));
      if (i >= 0) {
        matchedIdx.add(i);
        matchedMeds.add(medNames[i]);
      }
    }
    if (matchedIdx.length >= 2) {
      found.add((entry: entry, meds: matchedMeds));
    }
  }
  return found;
}

String interactionLevelMm(String level) => switch (level) {
      'high' => '🔴 ပြင်းထန်',
      'medium' => '🟡 အလယ်အလတ်',
      'low' => '🟢 နည်း',
      _ => level,
    };

// ---------------- period (web: calcPeriodSummary) ----------------

class PeriodSummary {
  const PeriodSummary({
    required this.count,
    required this.logs,
    this.last,
    this.avg,
    this.next,
    this.daysLeft,
  });
  final int count;
  final List<Map<String, dynamic>> logs; // oldest first
  final String? last;
  final int? avg;
  final String? next;
  final int? daysLeft;
}

/// Shared by the Period tab and the Profile tab auto-section.
/// Diffs use the first (oldest) up-to-3 gaps; prediction is from the most
/// recent entry — exactly as the web app does.
PeriodSummary calcPeriodSummary(LocalStore local, String profileId) {
  // Entries with a missing/non-string start date are dropped rather
  // than crashing the sort (same hostile-shape class as the blank tabs).
  final logs = local
      .list('periodLog')
      .where((x) =>
          x['profileId'] == profileId && strVal(x['start']).isNotEmpty)
      .toList()
    ..sort((a, b) => strVal(a['start']).compareTo(strVal(b['start'])));
  if (logs.isEmpty) return PeriodSummary(count: 0, logs: logs);
  final last = strVal(logs.last['start']);
  if (logs.length < 2) {
    return PeriodSummary(count: logs.length, last: last, logs: logs);
  }
  final diffs = <int>[];
  final n = logs.length - 1 < 3 ? logs.length - 1 : 3;
  for (var i = 0; i < n; i++) {
    diffs.add(parseDate(strVal(logs[i + 1]['start']))
        .difference(parseDate(strVal(logs[i]['start'])))
        .inDays);
  }
  final avg = (diffs.reduce((a, b) => a + b) / diffs.length).round();
  final next = addDaysStr(last, avg);
  final daysLeft =
      parseDate(next).difference(parseDate(todayStr())).inDays;
  return PeriodSummary(
    count: logs.length,
    last: last,
    avg: avg,
    next: next,
    daysLeft: daysLeft,
    logs: logs,
  );
}

// ---------------- sleep (web: sleepDuration) ----------------

/// '7 နာရီ 30 မိနစ်' (web: sleepDuration).
String sleepDuration(Map<String, dynamic> s) {
  final bed = strVal(s['bedtime']);
  final wake = strVal(s['wakeTime']);
  if (bed.isEmpty || wake.isEmpty) return '—';
  var d = hmToMin(wake) - hmToMin(bed);
  if (d <= 0) d += 1440;
  return '${d ~/ 60} နာရီ ${d % 60} မိနစ်';
}

// ---------------- coach tips (web: tipOfDay / COACH_TIPS) ----------------

String tipOfDay() {
  final d = DateTime.now();
  final h = d.hour;
  final bucket = h < 5
      ? 'night'
      : h < 11
          ? 'morning'
          : h < 17
              ? 'day'
              : h < 22
                  ? 'evening'
                  : 'night';
  final list = coachTips[bucket]!;
  final idx = (d.year * 372 + d.month * 31 + d.day) % list.length;
  return list[idx];
}

// ---------------- plan (web: GOAL_* / buildWorkoutWeeks / generateGoalPlan) ----------------

/// 7-day exercise split into 4 weeks; minutes scale x1 / x1.15 / x1.3 / x1.3.
List<Map<String, dynamic>> buildWorkoutWeeks(String goal) {
  final base = goalWorkoutDays[goal] ?? goalWorkoutDays['maintain']!;
  return List.generate(weekTitles.length, (wi) {
    return {
      'week': 'အပတ် ${wi + 1}',
      'title': weekTitles[wi],
      'days': base
          .map((d) => {
                'day': d.day,
                'text': d.min > 0
                    ? '${d.act} ${(d.min * weekMinFactors[wi]).round()} မိနစ်'
                    : d.act,
                'alt': d.alt,
              })
          .toList(),
    };
  });
}

/// Offline goal plan (web: generateGoalPlan) — the user's dictated format.
/// Returns the plan map to store under plans[profileId].
Map<String, dynamic> generateGoalPlan(
  HealthProfile p,
  String goal,
  String bedtime,
) {
  final kcal = calorieTargetFor(
    weightKg: p.weightKg ?? 60,
    heightCm: p.heightCm ?? 160,
    age: p.age ?? 30,
    female: p.gender == 'female',
    goal: goal,
  );
  final hasDiabetes =
      p.conditions.any((c) => RegExp(r'ဆီးချို|diabetes', caseSensitive: false).hasMatch(c));
  final hasBp = p.conditions.any((c) =>
      RegExp(r'သွေးတိုး|blood pressure|hypertension', caseSensitive: false).hasMatch(c));
  final meals = (goalMeals[goal] ?? goalMeals['maintain']!)
      .map((m) => {
            'name': m.name,
            'time': m.time,
            'items': List<String>.from(m.items),
            'why': m.why,
          })
      .toList();
  if (hasDiabetes) {
    (meals[0]['items'] as List<String>)[0] = 'ပဲပြုတ်ထမင်း ၁ ပန်းကန်';
  }
  final eat = <String>[...(goalDietEat[goal] ?? goalDietEat['maintain']!)];
  if (hasDiabetes) eat.add('အချိုနည်းသော အစားအစာများ');
  if (hasBp) eat.add('ပိုတက်စီယမ်များသော ငှက်ပျောသီး');
  final avoid = <String>[...dietAvoidBase];
  if (goal == 'lose') avoid.addAll(dietAvoidLoseExtra);
  if (hasDiabetes) avoid.add('သကြား၊ မုန့်ချို');
  if (hasBp) avoid.add('ဆား၊ ငံပြာရည်များများ');
  return {
    'month': currentMonthKey(),
    'createdAt': DateTime.now().toIso8601String(),
    'ai': false,
    'goal': goal,
    'meals': meals,
    'sleep': {'bed': bedtime, 'wake': '06:00'},
    'workout': buildWorkoutWeeks(goal),
    'diet': {'eat': eat, 'avoid': avoid},
    'calorieTarget': kcal,
    'tip': goalTips[goal] ?? goalTips['maintain']!,
  };
}

/// A stored plan is valid only for the current month AND with a goal field
/// (old-format plans without `goal` count as not generated).
Map<String, dynamic>? validPlan(
  LocalStore local,
  String profileId,
  String monthKey,
) {
  final plan = local.map('plans')[profileId];
  if (plan is Map && plan['month'] == monthKey && plan['goal'] != null) {
    return plan.cast<String, dynamic>();
  }
  return null;
}

Future<void> savePlan(
  LocalStore local,
  String profileId,
  Map<String, dynamic> plan,
) async {
  final plans = local.map('plans');
  plans[profileId] = plan;
  local.db['plans'] = plans;
  await local.markDirty('plans');
  await local.save();
}

Future<void> deletePlan(LocalStore local, String profileId) async {
  final plans = local.map('plans');
  plans.remove(profileId);
  local.db['plans'] = plans;
  await local.markDirty('plans');
  await local.save();
}

/// One food-group box per meal item: 'Label — options' splits into a labeled
/// box; a plain item becomes a box on its own (web: foodBoxHtml).
({String? label, String body}) foodBoxParts(String item) {
  final parts = item.split(' — ');
  if (parts.length > 1) {
    return (label: parts[0], body: parts.sublist(1).join(' — '));
  }
  return (label: null, body: item);
}

/// Day-by-day guide for the current date, derived from the stored plan
/// (web: todayGuide). Week = ceil(date/7), day Mon=0..Sun=6.
({
  String weekLabel,
  String? dayLabel,
  String? dayText,
  String? dayAlt,
  int calorieTarget,
  List<Map<String, dynamic>> meals,
})? todayGuide(Map<String, dynamic> plan) {
  final workout = (plan['workout'] as List?)?.cast<Map<String, dynamic>>();
  final meals = (plan['meals'] as List?)?.cast<Map<String, dynamic>>();
  if (workout == null || workout.isEmpty || meals == null) return null;
  final now = DateTime.now();
  final weekIndex =
      ((now.day / 7).ceil() - 1).clamp(0, workout.length - 1);
  final wk = workout[weekIndex];
  final days = (wk['days'] as List?)?.cast<Map<String, dynamic>>();
  final di = (now.weekday - 1) % 7; // Mon=0 .. Sun=6
  final day = (days != null && di < days.length) ? days[di] : null;
  return (
    weekLabel: "${wk['week'] as String}${wk['title'] != null ? ' — ${wk['title']}' : ''}",
    dayLabel: day?['day'] as String?,
    dayText: day?['text'] as String?,
    dayAlt: day?['alt'] as String?,
    calorieTarget: toInt(plan['calorieTarget']) ?? 0,
    meals: meals,
  );
}

/// Exercise alternatives (squat/push-up -> chair/wall) show only when the
/// profile age is >= 40 (web: showAlt).
bool showAltFor(HealthProfile? p) => (p?.age ?? 0) >= 40;

// ---------------- AI plan validation (web: planHeaderHits / planOutputOk) ----------------

const List<String> planHeaders = ['ကယ်လိုရီ', 'စားသောက်ချိန်', 'လေ့ကျင့်ခန်း', 'လမ်းညွှန်'];

int planHeaderHits(String ans) =>
    planHeaders.where((h) => ans.contains(h)).length;

bool planOutputOk(String ans) {
  final a = ans.replaceAll(
    RegExp(r'\b(kcal|kg|cm|min|AM|PM)\b', caseSensitive: false),
    '',
  );
  return planHeaderHits(a) >= 2 && !RegExp(r'[A-Za-z]{4,}').hasMatch(a);
}

// ---------------- weight auto-sync (web: renderProgress weight save) ----------------

/// After adding a weight log, sync the profile weight to the newest entry
/// by date (back-filling an old date does not touch the profile).
Future<void> syncProfileWeightFromLog(
  LocalStore local,
  HealthProfile p,
) async {
  final logs = local
      .list('weightLog')
      .where((x) => x['profileId'] == p.id)
      .toList()
    ..sort((a, b) => strVal(a['date']).compareTo(strVal(b['date'])));
  if (logs.isEmpty) return;
  final latest = logs.last;
  p.weightKg = toDouble(latest['weight']);
  p.updatedAt = DateTime.now().millisecondsSinceEpoch;
  await local.upsert('profiles', p.toJson());
}

/// Add water and save (web: addWater).
Future<void> addWater(LocalStore local, int ml) async {
  final t = todayStr();
  final wl = local.map('waterLog');
  wl[t] = (toInt(wl[t]) ?? 0) + ml;
  local.db['waterLog'] = wl;
  await local.markDirty('waterLog');
  await local.save();
}
