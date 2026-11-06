// 🚨 အရေးပေါ် (Emergency) — faithful port of renderEmergency in
// ~/workspace/health-app/app.js. All Burmese strings copied from app.js.
// Contacts are global in the web app (not filtered by profile) — kept so.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/health_data.dart';
import '../../theme.dart';
import 'tab_common.dart';

class EmergencyTab extends StatefulWidget {
  const EmergencyTab({super.key});

  @override
  State<EmergencyTab> createState() => _EmergencyTabState();
}

class _EmergencyTabState extends State<EmergencyTab>
    with TabLoader<EmergencyTab> {
  Future<void> _addContact() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📞 ဆက်သွယ်ရန် ထည့်မယ်'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'အမည် *',
                  hintText: 'ဥပမာ အမေ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'ဖုန်းနံပါတ် *',
                  hintText: 'ဥပမာ 09xxxxxxxxx',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: relCtrl,
                decoration: const InputDecoration(
                  labelText: 'တော်စပ်ပုံ',
                  hintText: 'ဥပမာ မိခင်',
                ),
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
            onPressed: () {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              if (name.isEmpty || phone.isEmpty) {
                showToast(ctx, 'အမည် နှင့် ဖုန်း ထည့်ပေးပါ');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('သိမ်းမယ်'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await local.upsert('emergencyContacts', {
      'id': newId(),
      'name': nameCtrl.text.trim(),
      'phone': phoneCtrl.text.trim(),
      'relation': relCtrl.text.trim(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    refresh();
    if (mounted) showToast(context, 'ထည့်ပြီးပါပြီ ✅');
  }

  Future<void> _call(String phone) async {
    await launchUrl(
      Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
    );
  }

  Future<void> _deleteContact(String id) async {
    await local.softDelete('emergencyContacts', id);
    refresh();
  }

  Widget _infoRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: value),
        ],
      ),
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
    final meds = local
        .list('meds')
        .where((m) => m['profileId'] == p.id)
        .map((m) => '${m['name'] ?? ''}')
        .where((n) => n.isNotEmpty)
        .toList();
    final contacts = local.list('emergencyContacts');

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
                  '🚨 အရေးပေါ် အချက်အလက်',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _infoRow('အမည်', Text(p.name)),
                _infoRow(
                  'သွေးအမျိုးအစား',
                  Text(
                    p.bloodType.isEmpty ? '—' : p.bloodType,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.danger,
                    ),
                  ),
                ),
                _infoRow(
                  'ဓာတ်မတည့်မှု',
                  Text(p.allergies.isEmpty ? '—' : p.allergies.join(', ')),
                ),
                _infoRow(
                  'နာတာရှည်ရောဂါ',
                  Text(p.conditions.isEmpty ? '—' : p.conditions.join(', ')),
                ),
                _infoRow(
                  'သောက်နေသောဆေးများ',
                  Text(meds.isEmpty ? '—' : meds.join(', ')),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        '📞 အရေးပေါ် ဆက်သွယ်ရမည့်သူများ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _addContact,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('＋ ထည့်မယ်'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (contacts.isEmpty)
                  const Text(
                    'မထည့်ရသေးပါ',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                for (final c in contacts)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${c['name'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${(c['relation'] as String?)?.isNotEmpty == true ? '${c['relation']} · ' : ''}${c['phone'] ?? ''}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              _call('${c['phone'] ?? ''}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                          ),
                          child: const Text('📞 ခေါ်မယ်'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              _deleteContact(c['id'] as String),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                          ),
                          child: const Text('ဖျက်မယ်'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  '💡 အရေးပေါ်အခြေအနေမှာ အထက်ပါ ခလုတ်နှိပ်ရုံနဲ့ ဖုန်းခေါ်နိုင်ပါတယ်',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
