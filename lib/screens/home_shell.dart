import 'package:flutter/material.dart';

import '../services/sync_service.dart';
import 'keys_screen.dart';
import 'tabs/tab_placeholders.dart';

/// The 12-tab shell — same order as the web app, same icons and labels.
/// Bottom bar scrolls horizontally (12 tabs do not fit one screen width),
/// mirroring the web app's tab bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class TabDef {
  const TabDef(this.id, this.icon, this.label, this.builder);
  final String id;
  final String icon;
  final String label;
  final Widget Function() builder;
}

const List<TabDef> tabDefs = [
  TabDef('home', '🏠', 'ပင်မ', HomeTab.new),
  TabDef('food', '🍚', 'အစားအသောက်', FoodTab.new),
  TabDef('progress', '📊', 'တိုးတက်မှု', ProgressTab.new),
  TabDef('meds', '💊', 'ဆေးဝါးများ', MedsTab.new),
  TabDef('plan', '🗓️', 'အစီအစဉ်', PlanTab.new),
  TabDef('period', '🩸', 'ရာသီစက်ဝန်း', PeriodTab.new),
  TabDef('symptom', '📝', 'လက္ခဏာ', SymptomTab.new),
  TabDef('remind', '⏰', 'သတိပေးချက်များ', RemindTab.new),
  TabDef('profile', '👤', 'ကျန်းမာရေးဖိုင်', ProfileTab.new),
  TabDef('report', '🖨️', 'အစီရင်ခံစာ', ReportTab.new),
  TabDef('emergency', '🚨', 'အရေးပေါ်', EmergencyTab.new),
  TabDef('settings', '⚙️', 'ဆက်တင်', SettingsTab.new),
];

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _sync = SyncService();

  @override
  void initState() {
    super.initState();
    _sync.start();
  }

  void _openKeys() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KeysScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = tabDefs[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('${tab.icon} ${tab.label}'),
        actions: [
          // Sync status dot: blue = synced, amber = pending/error.
          ValueListenableBuilder<SyncStatus>(
            valueListenable: _sync.status,
            builder: (context, s, _) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: s.labelMm,
                child: Icon(
                  s.state == SyncState.synced
                      ? Icons.cloud_done
                      : s.state == SyncState.syncing
                          ? Icons.cloud_upload
                          : Icons.cloud_off,
                  color: s.state == SyncState.synced
                      ? Colors.white
                      : Colors.amber.shade200,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'API Keys',
            onPressed: _openKeys,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [for (final t in tabDefs) t.builder()],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                for (var i = 0; i < tabDefs.length; i++)
                  _TabButton(
                    tab: tabDefs[i],
                    selected: i == _index,
                    onTap: () => setState(() => _index = i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final TabDef tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7F1FB) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tab.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 2),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? const Color(0xFF174A75)
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
