// Shared activity modal (web: openStepsModal) — used by the Home tab
// ("ခြေလှမ်းထည့်ရန်") and the Reminders tab ("ပြင်/ထည့်မယ်").
// Steps + exercise type + minutes, with a live kcal preview; saves one
// activityLog record per profile per day (source 'manual').
import 'package:flutter/material.dart';

import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../services/local_store.dart';
import 'tab_common.dart';

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
  final stepsCtrl = TextEditingController(
    text: ex != null ? '${ex['steps'] ?? ''}' : '',
  );
  final minsCtrl = TextEditingController(
    text: ex != null ? '${ex['minutes'] ?? ''}' : '',
  );
  var exType = toInt(ex?['exerciseType']) ?? 1;

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
                  final rec = {
                    'steps': steps,
                    'minutes': mins,
                    'exerciseType': exType,
                    'stepsKcal': k.stepsKcal,
                    'exKcal': k.exKcal,
                    'kcal': k.total,
                    'source': 'manual',
                  };
                  if (ex != null) {
                    final updated = Map<String, dynamic>.from(ex)
                      ..addAll(rec);
                    await local.upsert('activityLog', updated);
                  } else {
                    await local.upsert('activityLog', {
                      'id': newId(),
                      'profileId': p.id,
                      'date': t,
                      ...rec,
                    });
                  }
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
