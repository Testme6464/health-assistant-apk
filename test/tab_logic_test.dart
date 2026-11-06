import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/data/plan_data.dart';
import 'package:healthassistant/models/health_data.dart';
import 'package:healthassistant/screens/tabs/tab_common.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore().resetDb();
    await LocalStore().load();
  });

  HealthProfile testProfile({int? age, List<String> conditions = const []}) {
    return HealthProfile(
      id: 'p1',
      name: 'Test',
      age: age ?? 27,
      gender: 'male',
      heightCm: 160,
      weightKg: 81,
      goal: 'maintain',
      conditions: conditions,
    );
  }

  test('plan data counts match the web app', () {
    expect(goalMeals.length, 3);
    expect(goalMeals['gain']!.length, 4);
    expect(goalMeals['lose']!.length, 4);
    expect(goalMeals['maintain']!.length, 4);
    expect(goalWorkoutDays['gain']!.length, 7);
    expect(weekTitles.length, 4);
    expect(weekMinFactors, [1, 1.15, 1.3, 1.3]);
    expect(goalBtn['gain'], '💪 ဝိတ်တိုးရန်');
    expect(goalBtn['maintain'], '⚖️ ထိန်းသိမ်းရန်');
    expect(goalBtn['lose'], '🏃 ဝိတ်ချရန်');
    expect(coachTips['morning']!.length, 4);
    expect(goalDietEat['gain']!.length, 34);
    expect(goalDietEat['lose']!.length, 24);
    expect(goalDietEat['maintain']!.length, 27);
    expect(dietAvoidBase.length, 3);
    expect(dietAvoidLoseExtra.length, 9);
  });

  test('workout weeks scale minutes x1/x1.15/x1.3/x1.3', () {
    final weeks = buildWorkoutWeeks('gain');
    expect(weeks.length, 4);
    expect(weeks[0]['week'], 'အပတ် 1');
    expect(weeks[1]['title'], 'အရှိန်မြှင့်ခြင်း');
    // Monday gain: 20 min base -> 20 / 23 / 26 / 26.
    final mon = (weeks[0]['days'] as List)[0] as Map;
    expect(mon['text'], 'ကြွက်သားလေ့ကျင့်ခန်း (squat, push-up) 20 မိနစ်');
    expect(((weeks[1]['days'] as List)[0] as Map)['text'],
        'ကြွက်သားလေ့ကျင့်ခန်း (squat, push-up) 23 မိနစ်');
    expect(((weeks[2]['days'] as List)[0] as Map)['text'],
        'ကြွက်သားလေ့ကျင့်ခန်း (squat, push-up) 26 မိနစ်');
    expect(((weeks[3]['days'] as List)[0] as Map)['text'],
        'ကြွက်သားလေ့ကျင့်ခန်း (squat, push-up) 26 မိနစ်');
    // Sunday gain: rest, 0 min -> no minutes in text.
    expect(((weeks[0]['days'] as List)[6] as Map)['text'], 'အနားယူ');
  });

  test('offline goal plan matches the web format', () {
    final p = testProfile();
    final plan = generateGoalPlan(p, 'gain', '22:30');
    expect(plan['goal'], 'gain');
    expect(plan['ai'], isFalse);
    expect(plan['month'], currentMonthKey());
    expect(plan['calorieTarget'], 2600); // 81kg gain target
    expect((plan['meals'] as List).length, 4);
    expect((plan['workout'] as List).length, 4);
    expect((plan['diet']['eat'] as List).length, 34);
    expect(plan['tip'], goalTips['gain']);
    expect(plan['sleep']['bed'], '22:30');
    expect(plan['sleep']['wake'], '06:00');
    // Lose plan avoids the extra list.
    final lose = generateGoalPlan(p, 'lose', '22:30');
    expect((lose['diet']['avoid'] as List).length, 3 + 9);
    expect(lose['calorieTarget'], 1800);
  });

  test('diabetes swaps breakfast staple and adds diet lines', () {
    final p = testProfile(conditions: ['ဆီးချို']);
    final plan = generateGoalPlan(p, 'gain', '22:30');
    final meals = plan['meals'] as List;
    expect((meals[0]['items'] as List)[0], 'ပဲပြုတ်ထမင်း ၁ ပန်းကန်');
    expect((plan['diet']['eat'] as List).contains('အချိုနည်းသော အစားအစာများ'),
        isTrue);
    expect((plan['diet']['avoid'] as List).contains('သကြား၊ မုန့်ချို'),
        isTrue);
  });

  test('validPlan rejects old-format plans without a goal', () {
    final local = LocalStore();
    local.db['plans'] = {
      'p1': {'month': currentMonthKey(), 'meals': []},
    };
    expect(validPlan(local, 'p1', currentMonthKey()), isNull);
    local.db['plans'] = {
      'p1': {'month': '2000-01', 'goal': 'gain'},
    };
    expect(validPlan(local, 'p1', currentMonthKey()), isNull);
    local.db['plans'] = {
      'p1': {'month': currentMonthKey(), 'goal': 'lose'},
    };
    expect(validPlan(local, 'p1', currentMonthKey()), isNotNull);
  });

  test('todayGuide returns today\'s week/day and meals', () {
    final plan = generateGoalPlan(testProfile(), 'maintain', '22:30');
    final guide = todayGuide(plan);
    expect(guide, isNotNull);
    expect(guide!.calorieTarget, 2300);
    expect(guide.meals.length, 4);
    expect(guide.dayText, isNotNull);
  });

  test('food box splits on em dash', () {
    final b1 = foodBoxParts('အသားဟင်း — ကြက်သားဟင်း / ငါးဟင်း');
    expect(b1.label, 'အသားဟင်း');
    expect(b1.body, 'ကြက်သားဟင်း / ငါးဟင်း');
    final b2 = foodBoxParts('ထမင်း ၁ ပန်းကန်');
    expect(b2.label, isNull);
    expect(b2.body, 'ထမင်း ၁ ပန်းကန်');
  });

  test('period summary matches the web app (30-day cycle)', () {
    final local = LocalStore();
    local.db['periodLog'] = [
      {'id': 'a', 'profileId': 'p1', 'start': '2026-09-10'},
      {'id': 'b', 'profileId': 'p1', 'start': '2026-10-10'},
    ];
    final s = calcPeriodSummary(local, 'p1');
    expect(s.count, 2);
    expect(s.avg, 30);
    expect(s.last, '2026-10-10');
    expect(s.next, '2026-11-09');
    local.db['periodLog'] = [
      {'id': 'a', 'profileId': 'p1', 'start': '2026-10-10'},
    ];
    final s1 = calcPeriodSummary(local, 'p1');
    expect(s1.count, 1);
    expect(s1.avg, isNull);
    expect(calcPeriodSummary(local, 'p2').count, 0);
  });

  test('med supply left counts down to the end date', () {
    final today = todayStr();
    final start = addDaysStr(today, -10);
    expect(medSupplyLeft({'supplyDays': 30, 'supplyStartDate': start}), 20);
    expect(medSupplyLeft({'supplyDays': 5, 'supplyStartDate': start}), -5);
    expect(medSupplyLeft({}), isNull);
  });

  test('sleep duration crosses midnight', () {
    expect(
      sleepDuration({'bedtime': '22:30', 'wakeTime': '06:00'}),
      '7 နာရီ 30 မိနစ်',
    );
    expect(
      sleepDuration({'bedtime': '23:00', 'wakeTime': '07:15'}),
      '8 နာရီ 15 မိနစ်',
    );
    expect(sleepDuration({}), '—');
  });

  test('local interaction check matches the web app', () {
    final found = checkLocalInteractions(['Warfarin 5mg', 'Aspirin 100mg']);
    expect(found.length, 1);
    expect(found[0].entry.level, 'high');
    expect(checkLocalInteractions(['Warfarin']), isEmpty);
    expect(checkLocalInteractions(['Paracetamol', 'Vitamin C']), isEmpty);
  });

  test('AI plan output validation (4 headers)', () {
    expect(planHeaderHits('## 🎯 စားသင့်သော ကယ်လိုရီ\n## 🍽️ စားသောက်ချိန်\n## 🏃 လေ့ကျင့်ခန်း (၄ ပတ်)\n## 📅 တစ်ရက်ချင်းစာ လမ်းညွှန်'), 4);
    expect(
      planOutputOk(
        'ကယ်လိုရီ 2000 kcal\nစားသောက်ချိန် မနက်စာ\nလေ့ကျင့်ခန်း လမ်းလျှောက်\nလမ်းညွှန် ဒီနေ့',
      ),
      isTrue,
    );
    expect(planOutputOk('This is an English response with many words'), isFalse);
    expect(planOutputOk('ကယ်လိုရီ ပဲပါတယ်'), isFalse);
  });

  test('date/time formatters match the web app', () {
    expect(fmtDateMm('2026-11-06'), '6 နိုဝင်ဘာ 2026');
    expect(fmtDateMm('2026-01-05'), '5 ဇန်နဝါရီ 2026');
    expect(fmtTimeMm('07:30'), 'နံနက် 7:30');
    expect(fmtTimeMm('12:30'), 'နေ့လယ် 12:30');
    expect(fmtTimeMm('18:30'), 'ညနေ 6:30');
    expect(fmtTimeMm('22:30'), 'ည 10:30');
    expect(fmtTimeMm('00:15'), 'နံနက် 12:15');
    expect(addDaysStr('2026-10-10', 30), '2026-11-09');
  });

  test('elderly alternatives only from age 40', () {
    expect(showAltFor(testProfile(age: 40)), isTrue);
    expect(showAltFor(testProfile(age: 39)), isFalse);
    expect(showAltFor(null), isFalse);
  });
}
