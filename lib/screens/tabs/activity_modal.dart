// Shared activity modal (web: openStepsModal) — used by the Home tab
// ("ခြေလှမ်းထည့်ရန်") and the Reminders tab ("ပြင်/ထည့်မယ်").
// Logs ONE exercise session per save; each save ADDS to today's
// activityLog record (steps/minutes/kcal accumulate) instead of
// replacing it, so several sessions in a day show as a daily total.
// The fields start empty for a fresh session; today's running total is
// shown as a reference line above them.
import 'package:flutter/material.dart';

import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../services/local_store.dart';
import 'tab_common.dart';

/// Merge one exercise session into today's activity record.
/// If [existing] is null, returns a new record; otherwise ADDS the
/// session's steps/minutes/kcal to the running total (several sessions
/// in a day accumulate) and keeps the exercise type of the longer
/// session (dominant activity).
Map<String, dynamic> mergeActivitySession({
  required Map<String, dynamic>? existing,
  required String profileId,
  required String date,
  required int steps,
  required int minutes,
  required int exerciseType,
  required double weightKg,
}) {
  final k = activityKcal(
    steps: steps,
    exerciseType: exerciseType,
    minutes: minutes,
    weightKg: weightKg,
  );
  if (existing == null) {
    return {
      'id': newId(),
      'profileId': profileId,
      'date': date,
      'steps': steps,
      'minutes': minutes,
      'exerciseType': exerciseType,
      'stepsKcal': k.stepsKcal,
      'exKcal': k.exKcal,
      'kcal': k.total,
      'source': 'manual',
    };
  }
  final prevSteps = toInt(existing['steps']) ?? 0;
  final prevMins = toInt(existing['minutes']) ?? 0;
  final prevStepsKcal = toInt(existing['stepsKcal']) ?? 0;
  final prevExKcal = toInt(existing['exKcal']) ?? 0;
  final totalStepsKcal = prevStepsKcal + k.stepsKcal;
  final totalExKcal = prevExKcal + k.exKcal;
  final keepType = prevMins >= minutes
      ? (toInt(existing['exerciseType']) ?? 1)
      : exerciseType;
  return Map<String, dynamic>.from(existing)
    ..['steps'] = prevSteps + steps
    ..['minutes'] = prevMins + minutes
    ..['exerciseType'] = keepType
    ..['stepsKcal'] = totalStepsKcal
    ..['exKcal'] = totalExKcal
    ..['kcal'] = totalStepsKcal + totalExKcal
    ..['source'] = 'manual';
}

Future<void> showActivityModal(
  BuildContext context,
  LocalStore local,
  HealthProfile p, {
  VoidCallback? onSaved,
}) async {
  final t = todayStr();
  final w = p.weightKg ?? 60;
  final existing = local.list('activityLog').where(
    (a) => a['profileId'] == p.id && a['date'] == t,
  );
  final ex = existing.isEmpty ? null : existing.first;
  // Fresh session each time the modal opens — do NOT pre-fill with
  // today's totals, or saving would double-count them.
  final stepsCtrl = TextEditingController();
  final minsCtrl = TextEditingController();
  var exType = 1;

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setD) {
          int steps = int.tryParse(stepsCtrl.text) ?? 0;
          int mins = int.tryParse(minsCtrl.text) ?? 0;
          final k = activityKcal(
            steps: steps,
            exerciseType: exType,
            minutes: mins,
            weightKg: w,
          );
          final e = (exType >= 0 && exType < exerciseBurn.length)
              ? exerciseBurn[exType]
              : exerciseBurn[1];
          return AlertDialog(
            title: const Text('🚶 ဒီနေ့ လှုပ်ရှားမှု'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ex != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'ဒီနေ့ စုစုပေါင်း: ခြေလှမ်း ${toInt(ex['steps']) ?? 0} · ${toInt(ex['minutes']) ?? 0} မိနစ် · ~${toInt(ex['kcal']) ?? 0} kcal',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  const Text('ခြေလှမ်း အရေအတွက်'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: stepsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'ဥပမာ 5000',
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 12),
                  const Text('လေ့ကျင့်ခန်း အမျိုးအစား'),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    key: ValueKey(exType),
                    initialValue: exType,
                    isExpanded: true,
                    items: [
                      for (var i = 0; i < exerciseBurn.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(exerciseBurn[i].name),
                        ),
                    ],
                    onChanged: (v) => setD(() => exType = v ?? 1),
                  ),
                  const SizedBox(height: 12),
                  const Text('လေ့ကျင့်ခန်း (မိနစ်)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: minsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'ဥပမာ 30',
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '🔥 လောင်ကျွမ်းမည့် ကယ်လိုရီ (ခန့်မှန်း): ~${k.total} kcal (ခြေလှမ်း ~${k.stepsKcal} + ${e.name} ~${k.exKcal})',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '📱 APK မှာ Health Connect နဲ့ ချိတ်ရင် ခြေလှမ်း နဲ့ လေ့ကျင့်ခန်း အလိုလို ရောက်လာမယ်',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('မလုပ်ဘူး'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final merged = mergeActivitySession(
                    existing: ex,
                    profileId: p.id,
                    date: t,
                    steps: steps,
                    minutes: mins,
                    exerciseType: exType,
                    weightKg: w,
                  );
                  await local.upsert('activityLog', merged);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    showToast(context, 'မှတ်တမ်းတင်ပြီးပါပြီ ✅');
                  }
                  onSaved?.call();
                },
                child: const Text('သိမ်းမယ်'),
              ),
            ],
          );
        },
      );
    },
  );
}
