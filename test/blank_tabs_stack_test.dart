// Reproduction: pump the tabs inside an IndexedStack exactly like
// HomeShell does (all tabs alive at once, switch index), with the rich
// realistic DB, and check the 4 reported-blank tabs actually paint.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/screens/tabs/food_tab.dart';
import 'package:healthassistant/screens/tabs/home_tab.dart';
import 'package:healthassistant/screens/tabs/meds_tab.dart';
import 'package:healthassistant/screens/tabs/profile_tab.dart';
import 'package:healthassistant/screens/tabs/progress_tab.dart';
import 'package:healthassistant/screens/tabs/remind_tab.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'blank_tabs_rich_test.dart' show richDb;

class StackHarness extends StatefulWidget {
  const StackHarness({super.key});
  @override
  State<StackHarness> createState() => _StackHarnessState();
}

class _StackHarnessState extends State<StackHarness> {
  int index = 0;
  final tabs = const <Widget>[
    HomeTab(),
    FoodTab(),
    ProgressTab(),
    MedsTab(),
    RemindTab(),
    ProfileTab(),
  ];
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: IndexedStack(index: index, children: tabs),
        bottomNavigationBar: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              TextButton(
                onPressed: () => setState(() => index = i),
                child: Text('tab$i'),
              ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('IndexedStack: all 6 tabs paint when switched to',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'healthassistant_db_v1': jsonEncode(richDb()),
    });
    await LocalStore().load();
    await tester.pumpWidget(const StackHarness());
    await tester.pumpAndSettle();

    // Home (index 0)
    expect(find.textContaining('ဒီနေ့ အကျဉ်းချုပ်'), findsOneWidget);
    // Food (index 1)
    await tester.tap(find.text('tab1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ဒီနေ့ စားသုံးမှု'), findsOneWidget);
    // Progress (index 2)
    await tester.tap(find.text('tab2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ကိုယ်အလေးချိန် မှတ်တမ်း'), findsOneWidget);
    // Meds (index 3)
    await tester.tap(find.text('tab3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ဒီနေ့ သောက်ရမည့်ဆေးများ'), findsOneWidget);
    // Remind (index 4)
    await tester.tap(find.text('tab4'));
    await tester.pumpAndSettle();
    expect(find.textContaining('သတိပေးချက် ဆက်တင်များ'), findsOneWidget);
    // Profile (index 5)
    await tester.tap(find.text('tab5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('May'), findsWidgets);
    // Back to Home (index 0) — still paints after switching away and back.
    await tester.tap(find.text('tab0'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ဒီနေ့ အကျဉ်းချုပ်'), findsOneWidget);
  });
}
