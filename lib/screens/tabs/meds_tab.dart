// 💊 ဆေးများ (Meds) — faithful port of renderMeds / openMedModal /
// medSupplyLeft / checkLocalInteractions / renderLocalInteractions /
// renderAiInteractions in ~/workspace/health-app/app.js.
// Every Burmese string is copied from app.js, never typed from memory.
// Blue theme only.
import 'package:flutter/material.dart';

import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../services/gemini_service.dart';
import '../../services/key_store.dart';
import '../../theme.dart';
import 'tab_common.dart';

class MedsTab extends StatefulWidget {
  const MedsTab({super.key});

  @override
  State<MedsTab> createState() => _MedsTabState();
}

class _MedsTabState extends State<MedsTab> with TabLoader<MedsTab> {
  // Interaction-check result state. Null mode = default muted text.
  // 'warn' | 'localOk' | 'localFound' | 'aiBusy' | 'aiResult' | 'aiError'
  String? _interactMode;
  List<({DrugInteraction entry, List<String> meds})> _localFound = [];
  String _aiResult = '';
  String _aiError = '';
  bool _hasKeys = false;

  @override
  void initState() {
    super.initState();
    KeyStore().load().then((_) {
      if (mounted) setState(() => _hasKeys = KeyStore().hasKeys);
    });
  }

  List<Map<String, dynamic>> get _meds {
    final p = activeProfile;
    if (p == null) return [];
    return local
        .list('meds')
        .where((m) => m['profileId'] == p.id && m['deleted'] != true)
        .toList();
  }

  void _clearInteract() {
    _interactMode = null;
    _localFound = [];
    _aiResult = '';
    _aiError = '';
  }

  Future<void> _toggleDose(String key, String status) async {
    await toggleMedStatus(local, todayStr(), key, status);
    _clearInteract();
    refresh();
  }

  Future<void> _deleteMed(Map<String, dynamic> m) async {
    final ok = await confirmDialog(
      context,
      'ဒီဆေးကို ဖျက်မှာလား?',
      (m['name'] as String?) ?? '',
    );
    if (!ok) return;
    await local.softDelete('meds', m['id'] as String);
    _clearInteract();
    refresh();
  }

  Future<void> _openMedDialog([Map<String, dynamic>? med]) async {
    final p = activeProfile;
    if (p == null) return;
    final isEdit = med != null;
    final nameCtrl =
        TextEditingController(text: (med?['name'] as String?) ?? '');
    final dosageCtrl =
        TextEditingController(text: (med?['dosage'] as String?) ?? '');
    final timesCtrl = TextEditingController(
      text: med != null
          ? ((med['times'] as List?)?.map((e) => '$e').join(', ') ?? '')
          : '08:00, 20:00',
    );
    final reasonCtrl =
        TextEditingController(text: (med?['reason'] as String?) ?? '');
    final supplyCtrl = TextEditingController(
      text: med?['supplyDays'] == null ? '' : '${med?['supplyDays']}',
    );
    final supplyStartCtrl = TextEditingController(
      text: (med?['supplyStartDate'] as String?)?.isNotEmpty == true
          ? (med!['supplyStartDate'] as String)
          : todayStr(),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? '💊 ဆေးပြင်ရန်' : '💊 ဆေးအသစ်ထည့်ရန်'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'ဆေးအမည် *',
                  hintText: 'ဥပမာ Amlodipine',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dosageCtrl,
                decoration: const InputDecoration(
                  labelText: 'ပမာဏ (Dosage)',
                  hintText: 'ဥပမာ 5mg, ၁ လုံး',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: timesCtrl,
                decoration: const InputDecoration(
                  labelText: 'သောက်ရမည့်အချိန်များ (ကော်မာခြား, 24h)',
                  hintText: '08:00, 13:00, 20:00',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'သောက်ရသည့် အကြောင်းအရင်း',
                  hintText: 'ဥပမာ သွေးတိုးအတွက်',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: supplyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'လက်ကျန်ရက် (ရက်)',
                        hintText: 'ဥပမာ 30',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: supplyStartCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'စသောက်သည့်နေ့',
                      ),
                      onTap: () async {
                        final d = await pickDateStr(
                          ctx,
                          supplyStartCtrl.text.isEmpty
                              ? todayStr()
                              : supplyStartCtrl.text,
                        );
                        if (d != null) supplyStartCtrl.text = d;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    );
    if (saved != true) {
      nameCtrl.dispose();
      dosageCtrl.dispose();
      timesCtrl.dispose();
      reasonCtrl.dispose();
      supplyCtrl.dispose();
      supplyStartCtrl.dispose();
      return;
    }
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) showToast(context, 'ဆေးအမည် ထည့်ပေးပါ');
      nameCtrl.dispose();
      dosageCtrl.dispose();
      timesCtrl.dispose();
      reasonCtrl.dispose();
      supplyCtrl.dispose();
      supplyStartCtrl.dispose();
      return;
    }
    final tms = timesCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s))
        .toList();
    if (tms.isEmpty) {
      if (mounted) {
        showToast(context, 'အချိန် အနည်းဆုံး ၁ ခု မှန်အောင်ထည့်ပါ (ဥပမာ 08:00)');
      }
      nameCtrl.dispose();
      dosageCtrl.dispose();
      timesCtrl.dispose();
      reasonCtrl.dispose();
      supplyCtrl.dispose();
      supplyStartCtrl.dispose();
      return;
    }
    final supplyDays = int.tryParse(supplyCtrl.text.trim());
    final data = <String, dynamic>{
      'id': med?['id'] as String? ?? newId(),
      'profileId': p.id,
      'name': name,
      'dosage': dosageCtrl.text.trim(),
      'times': tms,
      'reason': reasonCtrl.text.trim(),
      'supplyDays': supplyDays,
      'supplyStartDate': supplyStartCtrl.text.trim(),
      'deleted': false,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    nameCtrl.dispose();
    dosageCtrl.dispose();
    timesCtrl.dispose();
    reasonCtrl.dispose();
    supplyCtrl.dispose();
    supplyStartCtrl.dispose();
    await local.upsert('meds', data);
    _clearInteract();
    refresh();
    if (mounted) showToast(context, 'ဆေး သိမ်းပြီးပါပြီ ✅');
  }

  void _checkLocal() {
    final names = _meds.map((m) => (m['name'] as String?) ?? '').toList();
    if (names.length < 2) {
      setState(() => _interactMode = 'warn');
      return;
    }
    final found = checkLocalInteractions(names);
    setState(() {
      _localFound = found;
      _interactMode = found.isEmpty ? 'localOk' : 'localFound';
    });
  }

  Future<void> _checkAi() async {
    final p = activeProfile;
    if (p == null) return;
    final meds = _meds;
    if (meds.length < 2) {
      setState(() => _interactMode = 'warn');
      return;
    }
    setState(() {
      _interactMode = 'aiBusy';
      _aiResult = '';
      _aiError = '';
    });
    try {
      final list = meds
          .map((m) =>
              '${m['name']}${(m['dosage'] as String?)?.isNotEmpty == true ? ' (${m['dosage']})' : ''}')
          .join(', ');
      final settings = local.map('settings');
      final model =
          (settings['geminiModel'] as String?) ?? GeminiService.defaultModel;
      final gemini = GeminiService(KeyStore(), model: model);
      final ans = await gemini.generate(
        'You are a pharmacy assistant. Reply in Burmese (Myanmar script). List potential drug-drug interactions, each with severity (ပြင်းထန်/အလယ်အလတ်/နည်း) and a one-line explanation. End with: ဆေးမပြောင်းမီ ဆရာဝန်နဲ့ တိုင်ပင်ပါ။ This is informational only, not medical advice.\n\n'
        'Check interactions between these medications: $list'
        '. Patient conditions: ${(p.conditions.join(', ').isEmpty ? 'none' : p.conditions.join(', '))}. Allergies: ${(p.allergies.join(', ').isEmpty ? 'none' : p.allergies.join(', '))}.',
      );
      if (!mounted) return;
      setState(() {
        _aiResult = ans;
        _interactMode = 'aiResult';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is GeminiException ? e.message : '$e';
      setState(() {
        _aiError = msg;
        _interactMode = 'aiError';
      });
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
    final meds = _meds;
    final sched = todaysMedSchedule(local, p.id, t)
        .where((d) => d.med['deleted'] != true)
        .toList();
    final lowMeds = meds
        .map((m) => (med: m, left: medSupplyLeft(m)))
        .where((x) => x.left != null && x.left! <= 7)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Today's schedule.
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
                      '💊 ဒီနေ့ သောက်ရမည့်ဆေးများ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      fmtDateMm(t),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (sched.isEmpty)
                  const Text(
                    'ဆေး မှတ်တမ်း မရှိသေးပါ — အောက်မှာ အရင်ထည့်ပါ',
                    style: TextStyle(color: Colors.grey),
                  ),
                for (final s in sched) _DoseRow(
                  dose: s,
                  onToggle: (status) => _toggleDose(s.key, status),
                ),
              ],
            ),
          ),
        ),
        // Refill alerts.
        if (lowMeds.isNotEmpty)
          Card(
            color: AppTheme.dangerBg,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠️ ဆေးကုန်ခါနီးနေပါပြီ:'),
                  const SizedBox(height: 4),
                  for (final x in lowMeds)
                    Text('• ${x.med['name']} — ${x.left} ရက် စာသာ ကျန်သည်'),
                ],
              ),
            ),
          ),
        // Med list.
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
                      '📋 ဆေးစာရင်း',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _openMedDialog(),
                      child: const Text('＋ ထည့်မယ်'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (meds.isEmpty)
                  const Text(
                    'ဆေး မထည့်ရသေးပါ',
                    style: TextStyle(color: Colors.grey),
                  ),
                for (final m in meds) _MedRow(
                  med: m,
                  onEdit: () => _openMedDialog(m),
                  onDelete: () => _deleteMed(m),
                ),
              ],
            ),
          ),
        ),
        // Interaction check.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔬 ဆေးအချင်းချင်း ဓာတ်ပြုမှု စစ်ဆေးရန်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildInteractResult(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _checkLocal,
                      child: const Text('📋 စာရင်းနဲ့ စစ်မယ် (offline)'),
                    ),
                    if (_hasKeys)
                      ElevatedButton(
                        onPressed: _interactMode == 'aiBusy' ? null : _checkAi,
                        child: const Text('✨ AI နဲ့ စစ်မယ်'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '⚠️ ဒါက ကနဦး လမ်းညွှန်ချက်သာ — ဆေးမပြောင်းမီ ဆရာဝန်/ဆေးဝါးပညာရှင်နဲ့ တိုင်ပင်ပါ။',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInteractResult() {
    switch (_interactMode) {
      case 'warn':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.amberBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('ဆေး ၂ မျိုးအထက် ထည့်ပြီးမှ စစ်လို့ရပါမယ်'),
        );
      case 'localOk':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.soft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '✅ ထည့်ထားတဲ့ စာရင်း (${drugInteractions.length} ချက်) နဲ့ စစ်ကြည့်တာ သိသာတဲ့ ဓာတ်ပြုမှု မတွေ့ပါ။\nမှတ်ချက် — စာရင်းက အဖြစ်များတာတွေသာ ပါတာမို့ ဆေးအသစ်မစမီ ဆရာဝန်နဲ့ တိုင်ပင်ပါ။',
          ),
        );
      case 'localFound':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.dangerBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⚠️ ဓာတ်ပြုနိုင်ချေ ${_localFound.length} ခု တွေ့ပါတယ်:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            for (final f in _localFound)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.amberBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${f.meds.join(' + ')} — ${interactionLevelMm(f.entry.level)}\n${f.entry.noteMm}',
                ),
              ),
            const Text(
              'ဆရာဝန်/ဆေးဝါးပညာရှင်နဲ့ အမြန်တိုင်ပင်ပါ။',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        );
      case 'aiBusy':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.soft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('AI စစ်ဆေးနေသည်…'),
            ],
          ),
        );
      case 'aiResult':
        return Card(
          color: AppTheme.soft,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✨ AI စစ်ဆေးချက်',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(_aiResult),
              ],
            ),
          ),
        );
      case 'aiError':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.dangerBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('AI ခေါ်ဆို၍မရပါ: $_aiError'),
        );
      default:
        return const Text(
          'ဆေး ၂ မျိုးနှင့်အထက် ထည့်ထားရင် စစ်လို့ရပါမယ်',
          style: TextStyle(color: Colors.grey),
        );
    }
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose, required this.onToggle});
  final MedDose dose;
  final void Function(String status) onToggle;

  @override
  Widget build(BuildContext context) {
    final taken = dose.status == 'taken';
    final missed = dose.status == 'missed';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: taken
            ? AppTheme.soft
            : (missed ? AppTheme.dangerBg : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text(
            fmtTimeMm(dose.time),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (dose.med['name'] as String?) ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if ((dose.med['dosage'] as String?)?.isNotEmpty == true)
                  Text(
                    dose.med['dosage'] as String,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          taken
              ? ElevatedButton(
                  onPressed: () => onToggle('taken'),
                  child: const Text('✅ သောက်ပြီး'),
                )
              : OutlinedButton(
                  onPressed: () => onToggle('taken'),
                  child: const Text('✅ သောက်ပြီး'),
                ),
          const SizedBox(width: 6),
          missed
              ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                  ),
                  onPressed: () => onToggle('missed'),
                  child: const Text('⏭️ လွတ်'),
                )
              : OutlinedButton(
                  onPressed: () => onToggle('missed'),
                  child: const Text('⏭️ လွတ်'),
                ),
        ],
      ),
    );
  }
}

class _MedRow extends StatelessWidget {
  const _MedRow({
    required this.med,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> med;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if ((med['dosage'] as String?)?.isNotEmpty == true) {
      parts.add(med['dosage'] as String);
    }
    final times = (med['times'] as List?)?.map((e) => fmtTimeMm('$e')).toList() ?? [];
    if (times.isNotEmpty) parts.add(times.join(', '));
    if ((med['reason'] as String?)?.isNotEmpty == true) {
      parts.add(med['reason'] as String);
    }
    final left = medSupplyLeft(med);
    if (left != null) parts.add('ကျန် $left ရက်');
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
                  (med['name'] as String?) ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join(' · '),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onEdit,
            child: const Text('ပြင်မယ်'),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: onDelete,
            child: const Text('ဖျက်မယ်'),
          ),
        ],
      ),
    );
  }
}
