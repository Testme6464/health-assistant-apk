// 🖨️ ဆရာဝန်ပြရန် အစီရင်ခံစာ — faithful port of web renderReport
// (~/workspace/health-app/app.js). Every Burmese string is copied from
// app.js, never typed from memory. The web's window.print() becomes SHARE
// (the native equivalent): '📤 မျှဝေမယ်' shares the same content as plain
// text, '📋 ကူးယူမယ်' copies it to the clipboard.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/health_data.dart';
import 'tab_common.dart';

class ReportTab extends StatefulWidget {
  const ReportTab({super.key});

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> with TabLoader<ReportTab> {
  /// JS-style number printing: 81 not 81.0.
  String _num(num v) =>
      v is double && v == v.truncateToDouble() ? '${v.toInt()}' : '$v';

  /// All report values, computed once per build and shared by the UI and
  /// the share/copy plain text.
  _ReportData _compute(HealthProfile p) {
    final t = todayStr();
    final bmi = calcBmi(heightCm: p.heightCm, weightKg: p.weightKg);
    final bmiStr =
        bmi == null ? '—' : '${bmi.toStringAsFixed(1)} (${bmiLabel(bmi)})';

    final weightLogs = local
        .list('weightLog')
        .where((w) => w['profileId'] == p.id && w['deleted'] != true)
        .toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    final lastW = weightLogs.isEmpty ? null : weightLogs.first;
    final heightWeight =
        '${p.heightCm == null ? '—' : _num(p.heightCm!)} cm / ${lastW != null ? '${_num(toNum(lastW['weight']) ?? 0)} kg (${fmtDateMm((lastW['date'] as String?) ?? '')})' : '${p.weightKg == null ? '—' : _num(p.weightKg!)} kg'}';
    final ageGender =
        '${p.age ?? '—'} / ${p.gender == 'male' ? 'ကျား' : p.gender == 'female' ? 'မ' : '—'}';

    final meds = local
        .list('meds')
        .where((m) => m['profileId'] == p.id && m['deleted'] != true)
        .toList();

    var kcal7 = 0;
    var water7 = 0;
    for (var i = 0; i < 7; i++) {
      final d = addDaysStr(t, -i);
      kcal7 += local
          .list('foodLog')
          .where(
            (f) =>
                f['profileId'] == p.id &&
                f['date'] == d &&
                f['deleted'] != true,
          )
          .fold<int>(0, (a, f) => a + (toInt(f['kcal']) ?? 0));
      water7 += toInt(local.map('waterLog')[d]) ?? 0;
    }
    final avgKcal = (kcal7 / 7).round();
    final avgWater = (water7 / 7).round();
    final settings = local.map('settings');
    final kcalTarget = p.calorieTarget(
      manualTarget: toInt(settings['calorieTarget']),
      manualMode: settings['calorieTargetMode'] == 'manual',
    );

    final recentSleep = local
        .list('sleepLog')
        .where((s) => s['profileId'] == p.id && s['deleted'] != true)
        .toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    final sleep7 = recentSleep.take(7).toList();

    final recentSym = local
        .list('symptoms')
        .where((s) => s['profileId'] == p.id && s['deleted'] != true)
        .toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    final sym10 = recentSym.take(10).toList();

    return _ReportData(
      dateLabel: fmtDateMm(t),
      name: p.name,
      ageGender: ageGender,
      heightWeight: heightWeight,
      bmiStr: bmiStr,
      bloodType: p.bloodType.isEmpty ? '—' : p.bloodType,
      conditions: p.conditions.isEmpty ? '—' : p.conditions.join(', '),
      familyHistory:
          p.familyHistory.isEmpty ? '—' : p.familyHistory.join(', '),
      allergies: p.allergies.isEmpty ? '—' : p.allergies.join(', '),
      meds: meds,
      avgKcal: avgKcal,
      kcalTarget: kcalTarget,
      avgWater: avgWater,
      sleep7: sleep7,
      sym10: sym10,
    );
  }

  String _reportText(_ReportData d) {
    final b = StringBuffer();
    b.writeln('ကျန်းမာရေး အစီရင်ခံစာ');
    b.writeln('ရက်စွဲ: ${d.dateLabel}');
    b.writeln();
    b.writeln('👤 လူနာ အချက်အလက်');
    b.writeln('အမည်: ${d.name}');
    b.writeln('အသက် / ကျား-မ: ${d.ageGender}');
    b.writeln('အရပ် / အလေးချိန်: ${d.heightWeight}');
    b.writeln('BMI: ${d.bmiStr}');
    b.writeln('သွေးအမျိုးအစား: ${d.bloodType}');
    b.writeln('နာတာရှည်ရောဂါ: ${d.conditions}');
    b.writeln('မျိုးရိုးရောဂါ: ${d.familyHistory}');
    b.writeln('ဓာတ်မတည့်မှု: ${d.allergies}');
    b.writeln();
    b.writeln('💊 လက်ရှိသောက်နေသောဆေးများ');
    if (d.meds.isEmpty) {
      b.writeln('မရှိပါ');
    } else {
      for (final m in d.meds) {
        final times = ((m['times'] as List?) ?? [])
            .map((e) => fmtTimeMm('$e'))
            .join(', ');
        b.writeln(
          "- ${m['name']} — ${(m['dosage'] as String?)?.isNotEmpty == true ? m['dosage'] : '—'} — $times — ${(m['reason'] as String?)?.isNotEmpty == true ? m['reason'] : '—'}",
        );
      }
    }
    b.writeln();
    b.writeln('📊 ၇ ရက်အတွင်း အကျဉ်းချုပ်');
    b.writeln(
      'ပျမ်းမျှ ကယ်လိုရီ: ${d.avgKcal} kcal/နေ့ (ရည်မှန်း ${d.kcalTarget})',
    );
    b.writeln('ပျမ်းမျှ ရေ: ${d.avgWater} ml/နေ့');
    b.writeln('အိပ်စက်မှု:');
    if (d.sleep7.isEmpty) {
      b.writeln('မှတ်တမ်း မရှိ');
    } else {
      for (final s in d.sleep7) {
        b.writeln(_sleepLine(s));
      }
    }
    b.writeln();
    b.writeln('📝 နောက်ဆုံး လက္ခဏာများ');
    if (d.sym10.isEmpty) {
      b.writeln('မရှိပါ');
    } else {
      for (final s in d.sym10) {
        b.writeln(
          "- ${fmtDateMm((s['date'] as String?) ?? '')}: ${s['name']}${(s['note'] as String?)?.isNotEmpty == true ? ' (${s['note']})' : ''} — ${s['severity']}/5",
        );
      }
    }
    b.writeln();
    b.writeln(
      '⚠️ ဒီအစီရင်ခံစာကို app မှတ်တမ်းများမှ အလိုအလျောက် ထုတ်လုပ်ထားခြင်းဖြစ်ပြီး ဆေးပညာအကြံဉာဏ် မဟုတ်ပါ။',
    );
    return b.toString();
  }

  String _sleepLine(Map<String, dynamic> s) =>
      '${fmtDateMm((s['date'] as String?) ?? '')}: ${sleepDuration(s)} (အရည်အသွေး ${s['quality']}/5${(s['nightmare'] as bool?) == true ? ', အိပ်မက်ဆိုး' : ''})';

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final p = activeProfile;
    if (p == null) {
      return const Center(child: Text('Profile မရှိသေးပါ'));
    }
    final d = _compute(p);
    final text = _reportText(d);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header card (web: print button -> native SHARE).
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🖨️ ဆရာဝန်ပြရန် အစီရင်ခံစာ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'အောက်ပါ အကျဉ်းချုပ်ကို ဆရာဝန်ထံ ယူသွားနိုင်ပါတယ်',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          SharePlus.instance.share(
                            ShareParams(
                              text: text,
                              subject: 'ကျန်းမာရေး အစီရင်ခံစာ',
                            ),
                          );
                        },
                        child: const Text('📤 မျှဝေမယ်'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            showToast(context, 'ကူးယူပြီးပါပြီ ✅');
                          }
                        },
                        child: const Text('📋 ကူးယူမယ်'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Patient info.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '👤 လူနာ အချက်အလက် (${d.dateLabel})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _infoRow('အမည်', d.name),
                _infoRow('အသက် / ကျား-မ', d.ageGender),
                _infoRow('အရပ် / အလေးချိန်', d.heightWeight),
                _infoRow('BMI', d.bmiStr),
                _infoRow('သွေးအမျိုးအစား', d.bloodType),
                _infoRow('နာတာရှည်ရောဂါ', d.conditions),
                _infoRow('မျိုးရိုးရောဂါ', d.familyHistory),
                _infoRow('ဓာတ်မတည့်မှု', d.allergies),
              ],
            ),
          ),
        ),
        // Current meds.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💊 လက်ရှိသောက်နေသောဆေးများ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (d.meds.isEmpty)
                  const Text('မရှိပါ', style: TextStyle(color: Colors.grey))
                else
                  Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Colors.grey.shade300,
                      ),
                    ),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                    },
                    children: [
                      const TableRow(
                        children: [
                          _Cell('ဆေး', bold: true),
                          _Cell('ပမာဏ', bold: true),
                          _Cell('အချိန်', bold: true),
                          _Cell('အကြောင်းအရင်း', bold: true),
                        ],
                      ),
                      for (final m in d.meds)
                        TableRow(
                          children: [
                            _Cell('${m['name']}'),
                            _Cell(
                              (m['dosage'] as String?)?.isNotEmpty == true
                                  ? '${m['dosage']}'
                                  : '—',
                            ),
                            _Cell(
                              ((m['times'] as List?) ?? [])
                                  .map((e) => fmtTimeMm('$e'))
                                  .join(', '),
                            ),
                            _Cell(
                              (m['reason'] as String?)?.isNotEmpty == true
                                  ? '${m['reason']}'
                                  : '—',
                            ),
                          ],
                        ),
                    ],
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
                  '📊 ၇ ရက်အတွင်း အကျဉ်းချုပ်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _infoRow(
                  'ပျမ်းမျှ ကယ်လိုရီ',
                  '${d.avgKcal} kcal/နေ့ (ရည်မှန်း ${d.kcalTarget})',
                ),
                _infoRow('ပျမ်းမျှ ရေ', '${d.avgWater} ml/နေ့'),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 140,
                      child: Text(
                        'အိပ်စက်မှု',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: d.sleep7.isEmpty
                          ? const Text('မှတ်တမ်း မရှိ')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final s in d.sleep7)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(_sleepLine(s)),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Recent symptoms.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📝 နောက်ဆုံး လက္ခဏာများ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (d.sym10.isEmpty)
                  const Text('မရှိပါ', style: TextStyle(color: Colors.grey))
                else
                  Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Colors.grey.shade300,
                      ),
                    ),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(3),
                      2: FlexColumnWidth(1),
                    },
                    children: [
                      const TableRow(
                        children: [
                          _Cell('နေ့', bold: true),
                          _Cell('လက္ခဏာ', bold: true),
                          _Cell('ပြင်းထန်မှု', bold: true),
                        ],
                      ),
                      for (final s in d.sym10)
                        TableRow(
                          children: [
                            _Cell(
                              fmtDateMm((s['date'] as String?) ?? ''),
                            ),
                            _Cell(
                              '${s['name']}${(s['note'] as String?)?.isNotEmpty == true ? ' (${s['note']})' : ''}',
                            ),
                            _Cell('${s['severity']}/5'),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const Text(
          '⚠️ ဒီအစီရင်ခံစာကို app မှတ်တမ်းများမှ အလိုအလျောက် ထုတ်လုပ်ထားခြင်းဖြစ်ပြီး ဆေးပညာအကြံဉာဏ် မဟုတ်ပါ။',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ReportData {
  const _ReportData({
    required this.dateLabel,
    required this.name,
    required this.ageGender,
    required this.heightWeight,
    required this.bmiStr,
    required this.bloodType,
    required this.conditions,
    required this.familyHistory,
    required this.allergies,
    required this.meds,
    required this.avgKcal,
    required this.kcalTarget,
    required this.avgWater,
    required this.sleep7,
    required this.sym10,
  });
  final String dateLabel;
  final String name;
  final String ageGender;
  final String heightWeight;
  final String bmiStr;
  final String bloodType;
  final String conditions;
  final String familyHistory;
  final String allergies;
  final List<Map<String, dynamic>> meds;
  final int avgKcal;
  final int kcalTarget;
  final int avgWater;
  final List<Map<String, dynamic>> sleep7;
  final List<Map<String, dynamic>> sym10;
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false});
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Text(
        text,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    );
  }
}
