// 🏠 ပင်မ (Dashboard) — faithful port of renderHome in
// ~/workspace/health-app/app.js. Every Burmese string is copied from app.js.
// Liquid-fill kcal + water cards, meds, activity, weight mini chart (last 14),
// coach tip + optional AI tip (Gemini, keys only).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../services/gemini_service.dart';
import '../../services/key_store.dart';
import '../../theme.dart';
import 'activity_modal.dart';
import 'line_chart.dart';
import 'tab_common.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with TabLoader<HomeTab> {
  bool _aiBusy = false;
  String? _aiTip;
  bool _hasKeys = false;

  @override
  void initState() {
    super.initState();
    KeyStore().load().then((_) {
      if (mounted) setState(() => _hasKeys = KeyStore().hasKeys);
    });
  }

  int _kcalTarget(HealthProfile p) {
    final settings = local.map('settings');
    final manualMode = settings['calorieTargetMode'] == 'manual';
    final manualTarget = toInt(settings['calorieTarget']);
    return p.calorieTarget(
      manualTarget: manualTarget,
      manualMode: manualMode,
    );
  }

  Future<void> _addWater(int ml) async {
    await addWater(local, ml);
    refresh();
    if (mounted) showToast(context, '$ml ml ထည့်ပြီးပါပြီ 💧');
  }

  Future<void> _askAiTip(HealthProfile p, int kcalToday, int kcalTarget,
      int waterToday, int stepsToday) async {
    setState(() => _aiBusy = true);
    try {
      final settings = local.map('settings');
      final modelRaw = strVal(settings['geminiModel']);
      final model =
          modelRaw.isEmpty ? GeminiService.defaultModel : modelRaw;
      final gemini = GeminiService(KeyStore(), model: model);
      // Exact system + user prompt strings from renderHome in app.js.
      // GeminiService takes one prompt, so they are joined with a blank line.
      const systemPrompt =
          'You are a friendly Burmese health coach. Reply in Burmese (Myanmar script), 2-3 short sentences, practical and encouraging. No medical diagnosis.';
      final bmi = p.bmi;
      final userPrompt = 'Profile: age ${p.age ?? '?'}, gender '
          '${p.gender.isEmpty ? '?' : p.gender}, BMI '
          '${(bmi ?? 0).toStringAsFixed(1)}, goal '
          '${goalLabels[p.goal] ?? ''}, conditions: '
          '${p.conditions.join(', ').isEmpty ? 'none' : p.conditions.join(', ')}'
          '. Today: $kcalToday/$kcalTarget kcal, water ${waterToday}ml, steps $stepsToday'
          '. Current local time is ${nowHm()} (${timeOfDayMm(DateTime.now().hour)}). '
          'Give one personalized health tip that fits THIS time of day and the rest of today. '
          'Never suggest bedtime or night routines during daytime, and never suggest morning routines in the evening or at night.';
      final tip = await gemini.generate('$systemPrompt\n\n$userPrompt');
      if (mounted) setState(() => _aiTip = tip.trim());
    } on GeminiException catch (e) {
      if (mounted) showToast(context, 'AI ခေါ်ဆို၍မရပါ: ${e.message}');
    } catch (e) {
      if (mounted) showToast(context, 'AI ခေါ်ဆို၍မရပါ: $e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final p = activeProfile;
    if (p == null) {
      return const Center(child: Text('Profile မရှိသေးပါ'));
    }
    final t = todayStr();
    final kcalTarget = _kcalTarget(p);
    final kcalToday = local
        .list('foodLog')
        .where((f) => f['profileId'] == p.id && f['date'] == t)
        .fold<int>(0, (a, f) => a + (toInt(f['kcal']) ?? 0));
    final settings = local.map('settings');
    final waterTarget = toInt(settings['waterTargetMl']) ?? 2000;
    final waterToday = toInt(local.map('waterLog')[t]) ?? 0;
    final medsToday = todaysMedSchedule(local, p.id, t);
    final takenCount = medsToday.where((m) => m.status == 'taken').length;
    final missedCount = medsToday.where((m) => m.status == 'missed').length;
    final act = local
        .list('activityLog')
        .where((a) => a['profileId'] == p.id && a['date'] == t)
        .firstOrNull;
    final stepsToday = toInt(act?['steps']) ?? 0;
    final actKcal = act == null
        ? 0
        : activityKcal(
            steps: toInt(act['steps']) ?? 0,
            exerciseType: toInt(act['exerciseType']) ?? 1,
            minutes: toInt(act['minutes']) ?? 0,
            weightKg: p.weightKg ?? 60,
          ).total;
    final wl = local
        .list('weightLog')
        .where((w) => w['profileId'] == p.id)
        .toList()
      ..sort((a, b) =>
          strVal(a['date']).compareTo(strVal(b['date'])));
    final wl14 = wl.length > 14 ? wl.sublist(wl.length - 14) : wl;
    final kcalPct = math.min(100, (kcalToday / kcalTarget * 100).round());
    final waterPct = math.min(100, (waterToday / waterTarget * 100).round());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header: ဒီနေ့ အကျဉ်းချုပ်
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
                      'ဒီနေ့ အကျဉ်းချုပ်',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      fmtDateMm(t),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.name} · ရည်မှန်းချက်: ${goalLabels[p.goal] ?? goalLabels['maintain']!}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        // Calories + water — side by side, liquid fill cards.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FillCard(
                title: '🍚 ကယ်လိုရီ',
                pct: kcalPct,
                bigNumber: '$kcalToday',
                bigUnit: 'kcal',
                targetLabel: 'ရည်မှန်း $kcalTarget kcal',
                fillColor: const Color(0xFFFF6B35),
                fillColorEnd: const Color(0xFFFFA726),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FillCard(
                title: '💧 ရေ',
                pct: waterPct,
                bigNumber: '$waterToday',
                bigUnit: 'ml',
                targetLabel: 'ရည်မှန်း $waterTarget ml',
                fillColor: AppTheme.primary,
                fillColorEnd: const Color(0xFF64B5F6),
                buttons: [
                  _WaterButton(
                    label: '+ 250 ml',
                    onPressed: () => _addWater(250),
                  ),
                  _WaterButton(
                    label: '+ 500 ml',
                    onPressed: () => _addWater(500),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Meds
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💊 ဒီနေ့ ဆေး',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (medsToday.isEmpty)
                  const Text(
                    'ဆေးမှတ်တမ်း မရှိသေးပါ — ဆေးဝါးများ tab မှာ ထည့်ပါ',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  Text(
                    'သောက်ပြီး $takenCount / လွတ်သွား $missedCount / စုစုပေါင်း ${medsToday.length}',
                  ),
              ],
            ),
          ),
        ),
        // Activity
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🚶 လှုပ်ရှားမှု',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                          children: [
                            const TextSpan(text: 'ဒီနေ့ ခြေလှမ်း: '),
                            TextSpan(
                              text: '$stepsToday',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            const TextSpan(text: ' · လောင်ကျွမ်း: '),
                            TextSpan(
                              text: '~$actKcal kcal',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
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
                      child: const Text('ခြေလှမ်းထည့်ရန်'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Weight mini chart (last 14)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚖️ ကိုယ်အလေးချိန် (နောက်ဆုံး ၁၄ မှတ်)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SimpleLineChart(
                  series: [
                    ChartSeries(
                      label: 'kg',
                      color: const Color(0xFF1F6FB2),
                      points: wl14
                          .map((w) {
                            final d = strVal(w['date']);
                            return ChartPoint(
                              d.length >= 5 ? d.substring(5) : d,
                              toDouble(w['weight']),
                            );
                          })
                          .toList(),
                    ),
                  ],
                  unit: 'kg',
                ),
              ],
            ),
          ),
        ),
        // Coach tip
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🤖 ဒီနေ့ အကြံပြုချက်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.soft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_aiTip ?? tipOfDay()),
                ),
                const SizedBox(height: 12),
                if (_hasKeys)
                  OutlinedButton(
                    onPressed: _aiBusy
                        ? null
                        : () => _askAiTip(
                            p, kcalToday, kcalTarget, waterToday, stepsToday),
                    child: Text(
                      _aiBusy
                          ? 'စဉ်းစားနေသည်…'
                          : '✨ AI အကြံပြုချက် တောင်းမယ်',
                    ),
                  )
                else
                  const Text(
                    'Settings မှာ API key ထည့်ထားရင် AI အကြံပြုချက် ရနိုင်ပါတယ်',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Liquid-fill card: bottom fill height = pct% of the card; content on top.
class _FillCard extends StatelessWidget {
  const _FillCard({
    required this.title,
    required this.pct,
    required this.bigNumber,
    required this.bigUnit,
    required this.targetLabel,
    required this.fillColor,
    required this.fillColorEnd,
    this.buttons,
  });

  final String title;
  final int pct;
  final String bigNumber;
  final String bigUnit;
  final String targetLabel;
  final Color fillColor;
  final Color fillColorEnd;
  final List<Widget>? buttons;

  static const double _cardHeight = 176;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _cardHeight,
        child: Stack(
          children: [
            // Liquid fill (web: .fill, height = pct%).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _cardHeight * pct / 100,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      fillColor.withValues(alpha: 0.35),
                      fillColorEnd.withValues(alpha: 0.18),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$pct%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      children: [
                        TextSpan(text: bigNumber),
                        TextSpan(
                          text: ' $bigUnit',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    targetLabel,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  if (buttons != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      children: buttons!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaterButton extends StatelessWidget {
  const _WaterButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
