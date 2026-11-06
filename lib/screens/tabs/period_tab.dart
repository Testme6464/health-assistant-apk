// 🩸 ရာသီစက်ဝန်း မှတ်တမ်း (Period Tracker) — faithful port of
// renderPeriod + calcPeriodSummary in ~/workspace/health-app/app.js.
//
// NOTE on encoding: app.js carries a literal U+FFFD replacement character
// after "ရာသီစက်ဝန်း" in the period strings (a corruption artifact — it
// would render as a replacement glyph). It is dropped here; the Burmese
// text is otherwise copied from app.js verbatim.
// One deliberate deviation from the web: the web lists logs.slice(0, 12)
// on the oldest-first list (oldest 12); this tab shows the latest 12,
// newest first, per the port spec.
import 'package:flutter/material.dart';

import '../../models/health_data.dart';
import '../../theme.dart';
import 'tab_common.dart';

class PeriodTab extends StatefulWidget {
  const PeriodTab({super.key});

  @override
  State<PeriodTab> createState() => _PeriodTabState();
}

class _PeriodTabState extends State<PeriodTab> with TabLoader<PeriodTab> {
  Future<void> _enablePeriod(HealthProfile p) async {
    p.periodEnabled = true;
    p.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await local.upsert('profiles', p.toJson());
    refresh();
    if (mounted) showToast(context, 'ဖွင့်ပြီးပါပြီ ✅');
  }

  Future<void> _addPeriod(HealthProfile p) async {
    var date = todayStr();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('🩸 ရာသီစက်ဝန်း မှတ်တမ်း'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('စတင်သည့်နေ့'),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await pickDateStr(ctx, date);
                  if (picked != null) setDialog(() => date = picked);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(fmtDateMm(date)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('မလုပ်ဘူး'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('သိမ်းမယ်'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await local.upsert('periodLog', {
      'id': newId(),
      'profileId': p.id,
      'start': date,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    refresh();
    if (mounted) showToast(context, 'မှတ်တမ်းတင်ပြီးပါပြီ ✅');
  }

  Future<void> _deletePeriod(String id) async {
    await local.softDelete('periodLog', id);
    refresh();
  }

  Widget _infoBox(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.soft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = activeProfile;
    if (p == null) {
      return const Center(child: Text('—'));
    }
    if (!p.periodEnabled) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🩸 ရာသီစက်ဝန်း မှတ်တမ်း',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _infoBox(
                    const Text(
                      'ဒီ module ကို သုံးဖို့ ကျန်းမာရေးဖိုင် tab မှာ “ရာသီစက်ဝန်း မှတ်တမ်း သုံးမယ်” ကို အမှန်ခြစ်ပေးပါ။',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _enablePeriod(p),
                    child: const Text('ဖွင့်မယ်'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final sum = calcPeriodSummary(local, p.id);
    // Latest 12, newest first.
    final logs = sum.logs.reversed.take(12).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        '🩸 ရာသီစက်ဝန်း မှတ်တမ်း',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _addPeriod(p),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('＋ ထည့်မယ်'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (sum.count >= 2)
                  _infoBox(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            children: [
                              const TextSpan(text: '📅 ပျမ်းမျှ စက်ဝန်း: '),
                              TextSpan(
                                text: '${sum.avg} ရက်',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            children: [
                              const TextSpan(text: 'နောက်တစ်ကြိမ် ခန့်မှန်း: '),
                              TextSpan(
                                text: fmtDateMm(sum.next ?? ''),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: (sum.daysLeft ?? 0) >= 0
                                    ? ' (${sum.daysLeft} ရက် အလို)'
                                    : ' (${-(sum.daysLeft ?? 0)} ရက် ကျော်လွန်)',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Text(
                    'ခန့်မှန်းဖို့ မှတ်တမ်း အနည်းဆုံး ၂ ခု လိုပါတယ်',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                if (logs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'မရှိသေးပါ',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                for (final l in logs)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            fmtDateMm(l['start'] as String? ?? ''),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _deletePeriod(l['id'] as String),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                          ),
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
