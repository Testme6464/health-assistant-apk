// Regression: the activity line in HomeTab and RemindTab must render
// horizontally (full card width), not squeezed into a vertical stack.
// Root cause: the old Row+Expanded+OutlinedButton layout let the wide
// Burmese button label take ~260px, leaving the text ~55px wide.
// NOTE: the test font renders Burmese much wider than Noto Sans Myanmar,
// so unrelated cards can overflow in the test only — overflow errors are
// ignored here; only the activity line width is asserted.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/screens/tabs/home_tab.dart';
import 'package:healthassistant/screens/tabs/remind_tab.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> seedProfile() async {
  SharedPreferences.setMockInitialValues({
    'healthassistant_db_v1': jsonEncode({
      'version': 1,
      'activeProfileId': 'p1',
      'profiles': [
        {
          'id': 'p1',
          'name': 'May',
          'age': '27',
          'gender': 'female',
          'height': '154',
          'weight': '82',
          'bloodType': 'B+',
          'conditions': [],
          'familyHistory': [],
          'allergies': [],
          'goal': 'lose',
          'periodEnabled': false,
          'updatedAt': 1790000000000,
        }
      ],
      'meds': [],
      'medLog': {},
      'foodLog': [],
      'waterLog': {},
      'sleepLog': [],
      'activityLog': [],
      'weightLog': [],
      'symptoms': [],
      'emergencyContacts': [],
      'periodLog': [],
      'mealPlans': [],
      'plans': {},
      'reminders': {},
      'settings': {'waterTargetMl': 2000},
    }),
  });
  await LocalStore().load();
}

void setPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(395 * 2.75, 800 * 2.75);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pump while swallowing RenderFlex overflow errors (test-font artifacts).
Future<void> pumpIgnoringOverflow(
    WidgetTester tester, Widget widget) async {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('HomeTab activity line is full width at phone size',
      (tester) async {
    await seedProfile();
    setPhoneSize(tester);
    await pumpIgnoringOverflow(
        tester, const MaterialApp(home: Scaffold(body: HomeTab())));
    final rich = find.byWidgetPredicate((w) =>
        w is RichText && w.text.toPlainText().contains('ဒီနေ့ ခြေလှမ်း'));
    expect(rich, findsOneWidget);
    final size = tester.getSize(rich);
    // Full card width (~323px) and a short height (1-2 lines), not a
    // 55px-wide vertical stack.
    expect(size.width, greaterThan(200));
    expect(size.height, lessThan(60));
  });

  testWidgets('RemindTab activity line is full width at phone size',
      (tester) async {
    await seedProfile();
    // Tall viewport so the whole ListView (incl. the activity card below
    // the fold) is built at once.
    tester.view.physicalSize = const Size(395 * 2.75, 3000 * 2.75);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpIgnoringOverflow(
        tester, const MaterialApp(home: Scaffold(body: RemindTab())));
    final txt = find.byWidgetPredicate((w) =>
        w is Text &&
        w.data != null &&
        w.data!.contains('ခြေလှမ်း:'));
    expect(txt, findsOneWidget);
    final size = tester.getSize(txt);
    expect(size.width, greaterThan(200));
    expect(size.height, lessThan(60));
  });
}
