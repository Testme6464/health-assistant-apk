// 📝 လက္ခဏာ (Symptom) — faithful port of renderSymptom in
// ~/workspace/health-app/app.js. Every Burmese string is copied from
// app.js, never typed from memory. Blue theme only.
import 'package:flutter/material.dart';

import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../theme.dart';
import 'tab_common.dart';

class SymptomTab extends StatefulWidget {
  const SymptomTab({super.key});

  @override
  State<SymptomTab> createState() => _SymptomTabState();
}

class _SymptomTabState extends State<SymptomTab> with TabLoader<SymptomTab> {
  String _date = todayStr();
  String _time = nowHm();
  int _severity = 2;
  TextEditingController? _nameCtrl;
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _timeCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _symptoms {
    final p = activeProfile;
    if (p == null) return [];
    return local
        .list('symptoms')
        .where((s) => s['profileId'] == p.id && s['deleted'] != true)
        .toList();
  }

  void _syncDateTimeCtrls() {
    _dateCtrl.text = fmtDateMm(_date);
    _timeCtrl.text = fmtTimeMm(_time);
  }

  Future<void> _addSymptom() async {
    final p = activeProfile;
    if (p == null) return;
    final name = (_nameCtrl?.text ?? '').trim();
    if (name.isEmpty) {
      showToast(context, 'လက္ခဏာ ထည့်ပေးပါ');
      return;
    }
    await local.upsert('symptoms', {
      'id': newId(),
      'profileId': p.id,
      'date': _date.isEmpty ? todayStr() : _date,
      'time': _time.isEmpty ? nowHm() : _time,
      'name': name,
      'severity': _severity,
      'note': _noteCtrl.text.trim(),
      'deleted': false,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    setState(() {
      _date = todayStr();
      _time = nowHm();
      _severity = 2;
      _nameCtrl?.clear();
      _noteCtrl.clear();
      _syncDateTimeCtrls();
    });
    if (mounted) showToast(context, 'မှတ်တမ်းတင်ပြီးပါပြီ ✅');
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final p = activeProfile;
    if (p == null) {
      return const Center(child: Text('Profile မရှိသေးပါ'));
    }
    _syncDateTimeCtrls();

    final all = _symptoms;
    final list = List<Map<String, dynamic>>.from(all)
      ..sort((a, b) =>
          ((a['date'] as String) + (a['time'] as String))
                  .compareTo((b['date'] as String) + (b['time'] as String)) *
              -1);
    final latest = list.take(30).toList();

    // Weekly counts (last 7 days).
    final weekAgo = addDaysStr(todayStr(), -7);
    final counts = <String, int>{};
    for (final s in all) {
      if ((s['date'] as String).compareTo(weekAgo) >= 0) {
        final n = (s['name'] as String?) ?? '';
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final repeaters = counts.keys.where((k) => counts[k]! >= 3).toList();
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Repeaters alert.
        if (repeaters.isNotEmpty)
          Card(
            color: AppTheme.dangerBg,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '⚠️ သတိပြုရန်: ပြီးခဲ့တဲ့ ၇ ရက်အတွင်း '
                '${repeaters.map((k) => '“$k” (${counts[k]} ကြိမ်)').join(', ')}'
                ' ဖြစ်ပွားခဲ့ပါတယ်။ ဆရာဝန်နဲ့ ပြသဖို့ စဉ်းစားပါ။',
              ),
            ),
          ),
        // Add form.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📝 လက္ခဏာ မှတ်တမ်းတင်ရန်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dateCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(labelText: 'နေ့'),
                        onTap: () async {
                          final d = await pickDateStr(context, _date);
                          if (d != null) {
                            setState(() {
                              _date = d;
                              _syncDateTimeCtrls();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _timeCtrl,
                        readOnly: true,
                        decoration:
                            const InputDecoration(labelText: 'အချိန်'),
                        onTap: () async {
                          final t = await pickTimeStr(context, _time);
                          if (t != null) {
                            setState(() {
                              _time = t;
                              _syncDateTimeCtrls();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  optionsBuilder: (value) {
                    if (value.text.isEmpty) return commonSymptoms;
                    return commonSymptoms
                        .where((s) => s.contains(value.text));
                  },
                  fieldViewBuilder:
                      (ctx, ctrl, focusNode, onFieldSubmitted) {
                    _nameCtrl = ctrl;
                    return TextField(
                      controller: ctrl,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'လက္ခဏာ *',
                        hintText: 'ဥပမာ ခေါင်းကိုက်',
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey(_severity),
                  initialValue: _severity,
                  decoration:
                      const InputDecoration(labelText: 'ပြင်းထန်မှု (1–5)'),
                  items: [1, 2, 3, 4, 5]
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text('$n'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _severity = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'မှတ်ချက်',
                    hintText: 'ဥပမာ ညနေ ၃ နာရီကတည်းက',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _addSymptom,
                  child: const Text('မှတ်တမ်းတင်မယ်'),
                ),
              ],
            ),
          ),
        ),
        // 7-day counts.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📊 ၇ ရက်အတွင်း အကြိမ်ရေ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (keys.isEmpty)
                  const Text(
                    'မရှိပါ',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1),
                    },
                    children: [
                      const TableRow(
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'လက္ခဏာ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'အကြိမ်ရေ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      for (final k in keys)
                        TableRow(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Text(k),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '${counts[k]}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        // Latest records.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🕘 နောက်ဆုံး မှတ်တမ်းများ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (latest.isEmpty)
                  const Text(
                    'မရှိသေးပါ',
                    style: TextStyle(color: Colors.grey),
                  ),
                for (final s in latest)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                children: [
                                  Text(
                                    (s['name'] as String?) ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.soft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'အဆင့် ${s['severity']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${fmtDateMm((s['date'] as String?) ?? '')} ${fmtTimeMm((s['time'] as String?) ?? '')}${(s['note'] as String?)?.isNotEmpty == true ? ' · ${s['note']}' : ''}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                          ),
                          onPressed: () async {
                            await local.softDelete(
                              'symptoms',
                              s['id'] as String,
                            );
                            refresh();
                          },
                          child: const Text('ဖျက်မယ်'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
