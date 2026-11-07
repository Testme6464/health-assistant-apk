// Reproduction test for the blank-tab report with RICH realistic data
// (mirrors the phone's imported web data: profile May, meds with times,
// weight log, activity log, food log, sleep log, meal plans).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/screens/tabs/home_tab.dart';
import 'package:healthassistant/screens/tabs/meds_tab.dart';
import 'package:healthassistant/screens/tabs/progress_tab.dart';
import 'package:healthassistant/screens/tabs/remind_tab.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> richDb() {
  const t = '2026-11-06';
  return {
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
    'meds': [
      {
        'id': 'm1',
        'profileId': 'p1',
        'name': 'Vitamin D',
        'dosage': '1 tablet',
        'times': ['08:00', '20:00'],
        'reason': '',
        'supplyDays': 30,
        'supplyStartDate': '2026-11-01',
        'updatedAt': 1790000000000,
      }
    ],
    'medLog': {t: {'m1@08:00': 'taken'}},
    'foodLog': [
      {
        'id': 'f1',
        'profileId': 'p1',
        'date': t,
        'time': '08:00',
        'name': 'Rice',
        'kcal': 200,
        'amount': '1 plate',
        'source': 'text',
        'updatedAt': 1790000000000,
      }
    ],
    'waterLog': {t: 500},
    'sleepLog': [
      {
        'id': 's1',
        'profileId': 'p1',
        'date': t,
        'bedtime': '22:30',
        'wakeTime': '06:30',
        'quality': 4,
        'nightmare': false,
        'updatedAt': 1790000000000,
      }
    ],
    'activityLog': [
      {
        'id': 'a1',
        'profileId': 'p1',
        'date': t,
        'steps': 5000,
        'minutes': 30,
        'exerciseType': 2,
        'stepsKcal': 100,
        'exKcal': 50,
        'kcal': 150,
        'source': 'manual',
        'updatedAt': 1790000000000,
      }
    ],
    'weightLog': [
      {
        'id': 'w1',
        'profileId': 'p1',
        'date': '2026-11-05',
        'weight': 82.5,
        'waist': '32',
        'updatedAt': 1790000000000,
      },
      {
        'id': 'w2',
        'profileId': 'p1',
        'date': t,
        'weight': 82.0,
        'waist': '32',
        'updatedAt': 1790000000000,
      }
    ],
    'symptoms': [],
    'emergencyContacts': [],
    'periodLog': [],
    'mealPlans': [
      {
        'id': 'mp1',
        'profileId': 'p1',
        'date': t,
        'time': '12:00',
        'what': 'Lunch',
        'updatedAt': 1790000000000,
      }
    ],
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
}

Future<void> seedRichDb() async {
  SharedPreferences.setMockInitialValues({
    'healthassistant_db_v1': jsonEncode(richDb()),
  });
  await LocalStore().load();
}

void main() {
  testWidgets('HomeTab renders with rich data', (tester) async {
    await seedRichDb();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ဒီနေ့ အကျဉ်းချုပ်'), findsOneWidget);
  });

  testWidgets('ProgressTab renders with rich data', (tester) async {
    await seedRichDb();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProgressTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ကိုယ်အလေးချိန် မှတ်တမ်း'), findsOneWidget);
  });

  testWidgets('MedsTab renders with rich data', (tester) async {
    await seedRichDb();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MedsTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ဒီနေ့ သောက်ရမည့်ဆေးများ'), findsOneWidget);
  });

  testWidgets('RemindTab renders with rich data', (tester) async {
    await seedRichDb();
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemindTab())));
    await tester.pumpAndSettle();
    expect(find.textContaining('သတိပေးချက် ဆက်တင်များ'), findsOneWidget);
  });
}
