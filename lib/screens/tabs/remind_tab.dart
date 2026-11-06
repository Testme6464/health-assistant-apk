// ⏰ သတိပေးချက်များ — faithful port of web renderRemind / openSleepModal /
// scheduleCheck (~/workspace/health-app/app.js). Every Burmese string is
// copied from app.js, never typed from memory. App-open reminders only:
// a 1-minute timer shows a SnackBar when a reminder is due; there are no
// background notifications here (that is a later step) and no notification
// plugin is used.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../theme.dart';
import 'activity_modal.dart';
import 'tab_common.dart';

class RemindTab extends StatefulWidget {
  const RemindTab({super.key});

  @override
  State<RemindTab> createState() => _RemindTabState();
}

class _RemindTabState extends State<RemindTab> with TabLoader<RemindTab> {
  Timer? _timer;

  /// Fired-reminder keys for the current day (web: sessionStorage fired_*).
  final Set<String> _fired = {};
  String _firedDay = '';
  bool _didInitialCheck = false;

  // ---- reminder-settings form state (initialised from DB.reminders) ----
  bool _settingsInit = false;
  bool _waterEnabled = true;
  bool _medEnabled = true;
  bool _sleepEnabled = true;
  final TextEditingController _intervalCtrl = TextEditingController();
  String _waterStart = '08:00';
  String _waterEnd = '21:00';
  String _bedtime = '22:30';

  // ---- meal-plan form state ----
  String _mpDate = todayStr();
  String _mpTime = '12:00';
  final TextEditingController _mpWhatCtrl = TextEditingController();

  // ---- custom water amount ----
  final TextEditingController _waterCustomCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkReminders(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _intervalCtrl.dispose();
    _mpWhatCtrl.dispose();
    _waterCustomCtrl.dispose();
    super.dispose();
  }

  void _initSettingsFromDb() {
    final r = local.map('reminders');
    _waterEnabled = (r['waterEnabled'] as bool?) ?? true;
    _medEnabled = (r['medEnabled'] as bool?) ?? true;
    _sleepEnabled = (r['sleepEnabled'] as bool?) ?? true;
    _intervalCtrl.text = '${toInt(r['waterInterval']) ?? 120}';
    _waterStart = (r['waterStart'] as String?) ?? '08:00';
    _waterEnd = (r['waterEnd'] as String?) ?? '21:00';
    _bedtime = (r['bedtime'] as String?) ?? '22:30';
    _settingsInit = true;
  }

  // ---------------- in-app reminder checker (web: scheduleCheck) ----------------

  /// Web fireNotif(): toast(title + ' — ' + body), plus a system
  /// Notification when granted. Here only the in-app toast exists.
  void _fireNotif(String title, String body) {
    if (!mounted) return;
    showToast(context, '$title — $body');
  }

  void _checkReminders() {
    if (!mounted || !loaded) return;
    final p = activeProfile;
    if (p == null) return;
    final t = todayStr();
    if (_firedDay != t) {
      _firedDay = t;
      _fired.clear();
    }
    final r = local.map('reminders');
    final mins = hmToMin(nowHm());
    final interval = (toInt(r['waterInterval']) ?? 120);
    final waterStart = (r['waterStart'] as String?) ?? '08:00';
    final waterEnd = (r['waterEnd'] as String?) ?? '21:00';
    final bedtime = (r['bedtime'] as String?) ?? '22:30';

    // Meds due within ±2 min and not yet taken.
    if ((r['medEnabled'] as bool?) ?? true) {
      for (final dose in todaysMedSchedule(local, p.id, t)) {
        final k = "med_${dose.med['id']}_${dose.time}";
        if (!_fired.contains(k) &&
            (mins - hmToMin(dose.time)).abs() <= 2 &&
            dose.status != 'taken') {
          final dosage = (dose.med['dosage'] as String?) ?? '';
          _fireNotif(
            '💊 ဆေးသောက်ချိန်',
            "${dose.med['name']}${dosage.isNotEmpty ? ' ($dosage)' : ''} သောက်ဖို့ အချိန်ရောက်ပါပြီ",
          );
          _fired.add(k);
        }
      }
    }
    // Water interval tick inside the enabled window.
    if ((r['waterEnabled'] as bool?) ?? true) {
      if (interval > 0) {
        final k = 'water_${mins ~/ interval}';
        if (!_fired.contains(k) &&
            mins >= hmToMin(waterStart) &&
            mins <= hmToMin(waterEnd) &&
            (mins % interval) <= 2) {
          _fireNotif('💧 ရေသောက်ပါ', 'ရေဓာတ်ပြည့်ဝဖို့ ရေတစ်ခွက် သောက်လိုက်ပါ');
          _fired.add(k);
        }
      }
    }
    // Bedtime within ±2 min.
    if ((r['sleepEnabled'] as bool?) ?? true) {
      const kPrefix = 'sleep_';
      final k = '$kPrefix$t';
      if (!_fired.contains(k) && (mins - hmToMin(bedtime)).abs() <= 2) {
        _fireNotif(
          '😴 အိပ်ချိန်ရောက်ပါပြီ',
          'အိပ်ရာဝင်ဖို့ ပြင်ဆင်လိုက်ပါ — မနက်ဖြန် လန်းဆန်းပါစေ',
        );
        _fired.add(k);
      }
    }
    // Scheduled meal plans (today, within ±2 min).
    for (final m in local.list('mealPlans').where(
      (m) => m['profileId'] == p.id && m['deleted'] != true && m['date'] == t,
    )) {
      final k = "meal_${m['id']}";
      if (!_fired.contains(k) &&
          (mins - hmToMin((m['time'] as String?) ?? '')).abs() <= 2) {
        _fireNotif(
          '🍽️ အစားအသောက် အချိန်ရောက်ပါပြီ',
          "${m['what']} စားဖို့ အချိန်ရောက်ပါပြီ",
        );
        _fired.add(k);
      }
    }
    // Refill alerts (once per day, in-app).
    final rk = 'refill_$t';
    if (!_fired.contains(rk)) {
      final low = local
          .list('meds')
          .where((m) => m['profileId'] == p.id && m['deleted'] != true)
          .map((m) => (name: '${m['name']}', left: medSupplyLeft(m)))
          .where((x) => x.left != null && x.left! <= 7 && x.left! >= 0)
          .toList();
      if (low.isNotEmpty) {
        _fireNotif(
          '⚠️ ဆေးကုန်ခါနီးပါပြီ',
          low.map((x) => '${x.name} (${x.left} ရက်စာ)').join(', '),
        );
        _fired.add(rk);
      }
    }
  }

  // ---------------- actions ----------------

  Future<void> _saveReminders() async {
    final r = local.map('reminders');
    r['waterEnabled'] = _waterEnabled;
    // Web: Math.max(30, parseInt(value, 10) || 120).
    final parsed = int.tryParse(_intervalCtrl.text.trim()) ?? 120;
    r['waterInterval'] = parsed < 30 ? 30 : parsed;
    r['waterStart'] = _waterStart.isEmpty ? '08:00' : _waterStart;
    r['waterEnd'] = _waterEnd.isEmpty ? '21:00' : _waterEnd;
    r['medEnabled'] = _medEnabled;
    r['sleepEnabled'] = _sleepEnabled;
    r['bedtime'] = _bedtime.isEmpty ? '22:30' : _bedtime;
    local.db['reminders'] = r;
    await local.markDirty('reminders');
    await local.save();
    _checkReminders();
    if (mounted) showToast(context, 'သိမ်းပြီးပါပြီ ✅');
  }

  Future<void> _addMealPlan() async {
    final p = activeProfile;
    if (p == null) return;
    final what = _mpWhatCtrl.text.trim();
    if (what.isEmpty) {
      showToast(context, 'ဘာစားမလဲ ထည့်ပေးပါ');
      return;
    }
    await local.upsert('mealPlans', {
      'id': newId(),
      'profileId': p.id,
      'date': _mpDate.isEmpty ? todayStr() : _mpDate,
      'time': _mpTime.isEmpty ? '12:00' : _mpTime,
      'what': what,
    });
    _mpWhatCtrl.clear();
    _checkReminders();
    refresh();
    if (mounted) showToast(context, 'ကြိုမှတ်ပြီးပါပြီ ✅');
  }

  Future<void> _addCustomWater() async {
    final v = int.tryParse(_waterCustomCtrl.text.trim());
    if (v == null || v <= 0) {
      showToast(context, 'ml ပမာဏ ထည့်ပေးပါ');
      return;
    }
    await addWater(local, v);
    _waterCustomCtrl.clear();
    refresh();
  }

  Future<void> _openSleepDialog() async {
    final p = activeProfile;
    if (p == null) return;
    final r = local.map('reminders');
    var date = todayStr();
    var bed = (r['bedtime'] as String?) ?? '22:30';
    var wake = '06:00';
    var quality = 3;
    var nightmare = false;
    const qualityLabels = ['အလွန်ဆိုး', 'ဆိုး', 'သာမန်', 'ကောင်း', 'အလွန်ကောင်း'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('😴 အိပ်စက်မှု မှတ်တမ်း'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('နေ့ (အိပ်ရာဝင်သည့်နေ့)'),
                  const SizedBox(height: 4),
                  _TapField(
                    label: fmtDateMm(date),
                    onTap: () async {
                      final picked = await pickDateStr(ctx, date);
                      if (picked != null) setD(() => date = picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('အိပ်ရာဝင်ချိန်'),
                            const SizedBox(height: 4),
                            _TapField(
                              label: fmtTimeMm(bed),
                              onTap: () async {
                                final picked = await pickTimeStr(ctx, bed);
                                if (picked != null) setD(() => bed = picked);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('နိုးထချိန်'),
                            const SizedBox(height: 4),
                            _TapField(
                              label: fmtTimeMm(wake),
                              onTap: () async {
                                final picked = await pickTimeStr(ctx, wake);
                                if (picked != null) setD(() => wake = picked);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('အိပ်စက်မှု အရည်အသွေး (1–5)'),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    key: ValueKey(quality),
                    initialValue: quality,
                    isExpanded: true,
                    items: [
                      for (var n = 1; n <= 5; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Text('$n — ${qualityLabels[n - 1]}'),
                        ),
                    ],
                    onChanged: (v) => setD(() => quality = v ?? 3),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: nightmare,
                    onChanged: (v) => setD(() => nightmare = v ?? false),
                    title: const Text('😱 အိပ်မက်ဆိုး မက်ခဲ့သည်'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
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
                  await local.upsert('sleepLog', {
                    'id': newId(),
                    'profileId': p.id,
                    'date': date,
                    'bedtime': bed,
                    'wakeTime': wake,
                    'quality': quality,
                    'nightmare': nightmare,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  refresh();
                  if (mounted) {
                    showToast(context, 'မှတ်တမ်းတင်ပြီးပါပြီ ✅');
                  }
                },
                child: const Text('သိမ်းမယ်'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final p = activeProfile;
    if (p == null) {
      return const Center(child: Text('Profile မရှိသေးပါ'));
    }
    if (!_settingsInit) _initSettingsFromDb();
    if (!_didInitialCheck) {
      _didInitialCheck = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkReminders());
    }

    final t = todayStr();
    final waterToday =
        toInt(local.map('waterLog')[t]) ?? 0;
    final waterTarget =
        toInt(local.map('settings')['waterTargetMl']) ?? 2000;
    final sleeps = local
        .list('sleepLog')
        .where((s) => s['profileId'] == p.id && s['deleted'] != true)
        .toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    final last7Sleeps = sleeps.take(7).toList();
    final mealPlans = local
        .list('mealPlans')
        .where(
          (m) =>
              m['profileId'] == p.id &&
              m['deleted'] != true &&
              (m['date'] as String? ?? '').compareTo(t) >= 0,
        )
        .toList()
      ..sort(
        (a, b) =>
            ('${a['date']}${a['time']}').compareTo('${b['date']}${b['time']}'),
      );
    final act = local.list('activityLog').where(
      (a) => a['profileId'] == p.id && a['date'] == t && a['deleted'] != true,
    );
    final actRec = act.isEmpty ? null : act.first;
    final actKcal = actRec == null
        ? 0
        : activityKcal(
            steps: toInt(actRec['steps']) ?? 0,
            exerciseType: toInt(actRec['exerciseType']) ?? 1,
            minutes: toInt(actRec['minutes']) ?? 0,
            weightKg: p.weightKg ?? 60,
          ).total;
    final waterPct =
        (waterToday / waterTarget * 100).round().clamp(0, 100);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info box.
        Card(
          color: AppTheme.amberBg,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'ℹ️ App ကို ဖွင့်ထားမှ သတိပေးချက်များ ရပါမယ်။',
            ),
          ),
        ),
        // Reminder settings.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔔 သတိပေးချက် ဆက်တင်များ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                CheckboxListTile(
                  value: _waterEnabled,
                  onChanged: (v) =>
                      setState(() => _waterEnabled = v ?? false),
                  title: const Text('ရေသောက်ရန် သတိပေးမယ်'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: _intervalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ဘယ်နှစ်မိနစ်တစ်ခါ',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('အချိန်အပိုင်းအခြား'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _TapField(
                        label: fmtTimeMm(_waterStart),
                        onTap: () async {
                          final picked =
                              await pickTimeStr(context, _waterStart);
                          if (picked != null) {
                            setState(() => _waterStart = picked);
                          }
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('–'),
                    ),
                    Expanded(
                      child: _TapField(
                        label: fmtTimeMm(_waterEnd),
                        onTap: () async {
                          final picked = await pickTimeStr(context, _waterEnd);
                          if (picked != null) {
                            setState(() => _waterEnd = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  value: _medEnabled,
                  onChanged: (v) => setState(() => _medEnabled = v ?? false),
                  title: const Text('ဆေးသောက်ချိန် သတိပေးမယ်'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: _sleepEnabled,
                  onChanged: (v) =>
                      setState(() => _sleepEnabled = v ?? false),
                  title: const Text('အိပ်ရာဝင်ချိန် သတိပေးမယ်'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const Text('အိပ်ရာဝင်ချိန်'),
                const SizedBox(height: 4),
                _TapField(
                  label: fmtTimeMm(_bedtime),
                  onTap: () async {
                    final picked = await pickTimeStr(context, _bedtime);
                    if (picked != null) setState(() => _bedtime = picked);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveReminders,
                    child: const Text('💾 သိမ်းမယ်'),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Meal plans.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🍽️ အစားအသောက် ကြိုစီစဉ်မှု',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ဘယ်နေ့ ဘယ်အချိန်မှာ ဘာစားမယ် ကြိုမှတ်ထားပါ — အချိန်ရောက်ရင် သတိပေးပါမယ်',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('နေ့'),
                          const SizedBox(height: 4),
                          _TapField(
                            label: fmtDateMm(_mpDate),
                            onTap: () async {
                              final picked =
                                  await pickDateStr(context, _mpDate);
                              if (picked != null) {
                                setState(() => _mpDate = picked);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('အချိန်'),
                          const SizedBox(height: 4),
                          _TapField(
                            label: fmtTimeMm(_mpTime),
                            onTap: () async {
                              final picked =
                                  await pickTimeStr(context, _mpTime);
                              if (picked != null) {
                                setState(() => _mpTime = picked);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('ဘာစားမလဲ'),
                const SizedBox(height: 4),
                TextField(
                  controller: _mpWhatCtrl,
                  decoration: const InputDecoration(
                    hintText: 'ဥပမာ ကြက်သားဟင်း + ထမင်း',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addMealPlan,
                    child: const Text('＋ ကြိုမှတ်မယ်'),
                  ),
                ),
                const SizedBox(height: 8),
                if (mealPlans.isEmpty)
                  const Text(
                    'ကြိုစီစဉ်ထားတာ မရှိသေးပါ',
                    style: TextStyle(color: Colors.grey),
                  ),
                for (final m in mealPlans)
                  _ListRow(
                    title: '${m['what']}',
                    subtitle:
                        '${fmtDateMm((m['date'] as String?) ?? '')} · ${fmtTimeMm((m['time'] as String?) ?? '')}',
                    onDelete: () async {
                      await local.softDelete(
                        'mealPlans',
                        '${m['id']}',
                      );
                      refresh();
                    },
                  ),
              ],
            ),
          ),
        ),
        // Water log.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💧 ရေမှတ်တမ်း (ဒီနေ့ $waterToday / $waterTarget ml)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: waterPct / 100,
                  backgroundColor: AppTheme.soft,
                  color: AppTheme.primary,
                  minHeight: 8,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await addWater(local, 250);
                          refresh();
                        },
                        child: const Text('+ 250 ml'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await addWater(local, 500);
                          refresh();
                        },
                        child: const Text('+ 500 ml'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _waterCustomCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'ml ရိုက်ထည့်ရန်',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _addCustomWater,
                      child: const Text('ထည့်မယ်'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Sleep log.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '😴 အိပ်စက်မှု မှတ်တမ်း',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _openSleepDialog,
                      child: const Text('＋ ထည့်မယ်'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (last7Sleeps.isEmpty)
                  const Text(
                    'မရှိသေးပါ',
                    style: TextStyle(color: Colors.grey),
                  ),
                for (final s in last7Sleeps)
                  _ListRow(
                    title:
                        '${fmtDateMm((s['date'] as String?) ?? '')} — ${fmtTimeMm((s['bedtime'] as String?) ?? '')} → ${fmtTimeMm((s['wakeTime'] as String?) ?? '')}',
                    subtitle:
                        'ကြာချိန် ${sleepDuration(s)} · အရည်အသွေး ${'★' * (toInt(s['quality']) ?? 0)}${'☆' * (5 - (toInt(s['quality']) ?? 0))}${(s['nightmare'] as bool?) == true ? ' · 😱 အိပ်မက်ဆိုး' : ''}',
                    onDelete: () async {
                      await local.softDelete('sleepLog', '${s['id']}');
                      refresh();
                    },
                  ),
              ],
            ),
          ),
        ),
        // Today's activity.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🚶 ဒီနေ့ လှုပ်ရှားမှု',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'ခြေလှမ်း: ${actRec == null ? 0 : toInt(actRec['steps']) ?? 0} · မိနစ်: ${actRec == null ? 0 : toInt(actRec['minutes']) ?? 0} · လောင်ကျွမ်း: ~$actKcal kcal',
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => showActivityModal(
                        context,
                        local,
                        p,
                        onSaved: refresh,
                      ),
                      child: const Text('ပြင်/ထည့်မယ်'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tappable read-only field that opens a date/time picker.
class _TapField extends StatelessWidget {
  const _TapField({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label),
      ),
    );
  }
}

/// One list row with a delete button (web: list-item + 'ဖျက်မယ်').
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.title,
    required this.subtitle,
    required this.onDelete,
  });
  final String title;
  final String subtitle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.danger),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('ဖျက်မယ်'),
          ),
        ],
      ),
    );
  }
}
