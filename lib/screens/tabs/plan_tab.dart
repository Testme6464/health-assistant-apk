// 🗓️ အစီအစဉ် (Monthly Plan) — the user's dictated format (2026-11-05).
// Flow: tap generate → BMI assessment line → pick 1 of 3 goals
// (💪 ဝိတ်တိုးရန်, ⚖️ ထိန်းသိမ်းရန်, 🏃 ဝိတ်ချရန်, current marked) → plan.
// Per-goal calories at top, meals with times + food groups + a reason each,
// 7-day exercise split into 4 weeks (minutes x1/x1.15/x1.3/x1.3), day-by-day
// guide for the current date at the bottom. Meal items in food-box boxes
// with "N မျိုးစားရန်" counts. Elderly exercise alternatives show ONLY when
// the profile age is >= 40. Old-format plans (no `goal`) count as not
// generated. AI path demands exactly the 4 headers (ကယ်လိုရီ / စားသောက်ချိန် /
// လေ့ကျင့်ခန်း / လမ်းညွှန်) — validated with planOutputOk + one strict retry.
import 'package:flutter/material.dart';

import '../../data/plan_data.dart';
import '../../models/health_data.dart';
import '../../services/gemini_service.dart';
import '../../services/key_store.dart';
import 'tab_common.dart';

class PlanTab extends StatefulWidget {
  const PlanTab({super.key});

  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> with TabLoader<PlanTab> {
  String? _chooseMode; // null | 'offline' | 'ai'
  bool _aiBusy = false;
  String _aiStatus = '';

  String get _monthKey => currentMonthKey();

  Map<String, dynamic>? get _plan {
    final p = activeProfile;
    if (p == null) return null;
    return validPlan(local, p.id, _monthKey);
  }

  Future<void> _pickGoal(String goal) async {
    final p = activeProfile;
    if (p == null) return;
    final mode = _chooseMode;
    setState(() => _chooseMode = null);
    if (mode == 'ai') {
      await _generateAiPlan(p, goal);
    } else {
      final bedtime =
          (local.map('reminders')['bedtime'] as String?) ?? '22:30';
      final plan = generateGoalPlan(p, goal, bedtime);
      await savePlan(local, p.id, plan);
      refresh();
      if (mounted) showToast(context, 'အစီအစဉ် ထုတ်ပြီးပါပြီ ✅');
    }
  }

  Future<void> _generateAiPlan(HealthProfile p, String goal) async {
    setState(() {
      _aiBusy = true;
      _aiStatus = '✨ AI အစီအစဉ် ထုတ်လုပ်နေသည်…';
    });
    try {
      final settings = local.map('settings');
      final modelRaw = strVal(settings['geminiModel']);
      final model =
          modelRaw.isEmpty ? GeminiService.defaultModel : modelRaw;
      final gemini = GeminiService(KeyStore(), model: model);
      final bmi = p.bmi;
      final meds = local
          .list('meds')
          .where((m) => m['profileId'] == p.id)
          .toList();
      final userPrompt = 'Name: ${p.name}\n'
          'Age: ${p.age ?? '?'}, Gender: ${p.gender.isEmpty ? '?' : p.gender}\n'
          'Height: ${p.heightCm ?? '?'} cm, Weight: ${p.weightKg ?? '?'} kg, BMI: '
          '${bmi != null ? '${bmi.toStringAsFixed(1)} (${bmiLabel(bmi)})' : '?'}\n'
          'Health goal (chosen by the user): ${goalLabels[goal] ?? goalLabels[p.goal] ?? ''}\n'
          'Existing health conditions (MUST tailor the plan to these): ${p.conditions.join(', ').isEmpty ? 'none' : p.conditions.join(', ')}\n'
          'Allergies: ${p.allergies.join(', ').isEmpty ? 'none' : p.allergies.join(', ')}\n'
          'Current medications: ${meds.isEmpty ? 'none' : meds.map((m) => '${m['name']}${(m['dosage'] as String?)?.isNotEmpty == true ? ' ${m['dosage']}' : ''}${(m['reason'] as String?)?.isNotEmpty == true ? ' (${m['reason']})' : ''}').join('; ')}\n'
          'Daily calorie target: ${calorieTargetFor(weightKg: p.weightKg ?? 60, heightCm: p.heightCm ?? 160, age: p.age ?? 30, female: p.gender == 'female', goal: goal)} kcal\n'
          'Today: ${todayStr()} (${['တနင်္ဂနွေ', 'တနင်္လာ', 'အင်္ဂါ', 'ဗုဒ္ဓဟူး', 'ကြာသပတေး', 'သောကြာ', 'စနေ'][DateTime.now().weekday % 7]}) — the day-by-day guide must start from today\n'
          'Usual bedtime: ${(local.map('reminders')['bedtime'] as String?) ?? '?'}';
      final isQwen = RegExp(r'qwen', caseSensitive: false).hasMatch(model);
      final showAlt = showAltFor(p);
      var prompt = planPrompt +
          (isQwen
              ? ' Keep the entire plan concise: under ~450 words total.'
              : '') +
          (showAlt
              ? ' For strenuous exercises (squat, push-up, running), also suggest a gentler alternative for older people.'
              : '');
      // GeminiService has no separate system-instruction slot: the system
      // prompt goes first, then the user profile (same content as the web).
      var ans = await gemini.generate('$prompt\n\n$userPrompt');
      if (!planOutputOk(ans)) {
        final retry = await gemini.generate(
          '$prompt\nSTRICT: all words Burmese except units kcal/kg/cm/min; use the 4 headers exactly; no questions.\n\n$userPrompt',
        );
        if (planOutputOk(retry)) {
          ans = retry;
        } else if (planHeaderHits(retry) > planHeaderHits(ans)) {
          ans = retry;
        }
      }
      if (ans.length < 150) throw Exception('AI အဖြေ ပုံစံမမှန်ပါ');
      final snap = 'အသက် ${p.age ?? '?'} · BMI ${bmi != null ? '${bmi.toStringAsFixed(1)} (${bmiLabel(bmi)})' : '?'}'
          ' · ရည်မှန်းချက်: ${goalLabels[goal] ?? goalLabels[p.goal] ?? ''}'
          ' · အခံရောဂါ: ${p.conditions.join(', ').isEmpty ? 'မရှိ' : p.conditions.join(', ')}'
          ' · သောက်နေသောဆေး: ${meds.isEmpty ? 'မရှိ' : meds.map((m) => '${m['name']}').join(', ')}';
      final plan = {
        'month': _monthKey,
        'createdAt': DateTime.now().toIso8601String(),
        'ai': true,
        'goal': goal,
        'rawAi': ans,
        'snap': snap,
      };
      await savePlan(local, p.id, plan);
      refresh();
      if (mounted) showToast(context, 'AI အစီအစဉ် ရပြီးပါပြီ ✅');
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          'AI ခေါ်ဆို၍မရပါ: $e — offline နဲ့ ထုတ်ကြည့်ပါ',
        );
      }
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
    final plan = _plan;
    final hasKeys = KeyStore().hasKeys;
    final monthLabel =
        '${mmMonths[DateTime.now().month - 1]} ${DateTime.now().year}';

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
                  '🗓️ တစ်လစာ ကျန်းမာရေး အစီအစဉ်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.name} · $monthLabel',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (plan == null) ..._buildNoPlan(p, hasKeys),
                if (plan != null) ..._buildPlan(p, plan),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildNoPlan(HealthProfile p, bool hasKeys) {
    if (_aiBusy) {
      return [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_aiStatus)),
              ],
            ),
          ),
        ),
      ];
    }
    if (_chooseMode == null) {
      return [
        const Text('ဒီလအတွက် အစီအစဉ် မထုတ်ရသေးပါ'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => setState(() => _chooseMode = 'offline'),
                child: const Text('📋 အစီအစဉ် ထုတ်မယ် (offline)'),
              ),
            ),
            if (hasKeys) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _chooseMode = 'ai'),
                  child: const Text('✨ AI နဲ့ ထုတ်မယ်'),
                ),
              ),
            ],
          ],
        ),
        if (!hasKeys)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Settings မှာ API key ထည့်ထားရင် AI နဲ့ ပိုကိုယ်ပိုင် အစီအစဉ် ထုတ်နိုင်ပါတယ်',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ];
    }
    // STEP 1: BMI assessment line, STEP 2: pick one of the three goals.
    final bmi = p.bmi;
    return [
      Card(
        color: Colors.blue.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '📊 BMI: ${bmi != null ? bmi.toStringAsFixed(1) : '?'} — ${bmiLabel(bmi)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'ရည်မှန်းချက် ရွေးပါ',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in ['gain', 'maintain', 'lose'])
            ElevatedButton(
              onPressed: () => _pickGoal(g),
              child: Text(
                '${goalBtn[g] ?? g}${p.goal == g ? ' (လက်ရှိ)' : ''}',
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => setState(() => _chooseMode = null),
        child: const Text('← ပြန်သွားမယ်'),
      ),
    ];
  }

  List<Widget> _buildPlan(HealthProfile p, Map<String, dynamic> plan) {
    final isAi = plan['ai'] == true;
    final goal = (plan['goal'] as String?) ?? p.goal;
    final showAlt = showAltFor(p);
    return [
      Card(
        color: Colors.blue.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '✅ ${isAi ? 'AI နဲ့' : 'offline စည်းမျဉ်းနဲ့'} ထုတ်ထားသော အစီအစဉ် · ရည်မှန်းချက်: ${goalLabels[goal] ?? ''}',
          ),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          await deletePlan(local, p.id);
          refresh();
        },
        icon: const Icon(Icons.refresh),
        label: const Text('🔄 ပြန်ထုတ်မယ်'),
      ),
      const SizedBox(height: 12),
      if (isAi && plan['rawAi'] != null)
        ..._buildAiPlan(plan)
      else
        ..._buildOfflinePlan(plan, showAlt),
    ];
  }

  /// AI plan: the "## Header" lines become real section headers.
  List<Widget> _buildAiPlan(Map<String, dynamic> plan) {
    final raw = (plan['rawAi'] as String?) ?? '';
    final widgets = <Widget>[];
    if (plan['snap'] != null) {
      widgets.add(
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '🔍 AI က ဒီအချက်တွေကို အခြေခံပြီး ဆွဲထားတာပါ:\n${plan['snap']}',
            ),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 8));
    }
    final parts = raw.split(RegExp(r'^## ', multiLine: true));
    if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
      widgets.add(Text(parts[0].trim()));
    }
    for (var i = 1; i < parts.length; i++) {
      final nl = parts[i].indexOf('\n');
      final head = nl >= 0 ? parts[i].substring(0, nl) : parts[i];
      final body = nl >= 0 ? parts[i].substring(nl + 1) : '';
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        Text(
          head.trim(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(const SizedBox(height: 4));
      widgets.add(Text(body.trim()));
    }
    return widgets;
  }

  /// Offline plan in the user's dictated format.
  List<Widget> _buildOfflinePlan(
    Map<String, dynamic> plan,
    bool showAlt,
  ) {
    final widgets = <Widget>[];
    final goal = (plan['goal'] as String?) ?? 'maintain';
    // Calories at the very top.
    widgets.add(
      Card(
        color: Colors.blue.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '🎯 ရည်မှန်းချက်: ${goalLabels[goal] ?? ''}\nစားသင့်သော ကယ်လိုရီ: ${plan['calorieTarget']} kcal/နေ့',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
    // Meals.
    widgets.add(const SizedBox(height: 12));
    widgets.add(
      const Text(
        '🍽️ စားသောက်ချိန် အချိန်ဇယား',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
    final meals =
        (plan['meals'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final m in meals) {
      final items = (m['items'] as List?)?.map((e) => '$e').toList() ?? [];
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtTimeMm((m['time'] as String?) ?? '')} — ${m['name']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${items.length} မျိုးစားရန်',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                for (final it in items) _FoodBox(item: it),
                if ((m['why'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '💡 ${m['why']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    // Sleep.
    final sleep = (plan['sleep'] as Map?)?.cast<String, dynamic>();
    if (sleep != null) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        const Text(
          '😴 အိပ်စက်ချိန်',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'အိပ်ရာဝင်ချိန်: ${fmtTimeMm((sleep['bed'] as String?) ?? '')} · နိုးထချိန်: ${fmtTimeMm((sleep['wake'] as String?) ?? '')} (၇.၅ နာရီ)',
            ),
          ),
        ),
      );
    }
    // 4-week workout.
    widgets.add(const SizedBox(height: 12));
    widgets.add(
      const Text(
        '🏃 ၄ ပတ် လေ့ကျင့်ခန်း အစီအစဉ် (၇ ရက်စာ)',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
    final workout =
        (plan['workout'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final w in workout) {
      final days = (w['days'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${w['week']}${w['title'] != null ? ' — ${w['title']}' : ''}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${d['day']}: ${d['text']}"),
                        if (showAlt && (d['alt'] as String?) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '👴 အသက်ကြီးသူများ အစားထိုး: ${d['alt']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    // Diet eat / avoid.
    final diet = (plan['diet'] as Map?)?.cast<String, dynamic>();
    if (diet != null) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        const Text(
          '🥗 စားသင့်သော အစားအစာများ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(const SizedBox(height: 6));
      widgets.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in (diet['eat'] as List? ?? []).map((e) => '$e'))
              Chip(
                label: Text('✅ $e', style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.blue.shade50,
              ),
          ],
        ),
      );
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        const Text(
          '🚫 ရှောင်ရန်များ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(const SizedBox(height: 6));
      widgets.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in (diet['avoid'] as List? ?? []).map((e) => '$e'))
              Chip(
                label: Text('❌ $e', style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.red.shade50,
              ),
          ],
        ),
      );
    }
    if ((plan['tip'] as String?)?.isNotEmpty == true) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('💡 ${plan['tip']}'),
          ),
        ),
      );
    }
    // Day-by-day guide for today.
    final guide = todayGuide(plan);
    if (guide != null) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        Text(
          '📅 ဒီနေ့ (${fmtDateMm(todayStr())}) လမ်းညွှန်',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(const SizedBox(height: 6));
      widgets.add(
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${guide.weekLabel}${guide.dayLabel != null ? ' · ${guide.dayLabel}' : ''}'),
                if (guide.dayText != null) ...[
                  const SizedBox(height: 6),
                  Text('🏃 လေ့ကျင့်ခန်း: ${guide.dayText}'),
                  if (showAlt && guide.dayAlt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '👴 အသက်ကြီးသူများ အစားထိုး: ${guide.dayAlt}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 6),
                Text('🎯 ကယ်လိုရီ: ${guide.calorieTarget} kcal'),
                const SizedBox(height: 6),
                const Text('🍽️ ဒီနေ့ စားရန်:'),
                for (final m in guide.meals) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${fmtTimeMm((m['time'] as String?) ?? '')} — ${m['name']} (${(m['items'] as List?)?.length ?? 0} မျိုး)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final it
                      in (m['items'] as List? ?? []).map((e) => '$e'))
                    _FoodBox(item: it),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

/// One food-group box (web: foodBoxHtml): "Label — options" splits into a
/// labeled box; a plain item becomes a box on its own.
class _FoodBox extends StatelessWidget {
  const _FoodBox({required this.item});
  final String item;

  @override
  Widget build(BuildContext context) {
    final parts = foodBoxParts(item);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: parts.label != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parts.label!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(parts.body),
              ],
            )
          : Text(parts.body),
    );
  }
}
