// Reproduction: fresh-install / clear-data state — EMPTY DB, no profile.
// The 4 reported-blank tabs should show "Profile မရှိသေးပါ", not a blank
// white body. If they render blank here, that is the bug.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/screens/tabs/home_tab.dart';
import 'package:healthassistant/screens/tabs/meds_tab.dart';
import 'package:healthassistant/screens/tabs/progress_tab.dart';
import 'package:healthassistant/screens/tabs/remind_tab.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> seedEmptyDb() async {
  SharedPreferences.setMockInitialValues({});
  await LocalStore().resetDb();
  await LocalStore().load();
}

void main() {
  testWidgets('HomeTab with NO profile shows the no-profile message',
      (tester) async {
    await seedEmptyDb();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeTab())));
    await tester.pumpAndSettle();
    expect(find.text('Profile မရှိသေးပါ'), findsOneWidget);
  });

  testWidgets('ProgressTab with NO profile shows the no-profile message',
      (tester) async {
    await seedEmptyDb();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProgressTab())));
    await tester.pumpAndSettle();
    expect(find.text('Profile မရှိသေးပါ'), findsOneWidget);
  });

  testWidgets('MedsTab with NO profile shows the no-profile message',
      (tester) async {
    await seedEmptyDb();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MedsTab())));
    await tester.pumpAndSettle();
    expect(find.text('Profile မရှိသေးပါ'), findsOneWidget);
  });

  testWidgets('RemindTab with NO profile shows the no-profile message',
      (tester) async {
    await seedEmptyDb();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemindTab())));
    await tester.pumpAndSettle();
    expect(find.text('Profile မရှိသေးပါ'), findsOneWidget);
  });
}
