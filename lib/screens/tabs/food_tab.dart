// 🍚 အစားအစာ (Food) — faithful port of renderFood + geminiFoodVision
// from ~/workspace/health-app/app.js. Every Burmese string is copied
// from app.js, never typed from memory. Blue theme only; no green.
// (ok-box in the web app is green — rendered here in AppTheme.soft blue
// to keep the blue-only rule.)
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/static_data.dart';
import '../../models/health_data.dart';
import '../../services/gemini_service.dart';
import '../../services/key_store.dart';
import '../../theme.dart';
import 'tab_common.dart';

/// Gemini food-vision prompt — copied VERBATIM from geminiFoodVision
/// in app.js (it demands JSON {"items":[...],"totalKcal":...}).
const String _foodVisionPrompt =
    'Analyze this food photo. Identify each visible food item and estimate calories '
    'for a typical serving. Reply ONLY with JSON: {"items":[{"name":"<Burmese name>","kcal":<number>}],"totalKcal":<number>}. '
    'Use Burmese (Myanmar script) for names. If no food is visible, return {"items":[],"totalKcal":0}.';

class _PickedPhoto {
  _PickedPhoto(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

class FoodTab extends StatefulWidget {
  const FoodTab({super.key});

  @override
  State<FoodTab> createState() => _FoodTabState();
}

class _FoodTabState extends State<FoodTab> with TabLoader<FoodTab> {
  bool _photoMode = false;

  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '1');
  final _kcalCtrl = TextEditingController();
  final _exMinCtrl = TextEditingController(text: '30');
  int _exIndex = 0;
  bool _dropOpen = false;
  FoodItem? _matched;

  final _photos = <_PickedPhoto>[];
  bool _hasKeys = false;
  bool _analyzing = false;
  String _analyzeStatus = '';
  List<({String name, int kcal})> _aiItems = [];
  int _aiFailed = 0;
  bool _aiShown = false;
  String _aiError = '';

  @override
  void initState() {
    super.initState();
    KeyStore().load().then((_) {
      if (mounted) setState(() => _hasKeys = KeyStore().hasKeys);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    _kcalCtrl.dispose();
    _exMinCtrl.dispose();
    super.dispose();
  }

  // ---------------- derived data (web: renderFood locals) ----------------

  /// Web calorieTarget(): manual settings target, else Mifflin-St Jeor.
  int _calorieTarget(HealthProfile p) {
    final s = local.map('settings');
    if (s['calorieTargetMode'] == 'manual') {
      return toInt(s['calorieTarget']) ?? 2000;
    }
    return p.calorieTarget();
  }

  List<Map<String, dynamic>> _todaysLogs(HealthProfile p) {
    final t = todayStr();
    final logs = local
        .list('foodLog')
        .where((f) =>
            f['profileId'] == p.id &&
            f['date'] == t &&
            (f['deleted'] as bool?) != true)
        .toList()
      ..sort((a, b) => (b['time'] as String? ?? '')
          .compareTo(a['time'] as String? ?? ''));
    return logs;
  }

  double get _amount {
    final v = double.tryParse(_amountCtrl.text.trim());
    return (v == null || v <= 0) ? 1 : v;
  }

  String _fmtAmt(double v) =>
      v == v.truncateToDouble() ? '${v.toInt()}' : '$v';

  /// Web: foodSearch input handler — exact match, else substring match;
  /// kcal is ALWAYS recalculated as baseKcal x amount.
  void _updateMatch() {
    final q = _searchCtrl.text.trim();
    final hit = foodDb.where((f) => f.name == q).firstOrNull ??
        (q.isEmpty
            ? null
            : foodDb.where((f) => f.name.contains(q)).firstOrNull);
    setState(() {
      _matched = hit;
      if (hit != null) {
        _kcalCtrl.text = '${(hit.kcal * _amount).round()}';
      }
    });
  }

  List<FoodItem> get _dropFoods {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return foodDb;
    return foodDb.where((f) => f.name.contains(q)).toList();
  }

  // ---------------- text-mode save ----------------

  Future<void> _saveTextEntry(HealthProfile p) async {
    final name = _matched?.name ?? _searchCtrl.text.trim();
    if (name.isEmpty) {
      showToast(context, 'အစားအစာ အမည် ထည့်ပေးပါ');
      return;
    }
    final kcal = int.tryParse(_kcalCtrl.text.trim());
    if (kcal == null || kcal <= 0) {
      showToast(context, 'ကယ်လိုရီ ထည့်ပေးပါ');
      return;
    }
    await local.upsert('foodLog', {
      'id': newId(),
      'profileId': p.id,
      'date': todayStr(),
      'time': nowHm(),
      'name': name,
      'kcal': kcal,
      'amount': '${_amountCtrl.text.trim().isEmpty ? '1' : _amountCtrl.text.trim()} စား',
      'source': 'text',
      'deleted': false,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    _searchCtrl.clear();
    _amountCtrl.text = '1';
    _kcalCtrl.clear();
    setState(() {
      _matched = null;
      _dropOpen = false;
    });
    refresh();
    if (mounted) showToast(context, 'မှတ်တမ်းတင်ပြီးပါပြီ ✅');
  }

  // ---------------- photo mode ----------------

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    try {
      if (source == ImageSource.camera) {
        final x = await picker.pickImage(source: ImageSource.camera);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        setState(() {
          _photos.add(_PickedPhoto(bytes, x.mimeType ?? 'image/jpeg'));
          _aiShown = false;
          _aiError = '';
        });
      } else {
        final xs = await picker.pickMultiImage();
        for (final x in xs) {
          final bytes = await x.readAsBytes();
          _photos.add(_PickedPhoto(bytes, x.mimeType ?? 'image/jpeg'));
        }
        setState(() {
          _aiShown = false;
          _aiError = '';
        });
      }
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  /// Web: analyze button handler — one Gemini call per photo, sequentially;
  /// parse the {...} substring; accumulate items, count failures.
  Future<void> _analyzePhotos(HealthProfile p) async {
    if (_photos.isEmpty) {
      showToast(context, 'အရင်ပုံ ရွေးပေးပါ');
      return;
    }
    final settings = local.map('settings');
    final modelRaw = strVal(settings['geminiModel']);
    final model =
        modelRaw.isEmpty ? GeminiService.defaultModel : modelRaw;
    final gemini = GeminiService(KeyStore(), model: model);
    setState(() {
      _analyzing = true;
      _aiShown = false;
      _aiError = '';
      _aiItems = [];
      _aiFailed = 0;
    });
    final allItems = <({String name, int kcal})>[];
    var failed = 0;
    try {
      for (var pi = 0; pi < _photos.length; pi++) {
        if (!mounted) return;
        setState(() =>
            _analyzeStatus = 'ပုံ ${pi + 1}/${_photos.length} ဆန်းစစ်နေသည်…');
        try {
          final photo = _photos[pi];
          final text = await gemini.generate(
            _foodVisionPrompt,
            media: [
              GeminiMedia(
                mimeType: photo.mimeType,
                base64: base64Encode(photo.bytes),
              ),
            ],
          );
          final jm = RegExp(r'\{.*\}', dotAll: true).firstMatch(text);
          if (jm == null) throw GeminiException('AI အဖြေကို ဖတ်မရပါ');
          final parsed = jsonDecode(jm.group(0)!) as Map<String, dynamic>;
          final items = (parsed['items'] as List?) ?? [];
          for (final it in items) {
            if (it is Map) {
              allItems.add((
                name: '${it['name'] ?? ''}',
                kcal: toInt(it['kcal']) ?? 0,
              ));
            }
          }
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      setState(() {
        _aiItems = allItems;
        _aiFailed = failed;
        _aiShown = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiError = 'AI ခေါ်ဆို၍မရပါ: $e');
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _analyzeStatus = '';
        });
      }
    }
  }

  Future<void> _saveAiItems(HealthProfile p) async {
    for (final i in _aiItems) {
      await local.upsert('foodLog', {
        'id': newId(),
        'profileId': p.id,
        'date': todayStr(),
        'time': nowHm(),
        'name': i.name,
        'kcal': i.kcal,
        'amount': '1 စား',
        'source': 'photo-ai',
        'deleted': false,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
    setState(() {
      _photos.clear();
      _aiItems = [];
      _aiFailed = 0;
      _aiShown = false;
      _aiError = '';
    });
    refresh();
    if (mounted) showToast(context, 'မှတ်တမ်းတင်ပြီးပါပြီ ✅');
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final p = activeProfile;
    if (!loaded || p == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final target = _calorieTarget(p);
    final logs = _todaysLogs(p);
    final kcalToday =
        logs.fold<int>(0, (a, f) => a + (toInt(f['kcal']) ?? 0));
    final pct = (kcalToday / target * 100).round().clamp(0, 100);
    final weight = p.weightKg ?? 60;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(kcalToday, target, pct),
        if (kcalToday > target) _buildOverAlert(kcalToday - target, weight),
        if (kcalToday <= target && kcalToday >= target * 0.9)
          _buildWarnBox(target - kcalToday),
        _buildBurnCard(weight),
        _buildAddCard(p),
        _buildLogCard(logs),
      ],
    );
  }

  Widget _buildSummaryCard(int kcalToday, int target, int pct) {
    final over = kcalToday > target;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🍚 ဒီနေ့ စားသုံးမှု',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$kcalToday kcal',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ရည်မှန်း $target kcal',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: pct / 100,
              minHeight: 10,
              backgroundColor: AppTheme.soft,
              color: over ? AppTheme.danger : AppTheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverAlert(int over, double weight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.dangerBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '⚠️ ဒီနေ့ ရည်မှန်းချက် ကျော်နေပါပြီ — $over kcal ပိုစားထားပါတယ်။\n'
        'ကျန်တဲ့အချိန်မှာ အစာလျှော့စားပြီး လေ့ကျင့်ခန်းလုပ်ပါ။\n'
        '🔥 ပိုနေတဲ့ ကယ်လိုရီ လောင်ကျွမ်းဖို့: လမ်းလျှောက် ~${burnMinutes(3.5, weight, over)} မိနစ် '
        '(သို့) လမ်းမြန်မြန်လျှောက် ~${burnMinutes(4.3, weight, over)} မိနစ် '
        '(သို့) ပြေး ~${burnMinutes(9.8, weight, over)} မိနစ်',
        style: const TextStyle(color: AppTheme.danger),
      ),
    );
  }

  Widget _buildWarnBox(int remaining) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.amberBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '⚠️ ရည်မှန်းချက် နီးနေပါပြီ — $remaining kcal ပဲ ကျန်ပါတယ်။ ကျန်တဲ့အချိန်မှာ အစာကို သတိထားစားပါ။',
        style: const TextStyle(color: AppTheme.amber),
      ),
    );
  }

  Widget _buildBurnCard(double weight) {
    final e = exerciseBurn[_exIndex];
    final min = int.tryParse(_exMinCtrl.text.trim()) ?? 30;
    final safeMin = min < 1 ? 30 : min;
    final burned = burnKcal(e.met, weight, safeMin);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔥 လေ့ကျင့်ခန်း ကယ်လိုရီ တွက်စက်',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'ကိုယ်အလေးချိန် ${_fmtAmt(weight)} kg အတွက် တွက်ထားတာပါ',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text('လေ့ကျင့်ခန်း'),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              key: ValueKey(_exIndex),
              initialValue: _exIndex,
              isExpanded: true,
              items: [
                for (var i = 0; i < exerciseBurn.length; i++)
                  DropdownMenuItem(value: i, child: Text(exerciseBurn[i].name)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _exIndex = v);
              },
            ),
            const SizedBox(height: 12),
            const Text('မိနစ်'),
            const SizedBox(height: 4),
            TextField(
              controller: _exMinCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.soft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '🔥 ${e.name} $safeMin မိနစ် လုပ်ရင် လောင်ကျွမ်းမည့် ကယ်လိုရီ: ~$burned kcal',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddCard(HealthProfile p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '➕ မှတ်တမ်းထည့်ရန်',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _photoMode
                      ? OutlinedButton(
                          onPressed: () => setState(() => _photoMode = false),
                          child: const Text('✍️ စာနဲ့ထည့်မယ်'),
                        )
                      : ElevatedButton(
                          onPressed: () {},
                          child: const Text('✍️ စာနဲ့ထည့်မယ်'),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _photoMode
                      ? ElevatedButton(
                          onPressed: () {},
                          child: const Text('📷 ပုံနဲ့ထည့်မယ်'),
                        )
                      : OutlinedButton(
                          onPressed: () => setState(() => _photoMode = true),
                          child: const Text('📷 ပုံနဲ့ထည့်မယ်'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_photoMode) _buildTextPane(p) else _buildPhotoPane(p),
          ],
        ),
      ),
    );
  }

  Widget _buildTextPane(HealthProfile p) {
    final q = _searchCtrl.text.trim();
    final hit = _matched;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('အစားအစာ ရှာရန် / ရိုက်ထည့်ရန်'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => _updateMatch(),
                decoration: const InputDecoration(
                  hintText: 'ဥပမာ ထမင်း၊ ကြက်သားဟင်း…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => setState(() => _dropOpen = !_dropOpen),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('▼', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
        if (_dropOpen) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.soft),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _dropFoods.isEmpty
                ? const ListTile(title: Text('မတွေ့ပါ'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _dropFoods.length,
                    itemBuilder: (ctx, i) {
                      final f = _dropFoods[i];
                      return ListTile(
                        dense: true,
                        title: RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(ctx).style,
                            children: [
                              TextSpan(
                                text: f.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: ' — ${f.kcal} kcal / ${f.unit}',
                                style: const TextStyle(
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () {
                          _searchCtrl.text = f.name;
                          setState(() => _dropOpen = false);
                          _updateMatch();
                        },
                      );
                    },
                  ),
          ),
        ],
        if (hit != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '✅ ${hit.name} — ${hit.kcal} kcal / ${hit.unit} → ပမာဏ ${_fmtAmt(_amount)} = ${(hit.kcal * _amount).round()} kcal',
            ),
          ),
        ] else if (q.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.amberBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'စာရင်းထဲမှာ မတွေ့ပါ — ကယ်လိုရီကို လက်နဲ့ထည့်ပေးပါ',
              style: TextStyle(color: AppTheme.amber),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ပမာဏ (စားသုံးမှုအရေအတွက်)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _updateMatch(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ကယ်လိုရီ (လက်နဲ့ပြင်နိုင်သည်)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _kcalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'kcal'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => _saveTextEntry(p),
          child: const Text('မှတ်တမ်းတင်မယ်'),
        ),
      ],
    );
  }

  Widget _buildPhotoPane(HealthProfile p) {
    final totalKcal =
        _aiItems.fold<int>(0, (a, i) => a + i.kcal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('အစားအစာ ပုံရိုက်ရန် / ရွေးရန် (များများ ရွေးနိုင်ပါတယ်)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _pickPhoto(ImageSource.camera),
                child: const Text('📷 ရိုက်မယ်'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickPhoto(ImageSource.gallery),
                child: const Text('🖼️ ရွေးမယ်'),
              ),
            ),
          ],
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _photos[i].bytes,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _photos.removeAt(i);
                          _aiShown = false;
                          _aiError = '';
                        }),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: AppTheme.danger,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '✕',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (_aiShown && _aiItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.amberBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'ပုံတွေထဲမှာ အစားအစာ မတွေ့ပါ',
              style: TextStyle(color: AppTheme.amber),
            ),
          )
        else if (_aiShown)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'AI တွေ့ရှိချက် (စုစုပေါင်း $totalKcal kcal):\n'
              '${_aiItems.map((i) => '• ${i.name} — ${i.kcal} kcal').join('\n')}'
              '${_aiFailed > 0 ? '\nပုံ $_aiFailed ပုံ ဆန်းစစ်၍မရပါ' : ''}',
            ),
          ),
        if (_aiShown && _aiItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _saveAiItems(p),
            child: const Text('ဒီအတိုင်း မှတ်တမ်းတင်မယ်'),
          ),
        ],
        if (_aiError.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.dangerBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _aiError,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_hasKeys)
          ElevatedButton(
            onPressed: _analyzing ? null : () => _analyzePhotos(p),
            child: Text(
              _analyzing
                  ? _analyzeStatus
                  : '✨ AI နဲ့ ပုံများကို ဆန်းစစ်မယ်${_photos.isNotEmpty ? ' (${_photos.length} ပုံ)' : ''}',
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '📷 ပုံမှ AI ဆန်းစစ်ချက်ရဖို့ Settings မှာ Gemini API key ထည့်ထားရပါမယ်။ Key မရှိရင် ပုံကြည့်ပြီး အောက်က စာနဲ့ထည့်တဲ့နည်းနဲ့ မှတ်နိုင်ပါတယ်။',
            ),
          ),
      ],
    );
  }

  Widget _buildLogCard(List<Map<String, dynamic>> logs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📝 ဒီနေ့ မှတ်တမ်းများ',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              const Text(
                'မရှိသေးပါ',
                style: TextStyle(color: Colors.black54),
              ),
            for (final f in logs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        fmtTimeMm((f['time'] as String?) ?? ''),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${f['name'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${f['amount'] ?? ''}'
                            '${f['source'] == 'photo-ai' ? ' · 📷 AI' : ''}',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${toInt(f['kcal']) ?? 0} kcal',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        await local.softDelete('foodLog', '${f['id']}');
                        refresh();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('ဖျက်မယ်'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
