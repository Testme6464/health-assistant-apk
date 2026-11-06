// String-number tolerance: the web app stores numeric fields as STRINGS
// (profile age/height/weight are '' by default and saved from input
// .value; food kcal / weight-log weight are strings too). The APK must
// parse those without throwing "type 'String' is not a subtype of type
// 'num?' in type cast" — the red-screen crash seen after importing the
// web app's JSON export.
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/models/health_data.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore().resetDb();
    await LocalStore().load();
  });

  test('toNum parses numbers, numeric strings and empty strings safely', () {
    expect(toNum(42), 42);
    expect(toNum(81.1), 81.1);
    expect(toNum('27'), 27);
    expect(toNum('81.1'), 81.1);
    expect(toNum(' 160 '), 160);
    expect(toNum(''), isNull);
    expect(toNum(null), isNull);
    expect(toNum('abc'), isNull);
    expect(toInt('27'), 27);
    expect(toInt('81.1'), 81);
    expect(toInt(''), isNull);
    expect(toDouble('81.1'), 81.1);
    expect(toDouble(''), isNull);
  });

  test('HealthProfile.fromJson accepts string age/height/weight', () {
    final p = HealthProfile.fromJson({
      'id': 'p1',
      'name': 'Test',
      'age': '27',
      'gender': 'male',
      'height': '160',
      'weight': '81.1',
      'goal': 'gain',
    });
    expect(p.age, 27);
    expect(p.heightCm, 160.0);
    expect(p.weightKg, 81.1);
    expect(p.bmi, closeTo(31.7, 0.1));
  });

  test('HealthProfile.fromJson accepts empty-string numbers (web default)',
      () {
    final p = HealthProfile.fromJson({
      'id': 'p1',
      'name': 'ကျွန်ုပ်',
      'age': '',
      'gender': '',
      'height': '',
      'weight': '',
      'goal': 'maintain',
    });
    expect(p.age, isNull);
    expect(p.heightCm, isNull);
    expect(p.weightKg, isNull);
    expect(p.bmi, isNull);
  });

  test('FoodEntry.fromJson accepts string kcal and string updatedAt', () {
    final f = FoodEntry.fromJson({
      'id': 'f1',
      'profileId': 'p1',
      'date': '2026-11-06',
      'time': '08:00',
      'name': 'ထမင်း',
      'kcal': '250',
      'updatedAt': '1762400000000',
    });
    expect(f.kcal, 250);
    expect(f.updatedAt, 1762400000000);
  });

  test('ActivityEntry and Med accept string numbers', () {
    final a = ActivityEntry.fromJson({
      'id': 'a1',
      'profileId': 'p1',
      'date': '2026-11-06',
      'steps': '5000',
      'minutes': '30',
      'exerciseType': '3',
      'kcal': '142',
    });
    expect(a.steps, 5000);
    expect(a.minutes, 30);
    expect(a.exerciseType, 3);
    expect(a.kcal, 142);

    final m = Med.fromJson({
      'id': 'm1',
      'profileId': 'p1',
      'name': 'ဆေး',
      'supplyDays': '30',
    });
    expect(m.supplyDays, 30);
  });

  test('importWebExport tolerates string numbers end to end', () async {
    final local = LocalStore();
    await local.importWebExport({
      'activeProfileId': 'p1',
      'profiles': [
        {
          'id': 'p1',
          'name': 'Test',
          'age': '27',
          'gender': 'male',
          'height': '160',
          'weight': '81.1',
          'goal': 'gain',
        },
      ],
      'foodLog': [
        {
          'id': 'f1',
          'profileId': 'p1',
          'date': '2026-11-06',
          'time': '08:00',
          'name': 'ထမင်း',
          'kcal': '250',
        },
      ],
      'weightLog': [
        {'id': 'w1', 'profileId': 'p1', 'date': '2026-11-06', 'weight': '81.1'},
      ],
    });
    // The imported raw maps must parse through the models without throwing.
    final p = HealthProfile.fromJson(local.list('profiles').first);
    expect(p.age, 27);
    expect(p.weightKg, 81.1);
    final f = FoodEntry.fromJson(local.list('foodLog').first);
    expect(f.kcal, 250);
    expect(
      toDouble(local.list('weightLog').first['weight']),
      81.1,
    );
  });
}
