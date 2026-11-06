// 📊 တိုးတက်မှု (Progress) — faithful port of renderProgress in
// ~/workspace/health-app/app.js. Every Burmese string is copied from app.js.
// Weight chart + add-weight modal (with profile weight auto-sync), BMI chart,
// 7-day summary table with the same formulas as the web app.
import 'package:flutter/material.dart';

import '../../models/health_data.dart';
import 'line_chart.dart';
import 'tab_common.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> with TabLoader<ProgressTab> {
  Future<void> _showAddWeightModal(HealthProfile p) async {
    var dateStr = todayStr();
    final weightCtrl = TextEditingController();
    final waistCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: const Text('⚖️ ကိုယ်အလေးချိန် မှတ်တမ်း'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('နေ့'),
                    const SizedBox(height: 4),
                    OutlinedButton(
                      onPressed: () async {
                        final picked = await pickDateStr(ctx, dateStr);
                        if (picked != null) setD(() => dateStr = picked);
                      },
                      child: Text(fmtDateMm(dateStr)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('အလေးချိန် (kg) *'),
                              const SizedBox(height: 4),
                              TextField(
                                controller: weightCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'ဥပမာ 65.5',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ခါးပတ်လည် (လက်မ)'),
                              const SizedBox(height: 4),
                              TextField(
                                controller: waistCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'ဥပမာ 32',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                    final w = double.tryParse(weightCtrl.text.trim());
                    if (w == null || w <= 0) {
                      showToast(context, 'အလေးချိန် မှန်အောင်ထည့်ပါ');
                      return;
                    }
                    final wd = dateStr.isEmpty ? todayStr() : dateStr;
                    await local.upsert('weightLog', {
                      'id': newId(),
                      'profileId': p.id,
                      'date': wd,
                      'weight': w,
                      'waist': waistCtrl.text.trim(),
                    });
                    // AUTO-SYNC (web comment 2026-11-05): profile weight
                    // follows the newest log by date; back-filling an old
                    // date does not touch the profile.
                    await syncProfileWeightFromLog(local, p);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    showToast(context, 'မှတ်တမ်းတင်ပြီးပါပြီ ✅');
                    refresh();
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

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final p = activeProfile;
    if (p == null) {
      return const Center(child: Text('Profile မရှိသေးပါ'));
    }

    final wl = local
        .list('weightLog')
        .where((w) => w['profileId'] == p.id)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    final h = p.heightCm ?? 0;

    // 7-day summary (same formulas as renderProgress).
    final days = <String>[];
    for (var i = 6; i >= 0; i--) {
      days.add(addDaysStr(todayStr(), -i));
    }
    var kcalSum = 0;
    var waterSum = 0;
    var stepsSum = 0;
    var qSum = 0.0;
    var qN = 0;
    var taken = 0;
    var total = 0;
    for (final d in days) {
      kcalSum += local
          .list('foodLog')
          .where((f) => f['profileId'] == p.id && f['date'] == d)
          .fold<int>(0, (a, f) => a + (toInt(f['kcal']) ?? 0));
      waterSum += toInt(local.map('waterLog')[d]) ?? 0;
      final a = local
          .list('activityLog')
          .where((x) => x['profileId'] == p.id && x['date'] == d)
          .firstOrNull;
      if (a != null) stepsSum += toInt(a['steps']) ?? 0;
      for (final s in local
          .list('sleepLog')
          .where((s) => s['profileId'] == p.id && s['date'] == d)) {
        qSum += toDouble(s['quality']) ?? 0;
        qN++;
      }
      final sched = todaysMedSchedule(local, p.id, d);
      for (final s in sched) {
        total++;
        if (s.status == 'taken') taken++;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Weight chart + add button.
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
                      '⚖️ ကိုယ်အလေးချိန် မှတ်တမ်း',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    OutlinedButton(
                      onPressed: () => _showAddWeightModal(p),
                      child: const Text('＋ ထည့်မယ်'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SimpleLineChart(
                  series: [
                    ChartSeries(
                      label: 'ကိုယ်အလေးချိန် (kg)',
                      color: const Color(0xFF1F6FB2),
                      points: wl
                          .map((w) => ChartPoint(
                                (w['date'] as String).substring(5),
                                toDouble(w['weight']),
                              ))
                          .toList(),
                    ),
                  ],
                  unit: 'kg',
                ),
              ],
            ),
          ),
        ),
        // BMI chart.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📏 BMI မှတ်တမ်း',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SimpleLineChart(
                  series: [
                    ChartSeries(
                      label: 'BMI',
                      color: const Color(0xFF1F6FB2),
                      points: wl
                          .where((_) => h > 0)
                          .map((w) => ChartPoint(
                                (w['date'] as String).substring(5),
                                (toDouble(w['weight']) ?? 0) /
                                    ((h / 100) * (h / 100)),
                              ))
                          .toList(),
                    ),
                  ],
                  unit: '',
                ),
              ],
            ),
          ),
        ),
        // 7-day summary.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🗓️ ၇ ရက်အကျဉ်းချုပ်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1),
                  },
                  children: [
                    _summaryRow(
                      'ပျမ်းမျှ ကယ်လိုရီ/နေ့',
                      '${(kcalSum / 7).round()} kcal',
                    ),
                    _summaryRow(
                      'ပျမ်းမျှ ရေ/နေ့',
                      '${(waterSum / 7).round()} ml',
                    ),
                    _summaryRow('စုစုပေါင်း ခြေလှမ်း', '$stepsSum'),
                    _summaryRow(
                      'ပျမ်းမျှ အိပ်စက်မှု အရည်အသွေး',
                      qN > 0 ? '${(qSum / qN).toStringAsFixed(1)} / 5' : '—',
                    ),
                    _summaryRow(
                      'ဆေးသောက်မှန်ကန်မှု',
                      total > 0 ? '${(taken / total * 100).round()}%' : '—',
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

  TableRow _summaryRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
