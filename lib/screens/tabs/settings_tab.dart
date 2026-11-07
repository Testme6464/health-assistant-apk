// ⚙️ ဆက်တင် — account + sync + API Keys + Gemini model + backup + wipe.
// Ports the web app's renderSettings (Gemini-only mode); the Keys tab itself
// lives in lib/screens/keys_screen.dart.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/health_data.dart';
import '../../services/auth_service.dart';
import '../../services/gemini_service.dart';
import '../../services/key_store.dart';
import '../../services/local_store.dart';
import '../../services/sync_service.dart';
import '../../theme.dart';
import '../keys_screen.dart';
import 'tab_common.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> with TabLoader<SettingsTab> {
  final _sync = SyncService();
  bool _signingOut = false;

  void _openKeys() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KeysScreen()),
    );
  }

  Future<void> _signOut() async {
    final yes = await confirmDialog(
      context,
      'ထွက်မလား?',
      'Google အကောင့်က ထွက်လိုက်ပါမယ်။ ဖုန်းထဲက data တွေ မပျက်ပါ။',
    );
    if (!yes) return;
    setState(() => _signingOut = true);
    await AuthService().signOut();
    if (mounted) setState(() => _signingOut = false);
  }

  Future<void> _export() async {
    try {
      final json = jsonEncode(local.db);
      final f = File(
        '${Directory.systemTemp.path}/health-app-backup-${todayStr()}.json',
      );
      await f.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(f.path)], subject: 'Health app backup'),
      );
      if (mounted) showToast(context, 'Export လုပ်ပြီးပါပြီ ✅');
    } catch (e) {
      if (mounted) showToast(context, 'Export မရပါ: $e');
    }
  }

  Future<void> _import() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return;
      final path = files.single.path;
      if (path == null) return;
      final parsed = jsonDecode(await File(path).readAsString());
      if (parsed is! Map ||
          parsed['version'] != 1 ||
          parsed['profiles'] is! List) {
        if (mounted) showToast(context, 'ဖိုင်ပုံစံ မမှန်ပါ');
        return;
      }
      if (!mounted) return;
      final yes = await confirmDialog(
        context,
        'Import လုပ်မှာလား?',
        'လက်ရှိ data အားလုံး အစားထိုးမှာလား?',
      );
      if (!yes) return;
      final map = Map<String, dynamic>.from(parsed);
      local.db.clear();
      local.db.addAll(map);
      for (final c in LocalStore.collections) {
        await local.markDirty(c);
      }
      await local.save();
      if (!mounted) return;
      refresh();
      showToast(context, 'Import လုပ်ပြီးပါပြီ ✅');
    } catch (e) {
      if (mounted) showToast(context, 'Import မအောင်မြင်ပါ: $e');
    }
  }

  Future<void> _wipe() async {
    final yes1 = await confirmDialog(
      context,
      'တကယ် ဖျက်မှာလား?',
      'ဒါကို ပြန်မရနိုင်ပါ!',
    );
    if (!yes1) return;
    if (!mounted) return;
    final yes2 = await confirmDialog(
      context,
      'နောက်တစ်ကြိမ် အတည်ပြုပါ',
      'data အားလုံး ပျောက်မှာပါ',
    );
    if (!yes2) return;
    await local.resetDb();
    if (!mounted) return;
    refresh();
    showToast(context, 'ဖျက်ပြီးပါပြီ');
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final user = AuthService().currentUser;
    final settings = local.map('settings');
    final modelRaw = strVal(settings['geminiModel']);
    final model =
        modelRaw.isEmpty ? GeminiService.defaultModel : modelRaw;
    final keyCount = KeyStore().keys.length;
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
                  '👤 အကောင့်',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(user?.displayName ?? '—'),
                Text(
                  user?.email ?? '',
                  style: const TextStyle(color: Colors.grey),
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
                  '🔄 Server Sync (Firestore)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<SyncStatus>(
                  valueListenable: _sync.status,
                  builder: (context, s, _) => Text(s.labelMm),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Offline မှာ ဖုန်းထဲမှာ သိမ်းထားပြီး online ဖြစ်တာနဲ့ အလိုလို server ကို ပို့ပါတယ်။',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _sync.syncNow(),
                  icon: const Icon(Icons.sync),
                  label: const Text('အခု Sync လုပ်မယ်'),
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
                  '🤖 Gemini AI (BYOK)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Key တွေကို ဒီဖုန်းထဲမှာပဲ သိမ်းထားပါတယ် — server ကို မပို့ပါ။',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text('Gemini Model (အခမဲ့ free tier ရတာတွေချည်း)'),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey(model),
                  initialValue: GeminiService.freeModels.contains(model)
                      ? model
                      : GeminiService.defaultModel,
                  isExpanded: true,
                  items: [
                    for (final m in GeminiService.freeModels)
                      DropdownMenuItem(
                        value: m,
                        child: Text(
                          m +
                              (m == 'gemini-3.8-flash' ? ' (အကြံပြု)' : ''),
                        ),
                      ),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    settings['geminiModel'] = v;
                    local.db['settings'] = settings;
                    await local.markDirty('settings');
                    await local.save();
                    refresh();
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'လက်ရှိ AI: ${keyCount > 0 ? 'Gemini ($model, key $keyCount ခု)' : 'မရှိပါ (offline mode)'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.key, color: AppTheme.amber),
            title: const Text('🔑 API Keys'),
            subtitle: const Text('Gemini key များ စီမံခန့်ခွဲခြင်း'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openKeys,
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💾 Data Backup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _export,
                        child: const Text('⬇️ Export (JSON)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _import,
                        child: const Text('⬆️ Import (JSON)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'မှတ်တမ်းအားလုံးကို ဖိုင်အဖြစ် သိမ်းနိုင် / ပြန်ထည့်နိုင်ပါတယ်',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔗 ချိတ်ဆက်မှုများ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '❤️ Health Connect — APK နောက်အဆင့်မှာ ရမယ်',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔒 Privacy',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Data အားလုံး သင့်အကောင့်နဲ့ Firebase server မှာ သိမ်းထားပြီး ဖုန်းထဲမှာလည်း offline သုံးဖို့ မိတ္တူရှိပါတယ်။',
                  style: TextStyle(fontSize: 13),
                ),
                SizedBox(height: 4),
                Text(
                  'App version 1.0.0 (release)။',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _wipe,
          icon: const Icon(Icons.delete_forever, color: AppTheme.danger),
          label: const Text(
            'Data အားလုံး ဖျက်မယ်',
            style: TextStyle(color: AppTheme.danger),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _signingOut ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: Text(
            _signingOut ? 'ထွက်နေသည်…' : 'Google အကောင့်က ထွက်မယ်',
          ),
        ),
      ],
    );
  }
}
