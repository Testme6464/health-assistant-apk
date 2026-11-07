// Reproduction test for the blank-tab report (Home / Progress / Meds /
// Reminders show an empty white body on the phone after the string-number
// fix). Pumps each tab with a web-style imported DB (profile with STRING
// age/height/weight, as the web app stores them) and checks the tab's
// static content actually renders.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/screens/tabs/home_tab.dart';
import 'package:healthassistant/screens/tabs/meds_tab.dart';
import 'package:healthassistant/screens/tabs/progress_tab.dart';
import 'package:healthassistant/screens/tabs/remind_tab.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> webStyleDb() => {
      'version': 1,
      'activeProfileId': 'p1',
      'profiles': [
        {
          'id': 'p1',
          'name': 'Kio',
          'age': '27',
          'gender': 'male',
          'height': '160',
          'weight': '81.1',
          'bloodType': 'O',
          'conditions': [],
          'familyHistory': [],
          'allergies': [],
          'goal': 'gain',
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
      'reminders': {
        'waterEnabled': true,
        'waterInterval': 120,
        'waterStart': '08:00',
        'waterEnd': '21:00',
        'medEnabled': true,
        'sleepEnabled': true,
        'bedtime': '22:30',
      },
      'settings': {
        'geminiModel': 'gemini-3.8-flash',
        'calorieTargetMode': 'auto',
        'calorieTarget': 2000,
        'waterTargetMl': 2000,
      },
    };

Future<void> seedWebDb() async {
  SharedPreferences.setMockInitialValues({
    'healthassistant_db_v1': jsonEncode(webStyleDb()),
  });
  // Force the singleton to reload from the mock prefs.
  await LocalStore().load();
}

void main() {
  testWidgets('HomeTab renders its header with a web-imported profile',
      (tester) async {
    await seedWebDb();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ဒီနေ့ အကျဉ်းချုပ်'), findsOneWidget);
  });

  testWidgets('ProgressTab renders its weight card with a web-imported profile',
      (tester) async {
    await seedWebDb();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProgressTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ကိုယ်အလေးချိန် မှတ်တမ်း'), findsOneWidget);
  });

  testWidgets('MedsTab renders its schedule card with a web-imported profile',
      (tester) async {
    await seedWebDb();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MedsTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ဒီနေ့ သောက်ရမည့်ဆေးများ'), findsOneWidget);
  });

  testWidgets('RemindTab renders its settings card with a web-imported profile',
      (tester) async {
    await seedWebDb();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemindTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('သတိပေးချက် ဆက်တင်များ'), findsOneWidget);
  });
}
