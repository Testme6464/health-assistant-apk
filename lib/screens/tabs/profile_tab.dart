// 👤 ကျန်းမာရေးဖိုင် (Profile) — faithful port of renderProfile in
// ~/workspace/health-app/app.js. All Burmese strings copied from app.js.
//
// NOTE on encoding: app.js carries a literal U+FFFD replacement character
// after "ရာသီစက်ဝန်း" in the period checkbox label (a corruption artifact —
// it would render as a replacement glyph). It is dropped here; the text is
// otherwise verbatim.
// Tag add/remove persists immediately (as the web does via saveDB +
// renderProfile); the typed-but-unsaved form fields are preserved because
// the controllers are only re-initialised when the active profile changes.
import 'package:flutter/material.dart';

import '../../models/health_data.dart';
import '../../theme.dart';
import 'tab_common.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with TabLoader<ProfileTab> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _condInput = TextEditingController();
  final _famInput = TextEditingController();
  final _algInput = TextEditingController();

  String _gender = '';
  String _bloodType = '';
  String _goal = 'maintain';
  bool _periodEnabled = false;
  List<String> _conditions = [];
  List<String> _familyHistory = [];
  List<String> _allergies = [];
  String? _initProfileId;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _condInput.dispose();
    _famInput.dispose();
    _algInput.dispose();
    super.dispose();
  }

  void _initFromProfile(HealthProfile p) {
    _initProfileId = p.id;
    _nameCtrl.text = p.name;
    _ageCtrl.text = p.age?.toString() ?? '';
    _heightCtrl.text = p.heightCm?.toString() ?? '';
    _weightCtrl.text = p.weightKg?.toString() ?? '';
    _gender = p.gender;
    _bloodType = p.bloodType;
    _goal = goalLabels.containsKey(p.goal) ? p.goal : 'maintain';
    _periodEnabled = p.periodEnabled;
    _conditions = List.of(p.conditions);
    _familyHistory = List.of(p.familyHistory);
    _allergies = List.of(p.allergies);
  }

  /// Copy the current form state into the profile model (web: pfSave reads
  /// the DOM fields). Name falls back to the existing name when blank.
  void _applyFormToProfile(HealthProfile p) {
    final name = _nameCtrl.text.trim();
    p.name = name.isNotEmpty ? name : p.name;
    p.age = int.tryParse(_ageCtrl.text.trim());
    p.gender = _gender;
    p.bloodType = _bloodType;
    p.heightCm = double.tryParse(_heightCtrl.text.trim());
    p.weightKg = double.tryParse(_weightCtrl.text.trim());
    p.goal = _goal;
    p.periodEnabled = _periodEnabled;
    p.conditions = List.of(_conditions);
    p.familyHistory = List.of(_familyHistory);
    p.allergies = List.of(_allergies);
    p.updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> _save(HealthProfile p) async {
    _applyFormToProfile(p);
    await local.upsert('profiles', p.toJson());
    refresh();
    if (mounted) showToast(context, 'Profile သိမ်းပြီးပါပြီ ✅');
  }

  /// Tags persist immediately in the web app; do the same here.
  Future<void> _persistTags(HealthProfile p) async {
    _applyFormToProfile(p);
    await local.upsert('profiles', p.toJson());
    refresh();
  }

  void _addTag(
    HealthProfile p,
    List<String> list,
    TextEditingController input,
  ) {
    final v = input.text.trim();
    if (v.isEmpty) return;
    setState(() {
      list.add(v);
      input.clear();
    });
    _persistTags(p);
  }

  void _removeTag(HealthProfile p, List<String> list, int i) {
    setState(() => list.removeAt(i));
    _persistTags(p);
  }

  Future<void> _switchProfile(String id) async {
    local.db['activeProfileId'] = id;
    await local.markDirty('profiles');
    await local.save();
    refresh();
  }

  Future<void> _deleteProfile(String id) async {
    final yes = await confirmDialog(
      context,
      'ဖျက်မယ်',
      'ဒီ profile နဲ့ ဆက်စပ်မှတ်တမ်းအားလုံး ဖျက်မှာလား?',
    );
    if (!yes) return;
    final remaining = local
        .list('profiles')
        .where((x) => x['id'] != id)
        .toList();
    await local.setCollection('profiles', remaining);
    for (final c in [
      'meds',
      'foodLog',
      'sleepLog',
      'activityLog',
      'weightLog',
      'symptoms',
      'periodLog',
    ]) {
      await local.setCollection(
        c,
        local.list(c).where((x) => x['profileId'] != id).toList(),
      );
    }
    final plans = local.map('plans');
    plans.remove(id);
    local.db['plans'] = plans;
    await local.markDirty('plans');
    await local.save();
    if (local.db['activeProfileId'] == id && remaining.isNotEmpty) {
      local.db['activeProfileId'] = remaining.first['id'];
      await local.markDirty('profiles');
      await local.save();
    }
    refresh();
  }

  Future<void> _newProfile() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('👥 Profile အသစ်'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'အမည်',
            hintText: 'ဥပမာ အမေ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('မလုပ်ဘူး'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ဖန်တီးမယ်'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final np = HealthProfile(
      id: newId(),
      name: name.isNotEmpty ? name : 'Profile အသစ်',
      goal: 'maintain',
    );
    await local.upsert('profiles', np.toJson());
    local.db['activeProfileId'] = np.id;
    await local.markDirty('profiles');
    await local.save();
    refresh();
    if (mounted) showToast(context, 'Profile အသစ် ဖန်တီးပြီးပါပြီ ✅');
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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _tagSection(
    HealthProfile p,
    String title,
    List<String> list,
    TextEditingController input,
    String hint,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < list.length; i++)
              Chip(
                label: Text(list[i]),
                deleteIcon: const Text('✕'),
                onDeleted: () => _removeTag(p, list, i),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: input,
                decoration: InputDecoration(hintText: hint),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _addTag(p, list, input),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('ထည့်မယ်'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = activeProfile;
    if (p == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Profile မရှိသေးပါ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'စတင်ဖို့ profile အသစ် တစ်ခု ဖန်တီးပါ',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _newProfile,
                child: const Text('👥 Profile အသစ် ဖန်တီးမယ်'),
              ),
            ],
          ),
        ),
      );
    }
    if (_initProfileId != p.id) _initFromProfile(p);
    final bmi = p.bmi;
    final profiles = local.list('profiles');
    final recentSym = local
        .list('symptoms')
        .where((s) => s['profileId'] == p.id)
        .toList()
      ..sort((a, b) =>
          ('${b['date'] ?? ''}${b['time'] ?? ''}')
              .compareTo('${a['date'] ?? ''}${a['time'] ?? ''}'));
    final recentSym10 = recentSym.take(10).toList();
    final ps = calcPeriodSummary(local, p.id);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '👤 ${p.name} ၏ ကျန်းမာရေးဖိုင်',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'အမည်'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'အသက်'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_gender),
                        initialValue: _gender,
                        decoration: const InputDecoration(labelText: 'ကျား/မ'),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('— ရွေးပါ —'),
                          ),
                          DropdownMenuItem(value: 'male', child: Text('ကျား')),
                          DropdownMenuItem(value: 'female', child: Text('မ')),
                        ],
                        onChanged: (v) =>
                            setState(() => _gender = v ?? ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_bloodType),
                        initialValue: _bloodType,
                        decoration: const InputDecoration(
                          labelText: 'သွေးအမျိုးအစား',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('—'),
                          ),
                          for (final b in [
                            'O+',
                            'O-',
                            'A+',
                            'A-',
                            'B+',
                            'B-',
                            'AB+',
                            'AB-',
                          ])
                            DropdownMenuItem(value: b, child: Text(b)),
                        ],
                        onChanged: (v) =>
                            setState(() => _bloodType = v ?? ''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _heightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'အရပ် (cm)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'အလေးချိန် (kg)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoBox(
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      children: [
                        const TextSpan(text: '📏 BMI: '),
                        TextSpan(
                          text: bmi != null ? bmi.toStringAsFixed(1) : '—',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: ' (${bmiLabel(bmi)}) · 🔥 '),
                        const TextSpan(text: 'နေ့စဉ် ကယ်လိုရီရည်မှန်း: '),
                        TextSpan(
                          text: '${p.calorieTarget()} kcal',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(_goal),
                  initialValue: _goal,
                  decoration: const InputDecoration(
                    labelText: 'ကျန်းမာရေး ရည်မှန်းချက်',
                  ),
                  items: [
                    for (final e in goalLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _goal = v ?? 'maintain'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _periodEnabled,
                  onChanged: (v) =>
                      setState(() => _periodEnabled = v ?? false),
                  title: const Text(
                    'ရာသီစက်ဝန်း မှတ်တမ်း သုံးမယ် (အမျိုးသမီးများအတွက်)',
                    style: TextStyle(fontSize: 14),
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                _tagSection(
                  p,
                  'နာတာရှည် ရောဂါရာဇဝင်',
                  _conditions,
                  _condInput,
                  'ဥပမာ သွေးတိုး၊ ဆီးချို',
                ),
                _tagSection(
                  p,
                  'မျိုးရိုးလိုက်ရောဂါများ',
                  _familyHistory,
                  _famInput,
                  'ဥပမာ နှလုံးရောဂါ (အဖေ)',
                ),
                _tagSection(
                  p,
                  'ဓာတ်မတည့်မှုများ (Allergies)',
                  _allergies,
                  _algInput,
                  'ဥပမာ ပုစွန်၊ penicillin',
                ),
                _sectionTitle('📝 လက္ခဏာ မှတ်တမ်း (auto)'),
                if (recentSym10.isEmpty)
                  const Text(
                    'လက္ခဏာ မှတ်တမ်း မရှိသေးပါ — လက္ခဏာ tab မှာ မှတ်ပါ',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  )
                else ...[
                  _infoBox(
                    const Text(
                      'လက္ခဏာ tab မှာ မှတ်လိုက်တာနဲ့ ဒီမှာ auto ပေါ်ပါတယ်',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  for (final s in recentSym10)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${s['name'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Chip(
                                label: Text('အဆင့် ${s['severity'] ?? ''}'),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                          Text(
                            '${fmtDateMm(s['date'] as String? ?? '')} ${fmtTimeMm(s['time'] as String? ?? '')}'
                            '${(s['note'] as String?)?.isNotEmpty == true ? ' · ${s['note']}' : ''}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                _sectionTitle('🩸 ရာသီစက်ဝန်း အကျဉ်းချုပ် (auto)'),
                if (ps.count == 0)
                  const Text(
                    'ရာသီစက်ဝန်း မှတ်တမ်း မရှိသေးပါ — ရာသီစက်ဝန်း tab မှာ မှတ်ပါ',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  )
                else if (ps.count < 2)
                  _infoBox(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            children: [
                              const TextSpan(text: 'နောက်ဆုံး ရာသီ: '),
                              TextSpan(
                                text: fmtDateMm(ps.last ?? ''),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Text(
                          'ခန့်မှန်းဖို့ မှတ်တမ်း အနည်းဆုံး ၂ ခု လိုပါတယ်',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                else
                  _infoBox(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            children: [
                              const TextSpan(text: '📅 ပျမ်းမျှ စက်ဝန်း: '),
                              TextSpan(
                                text: '${ps.avg} ရက်',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: ' · မှတ်တမ်း ${ps.count} ခု',
                              ),
                            ],
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            children: [
                              const TextSpan(text: 'နောက်ဆုံး ရာသီ: '),
                              TextSpan(
                                text: fmtDateMm(ps.last ?? ''),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            children: [
                              const TextSpan(
                                text: 'နောက်တစ်ကြိမ် ခန့်မှန်း: ',
                              ),
                              TextSpan(
                                text: fmtDateMm(ps.next ?? ''),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: (ps.daysLeft ?? 0) >= 0
                                    ? ' (${ps.daysLeft} ရက် အလို)'
                                    : ' (${-(ps.daysLeft ?? 0)} ရက် ကျော်လွန်)',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _save(p),
                  child: const Text('💾 သိမ်းဆည်းမယ်'),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '👥 Profile များ စီမံခန့်ခွဲရန်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final pr in profiles)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${pr['name'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (pr['id'] == local.activeProfileId)
                                const Chip(
                                  label: Text('လက်ရှိ'),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ),
                        if (pr['id'] != local.activeProfileId)
                          OutlinedButton(
                            onPressed: () =>
                                _switchProfile(pr['id'] as String),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            child: const Text('ပြောင်းမယ်'),
                          ),
                        if (profiles.length > 1) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () =>
                                _deleteProfile(pr['id'] as String),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            child: const Text('ဖျက်မယ်'),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _newProfile,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('＋ Profile အသစ်ထည့်ရန်'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
