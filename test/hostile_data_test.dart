// Hostile-data probe for the blank-tab report (2026-11-06):
// Home / Progress / Meds / Reminders render a blank white body on the
// phone while Food / Profile / Symptom / Period / Plan render fine, and
// the existing repro/rich/stack tests (clean or invented-rich data) all
// pass. So the trigger must be a REAL-DATA shape the invented data did
// not cover. Each variant below seeds one hostile shape on top of the
// May-profile base taken from the phone screenshots (age '', female,
// 154/82, goal lose, B+, periodEnabled false) and pumps each of the 4
// tabs, recording whether the tab's header text paints or the build
// throws. Run: flutter test test/hostile_data_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/screens/tabs/home_tab.dart';
import 'package:healthassistant/screens/tabs/meds_tab.dart';
import 'package:healthassistant/screens/tabs/progress_tab.dart';
import 'package:healthassistant/screens/tabs/remind_tab.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _t = '2026-11-06';

Map<String, dynamic> mayBase() {
  return {
    'version': 1,
    'activeProfileId': 'p1',
    'profiles': [
      {
        'id': 'p1',
        'name': 'May',
        'age': '',
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
      'calorieTarget': 1500,
      'waterTargetMl': 2000,
    },
  };
}

Map<String, dynamic> med({
  Object? times = const ['08:00', '20:00'],
  Object? supplyDays = 30,
  Object? supplyStartDate = '2026-11-01',
}) =>
    {
      'id': 'm1',
      'profileId': 'p1',
      'name': 'Vitamin D',
      'dosage': '1 tablet',
      'times': times,
      'reason': '',
      'supplyDays': supplyDays,
      'supplyStartDate': supplyStartDate,
      'updatedAt': 1790000000000,
    };

/// Variants: name -> mutator applied to a fresh May base DB.
final Map<String, void Function(Map<String, dynamic>)> variants = {
  'base-may-empty': (_) {},
  'med-times-string': (db) {
    db['meds'] = [med(times: '08:00, 20:00')];
  },
  'med-times-missing': (db) {
    final m = med();
    m.remove('times');
    db['meds'] = [m];
  },
  'med-times-int-entries': (db) {
    db['meds'] = [med(times: [800, 2000])];
  },
  'medLog-day-is-string': (db) {
    db['meds'] = [med()];
    db['medLog'] = {_t: 'taken'};
  },
  'medLog-value-is-bool': (db) {
    db['meds'] = [med()];
    db['medLog'] = {
      _t: {'m1@08:00': true}
    };
  },
  'med-supplyStart-number': (db) {
    db['meds'] = [med(supplyStartDate: 20261101)];
  },
  'med-supplyStart-empty': (db) {
    db['meds'] = [med(supplyStartDate: '')];
  },
  'med-supplyDays-string-words': (db) {
    db['meds'] = [med(supplyDays: '30 days')];
  },
  'weightLog-date-null': (db) {
    db['weightLog'] = [
      {'id': 'w1', 'profileId': 'p1', 'date': null, 'weight': 82.0}
    ];
  },
  'weightLog-date-int': (db) {
    db['weightLog'] = [
      {'id': 'w1', 'profileId': 'p1', 'date': 20261105, 'weight': 82.0}
    ];
  },
  'weightLog-weight-words': (db) {
    db['weightLog'] = [
      {'id': 'w1', 'profileId': 'p1', 'date': '2026-11-05', 'weight': '82kg'}
    ];
  },
  'sleepLog-date-null': (db) {
    db['sleepLog'] = [
      {
        'id': 's1',
        'profileId': 'p1',
        'date': null,
        'bedtime': '22:30',
        'wakeTime': '06:30',
        'quality': 4,
        'nightmare': false,
      }
    ];
  },
  'sleepLog-quality-6': (db) {
    db['sleepLog'] = [
      {
        'id': 's1',
        'profileId': 'p1',
        'date': _t,
        'bedtime': '22:30',
        'wakeTime': '06:30',
        'quality': 6,
        'nightmare': false,
      }
    ];
  },
  'sleepLog-bedtime-empty': (db) {
    db['sleepLog'] = [
      {
        'id': 's1',
        'profileId': 'p1',
        'date': _t,
        'bedtime': '',
        'wakeTime': '06:30',
        'quality': 4,
        'nightmare': false,
      }
    ];
  },
  'sleepLog-quality-string': (db) {
    db['sleepLog'] = [
      {
        'id': 's1',
        'profileId': 'p1',
        'date': _t,
        'bedtime': '22:30',
        'wakeTime': '06:30',
        'quality': '4',
        'nightmare': false,
      }
    ];
  },
  'mealPlan-date-null': (db) {
    db['mealPlans'] = [
      {'id': 'mp1', 'profileId': 'p1', 'date': null, 'time': '12:00', 'what': 'Lunch'}
    ];
  },
  'mealPlan-time-null': (db) {
    db['mealPlans'] = [
      {'id': 'mp1', 'profileId': 'p1', 'date': _t, 'time': null, 'what': 'Lunch'}
    ];
  },
  'reminders-bools-as-strings': (db) {
    db['reminders'] = {
      'waterEnabled': 'true',
      'waterInterval': '120',
      'waterStart': '08:00',
      'waterEnd': '21:00',
      'medEnabled': 'true',
      'sleepEnabled': 'true',
      'bedtime': '22:30',
    };
  },
  'reminders-bedtime-empty': (db) {
    (db['reminders'] as Map)['bedtime'] = '';
  },
  'reminders-waterStart-empty': (db) {
    (db['reminders'] as Map)['waterStart'] = '';
    (db['reminders'] as Map)['waterEnd'] = '';
  },
  'settings-numbers-as-strings': (db) {
    db['settings'] = {
      'geminiModel': 'gemini-3.8-flash',
      'calorieTargetMode': 'manual',
      'calorieTarget': '1500',
      'waterTargetMl': '2000',
    };
  },
  'waterLog-value-string': (db) {
    db['waterLog'] = {_t: '500'};
  },
  'activity-steps-string': (db) {
    db['activityLog'] = [
      {
        'id': 'a1',
        'profileId': 'p1',
        'date': _t,
        'steps': '5000',
        'minutes': '30',
        'exerciseType': '2',
      }
    ];
  },
  'activity-exerciseType-out-of-range': (db) {
    db['activityLog'] = [
      {
        'id': 'a1',
        'profileId': 'p1',
        'date': _t,
        'steps': 5000,
        'minutes': 30,
        'exerciseType': 99,
      }
    ];
  },
  'sleepLog-two-one-date-null': (db) {
    db['sleepLog'] = [
      {
        'id': 's1',
        'profileId': 'p1',
        'date': _t,
        'bedtime': '22:30',
        'wakeTime': '06:30',
        'quality': 4,
        'nightmare': false,
      },
      {
        'id': 's2',
        'profileId': 'p1',
        'date': null,
        'bedtime': '22:30',
        'wakeTime': '06:30',
        'quality': 3,
        'nightmare': false,
      },
    ];
  },
  'weightLog-two-one-date-null': (db) {
    db['weightLog'] = [
      {'id': 'w1', 'profileId': 'p1', 'date': '2026-11-05', 'weight': 82.5},
      {'id': 'w2', 'profileId': 'p1', 'date': null, 'weight': 82.0},
    ];
  },
  'mealPlans-two-one-time-null': (db) {
    db['mealPlans'] = [
      {'id': 'mp1', 'profileId': 'p1', 'date': _t, 'time': '12:00', 'what': 'Lunch'},
      {'id': 'mp2', 'profileId': 'p1', 'date': _t, 'time': null, 'what': 'Dinner'},
    ];
  },
  'meds-two-one-times-string': (db) {
    db['meds'] = [med(), med(times: '08:00')];
  },
  'food-kcal-words': (db) {
    db['foodLog'] = [
      {
        'id': 'f1',
        'profileId': 'p1',
        'date': _t,
        'time': '08:00',
        'name': 'Rice',
        'kcal': '200 kcal',
      }
    ];
  },
};

final _tabHeaders = <String, Widget Function()>{
  'Home': () => const HomeTab(),
  'Progress': () => const ProgressTab(),
  'Meds': () => const MedsTab(),
  'Remind': () => const RemindTab(),
};

final _headerText = {
  'Home': 'ဒီနေ့ အကျဉ်းချုပ်',
  'Progress': 'ကိုယ်အလေးချိန် မှတ်တမ်း',
  'Meds': 'ဒီနေ့ သောက်ရမည့်ဆေးများ',
  'Remind': 'သတိပေးချက် ဆက်တင်များ',
};

void seedDb(Map<String, dynamic> db) {
  // LocalStore is a singleton whose _loaded flag stays true after the
  // first load; mutate the live map directly (JSON round-trip first so
  // the shapes match what SharedPreferences/Firestore decoding yields).
  final decoded =
      jsonDecode(jsonEncode(db)) as Map<String, dynamic>;
  final store = LocalStore();
  store.db
    ..clear()
    ..addAll(decoded);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore().load();
  });

  for (final entry in variants.entries) {
    group(entry.key, () {
      for (final tab in _tabHeaders.entries) {
        testWidgets('${tab.key} renders', (tester) async {
          final db = mayBase();
          entry.value(db);
          seedDb(db);
          await tester.pumpWidget(
            MaterialApp(home: Scaffold(body: tab.value())),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining(_headerText[tab.key]!),
            findsOneWidget,
            reason: '${entry.key} broke ${tab.key}',
          );
        });
      }
    });
  }
}
