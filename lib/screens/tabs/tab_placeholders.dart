import 'package:flutter/material.dart';

import '../../models/health_data.dart';
import '../../services/auth_service.dart';
import '../../services/local_store.dart';
import '../../services/sync_service.dart';
import '../../theme.dart';
import '../keys_screen.dart';

/// Stage-1 tab screens.
/// [HomeTab] and [SettingsTab] are functional (local cache + sync status);
/// the other ten are placeholders with the real titles and the planned
/// feature list from the web app — the full port is stage 2.

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.description,
    required this.features,
  });

  final String icon;
  final String title;
  final String description;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$icon $title',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(description, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const Text('ပါဝင်မယ့် လုပ်ဆောင်ချက်များ',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final f in features)
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline,
                  color: AppTheme.primary),
              title: Text(f, style: const TextStyle(fontSize: 14)),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Stage 2 မှာ web app က လုပ်ဆောင်ချက်အပြည့်အစုံ ထည့်မယ်။',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}

/// 🏠 ပင်မ — functional: reads the local offline cache.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _local = LocalStore();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _local.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = _local.activeProfile;
    final today = todayStr();
    final settings = _local.map('settings');
    final foodToday = _local
        .list('foodLog')
        .where((f) =>
            f['profileId'] == p?.id &&
            f['date'] == today &&
            f['deleted'] != true)
        .fold<int>(0, (a, f) => a + ((f['kcal'] as num?)?.toInt() ?? 0));
    final waterToday =
        (_local.map('waterLog')[today] as num?)?.toInt() ?? 0;
    final kcalTarget = p?.calorieTarget(
          manualTarget: (settings['calorieTarget'] as num?)?.toInt(),
          manualMode: settings['calorieTargetMode'] == 'manual',
        ) ??
        2000;
    final waterTarget = (settings['waterTargetMl'] as num?)?.toInt() ?? 2000;
    final bmi = p?.bmi;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ဒီနေ့ အကျဉ်းချုပ် — $today',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '${p?.name ?? 'ကျွန်ုပ်'} · ရည်မှန်းချက်: ${goalLabels[p?.goal ?? 'maintain'] ?? ''}',
                  style: const TextStyle(color: Colors.grey),
                ),
                if (bmi != null)
                  Text('BMI: ${bmi.toStringAsFixed(1)} (${bmiLabel(bmi)})'),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'ကယ်လိုရီ',
                value: '$foodToday / $kcalTarget kcal',
                pct: (foodToday / kcalTarget).clamp(0.0, 1.0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'ရေ',
                value: '$waterToday / $waterTarget ml',
                pct: (waterToday / waterTarget).clamp(0.0, 1.0),
              ),
            ),
          ],
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '💡 Stage 1: Home tab က local cache က data ကိုပဲ ပြပါတယ်။ '
              'Food, Meds, Plan စတဲ့ tab တွေ အပြည့်အစုံကို Stage 2 မှာ ထည့်မယ်။',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.pct,
  });

  final String title;
  final String value;
  final double pct;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: pct,
              backgroundColor: AppTheme.soft,
              color: AppTheme.primary,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🍚 အစားအသောက်
class FoodTab extends StatelessWidget {
  const FoodTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '🍚',
      title: 'အစားအသောက်',
      description: 'ဒီနေ့ စားသုံးမှု ကယ်လိုရီ၊ အစားအစာ မှတ်တမ်း၊ ပုံနဲ့ AI ဆန်းစစ်ချက်။',
      features: [
        'ဒီနေ့ စားသုံးမှု (ရည်မှန်းချက် ကျော်ရင် သတိပေးစာတန်း)',
        'အစားအစာ ၆၀ မျိုးမှ ရှာဖွေ ထည့်သွင်းခြင်း',
        'ပုံနဲ့ AI ဆန်းစစ်ချက် (Gemini)',
        'လေ့ကျင့်ခန်း ကယ်လိုရီ တွက်စက်',
      ],
    );
  }
}

/// 📊 တိုးတက်မှု
class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '📊',
      title: 'တိုးတက်မှု',
      description: 'ကိုယ်အလေးချိန်၊ ကယ်လိုရီ၊ ရေ၊ အိပ်ချိန်တို့၏ တိုးတက်မှု ဇယားများ။',
      features: [
        'ကိုယ်အလေးချိန် ဇယား (နောက်ဆုံး ၁၄ မှတ်)',
        '၇ ရက် အကျဉ်းချုပ် (ကယ်လိုရီ၊ ရေ၊ ခြေလှမ်း၊ ဆေး)',
        'ကိုယ်အလေးချိန် မှတ်တမ်း ထည့်သွင်းခြင်း (profile weight auto-sync)',
      ],
    );
  }
}

/// 💊 ဆေးဝါးများ
class MedsTab extends StatelessWidget {
  const MedsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '💊',
      title: 'ဆေးဝါးများ',
      description: 'ဆေးမှတ်တမ်း၊ သောက်ချိန်၊ ဆေးအပြန်အလှန် သက်ရောက်မှု စစ်ဆေးခြင်း။',
      features: [
        'ဆေး ထည့်/ပြင်/ဖျက် (သောက်ချိန်၊ လက်ကျန်ရက်)',
        'ဆေး ၃၀ မျိုး အပြန်အလှန် သက်ရောက်မှု စစ်ဆေးခြင်း',
        'ဒီနေ့ သောက်ရမယ့် ဆေး စာရင်း',
      ],
    );
  }
}

/// 🗓️ အစီအစဉ်
class PlanTab extends StatelessWidget {
  const PlanTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '🗓️',
      title: 'အစီအစဉ်',
      description: 'BMI အကဲဖြတ်ချက်၊ ရည်မှန်းချက် ၃ ခု၊ အစားအသောက် + လေ့ကျင့်ခန်း အစီအစဉ်။',
      features: [
        'BMI အကဲဖြတ်ချက် → ရည်မှန်းချက် ရွေးချယ်မှု (တိုး/ထိန်း/ချ)',
        'ကယ်လိုရီ၊ အစားအသောက် (အချိန်နဲ့ အကြောင်းပြချက်), ၄ ပတ် လေ့ကျင့်ခန်း',
        'တစ်ရက်ချင်းစာ လမ်းညွှန် (ဒီနေ့)',
        'AI နဲ့ ထုတ်လုပ်ခြင်း (Gemini) / offline စည်းမျဉ်း',
      ],
    );
  }
}

/// 🩸 ရာသီစက်ဝန်း
class PeriodTab extends StatelessWidget {
  const PeriodTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '🩸',
      title: 'ရာသီစက်ဝန်း',
      description: 'ရာသီ မှတ်တမ်း၊ ပျမ်းမျှ စက်ဝန်း၊ နောက်တစ်ကြိမ် ခန့်မှန်းချက်။',
      features: [
        'ရာသီ စတင်ရက် မှတ်တမ်း',
        'ပျမ်းမျှ စက်ဝန်း + နောက်တစ်ကြိမ် ခန့်မှန်းချက်',
        'Profile မှာ အလိုလို အကျဉ်းချုပ် ပေါ်ခြင်း',
      ],
    );
  }
}

/// 📝 လက္ခဏာ
class SymptomTab extends StatelessWidget {
  const SymptomTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '📝',
      title: 'လက္ခဏာ',
      description: 'လက္ခဏာ မှတ်တမ်း (၁၈ မျိုး)၊ ပြင်းထန်မှု၊ အိပ်မက်ဆိုး မှတ်တမ်း။',
      features: [
        'လက္ခဏာ ၁၈ မျိုး + ပြင်းထန်မှု အဆင့်',
        'အိပ်ချိန် အရည်အသွေး + အိပ်မက်ဆိုး မှတ်တမ်း',
        'Profile မှာ လက္ခဏာ မှတ်တမ်း အလိုလို ပေါ်ခြင်း',
      ],
    );
  }
}

/// ⏰ သတိပေးချက်များ
class RemindTab extends StatelessWidget {
  const RemindTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '⏰',
      title: 'သတိပေးချက်များ',
      description: 'ရေ၊ ဆေး၊ အိပ်ချိန် သတိပေးချက်များ၊ လှုပ်ရှားမှု မှတ်တမ်း။',
      features: [
        'ရေ/ဆေး/အိပ်ချိန် သတိပေးချက် အချိန်ဇယား',
        'အစားအသောက် ကြိုစီစဉ်မှု သတိပေးချက်',
        'လှုပ်ရှားမှု (ခြေလှမ်း + လေ့ကျင့်ခန်း ကယ်လိုရီ)',
      ],
    );
  }
}

/// 👤 ကျန်းမာရေးဖိုင်
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '👤',
      title: 'ကျန်းမာရေးဖိုင်',
      description: 'Profile များ၊ BMI၊ ရောဂါ၊ ဓာတ်မတည့်မှု၊ လက္ခဏာ/ရာသီ အကျဉ်းချုပ်။',
      features: [
        'Profile များ ဖန်တီး/ပြောင်းလဲခြင်း',
        'BMI၊ အသက်၊ အရပ်၊ ကိုယ်အလေးချိန်',
        'ရောဂါ၊ မိသားစု ရာဇဝင်၊ ဓာတ်မတည့်မှု',
        'လက္ခဏာ မှတ်တမ်း + ရာသီစက်ဝန်း အကျဉ်းချုပ် (auto)',
      ],
    );
  }
}

/// 🖨️ အစီရင်ခံစာ
class ReportTab extends StatelessWidget {
  const ReportTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '🖨️',
      title: 'အစီရင်ခံစာ',
      description: 'ဆရာဝန်ပြဖို့ အစီရင်ခံစာ (PDF) တစ်ချက်နှိပ်ထုတ်ခြင်း။',
      features: [
        'Profile + ဆေး + လက္ခဏာ + တိုးတက်မှု အကျဉ်းချုပ်',
        'PDF အဖြစ် သိမ်းဆည်း / မျှဝေခြင်း',
      ],
    );
  }
}

/// 🚨 အရေးပေါ်
class EmergencyTab extends StatelessWidget {
  const EmergencyTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderTab(
      icon: '🚨',
      title: 'အရေးပေါ်',
      description: 'အရေးပေါ် ဆက်သွယ်ရမယ့် လူများ၊ အရေးပေါ် အချက်အလက် ကတ်။',
      features: [
        'အရေးပေါ် ဆက်သွယ်ရန် လူများ (ဖုန်းနံပါတ်)',
        'သွေးအမျိုးအစား၊ ရောဂါ၊ ဓာတ်မတည့်မှု အကျဉ်းချုပ်',
      ],
    );
  }
}

/// ⚙️ ဆက်တင် — functional: sync status, API Keys, sign-out.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final _sync = SyncService();
  bool _signingOut = false;

  void _openKeys() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KeysScreen()),
    );
  }

  Future<void> _signOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ထွက်မလား?'),
        content: const Text(
            'Google အကောင့်က ထွက်လိုက်ပါမယ်။ ဖုန်းထဲက data တွေ မပျက်ပါ။'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('မထွက်ဘူး'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ထွက်မယ်'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _signingOut = true);
    await AuthService().signOut();
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('👤 အကောင့်',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(user?.displayName ?? '—'),
                Text(user?.email ?? '',
                    style: const TextStyle(color: Colors.grey)),
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
                const Text('🔄 Server Sync (Firestore)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          child: ListTile(
            leading: const Icon(Icons.key, color: AppTheme.amber),
            title: const Text('🔑 API Keys'),
            subtitle: const Text('Gemini key များ စီမံခန့်ခွဲခြင်း'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openKeys,
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🔗 ချိတ်ဆက်မှုများ',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('❤️ Health Connect — APK နောက်အဆင့်မှာ ရမယ်',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '🔒 Data အားလုံး Firebase server မှာ သင့်အကောင့်နဲ့ပဲ သိမ်းပါတယ်။ '
              'App version 0.1.0 (stage 1 skeleton)။',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _signingOut ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: Text(_signingOut ? 'ထွက်နေသည်…' : 'Google အကောင့်က ထွက်မယ်'),
        ),
      ],
    );
  }
}
