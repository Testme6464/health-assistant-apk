import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/data/static_data.dart';
import 'package:healthassistant/models/health_data.dart';

void main() {
  test('static data counts match the web app', () {
    expect(foodDb.length, 160);
    expect(drugInteractions.length, 30);
    expect(commonSymptoms.length, 18);
    expect(exerciseBurn.length, 10);
  });

  test('BMI matches the web app formula', () {
    final bmi = calcBmi(heightCm: 160, weightKg: 81);
    expect(bmi, closeTo(31.64, 0.01));
    expect(bmiLabel(bmi), 'အလွန်ဝသည်');
    expect(bmiLabel(20.0), 'ပုံမှန်');
    expect(bmiLabel(17.0), 'ပိန်လွန်းသည်');
    expect(calcBmi(heightCm: null, weightKg: 81), isNull);
  });

  test('calorie target matches the web app (81kg, 160cm, 27y, male)', () {
    // BMR = 10*81 + 6.25*160 - 5*27 + 5 = 1680; TDEE = 1680*1.375 = 2310.
    expect(
      calorieTargetFor(
        weightKg: 81, heightCm: 160, age: 27, female: false, goal: 'maintain'),
      2300,
    );
    expect(
      calorieTargetFor(
        weightKg: 81, heightCm: 160, age: 27, female: false, goal: 'lose'),
      1800, // 2310 - 500 = 1810 -> 1800
    );
    expect(
      calorieTargetFor(
        weightKg: 81, heightCm: 160, age: 27, female: false, goal: 'gain'),
      2600, // 2310 + 300 = 2610 -> 2600
    );
  });

  test('activity kcal matches the web app check', () {
    // 5000 steps + 30 min fast walk @81kg = 231 + 174 = 405 kcal.
    final k = activityKcal(
      steps: 5000, exerciseType: 2, minutes: 30, weightKg: 81);
    expect(k.stepsKcal, 231);
    expect(k.exKcal, 174);
    expect(k.total, 405);
    // 30 min walk @81kg = 142 kcal (web check).
    expect(burnKcal(3.5, 81, 30), 142);
    // 30 min run @81kg = 397 kcal (web check).
    expect(burnKcal(9.8, 81, 30), 397);
  });

  test('profile model round-trips JSON', () {
    final p = HealthProfile(
      id: 'p1',
      name: 'Kio',
      age: 27,
      gender: 'male',
      heightCm: 160,
      weightKg: 81,
      goal: 'gain',
    );
    final back = HealthProfile.fromJson(p.toJson());
    expect(back.name, 'Kio');
    expect(back.bmi, closeTo(31.64, 0.01));
    expect(back.calorieTarget(), 2600);
    expect(goalLabels[back.goal], 'တိုးရန်');
  });
}
