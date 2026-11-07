// Activity sessions accumulate: logging a second exercise in the same
// day ADDS to the running total (steps/minutes/kcal) instead of
// replacing it. Regression for the user's report that only the latest
// session showed and the total never appeared.
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/screens/tabs/activity_modal.dart';

void main() {
  test('first session creates a new record', () {
    final rec = mergeActivitySession(
      existing: null,
      profileId: 'p1',
      date: '2026-11-07',
      steps: 5000,
      minutes: 30,
      exerciseType: 1,
      weightKg: 82,
    );
    expect(rec['steps'], 5000);
    expect(rec['minutes'], 30);
    expect(rec['exerciseType'], 1);
    expect(rec['kcal'], greaterThan(0));
    expect(rec['source'], 'manual');
  });

  test('second session adds to the running total', () {
    final first = mergeActivitySession(
      existing: null,
      profileId: 'p1',
      date: '2026-11-07',
      steps: 5000,
      minutes: 30,
      exerciseType: 1, // walk
      weightKg: 82,
    );
    final second = mergeActivitySession(
      existing: first,
      profileId: 'p1',
      date: '2026-11-07',
      steps: 2000,
      minutes: 20,
      exerciseType: 3, // run
      weightKg: 82,
    );
    // Totals accumulate.
    expect(second['steps'], 7000);
    expect(second['minutes'], 50);
    // Total kcal = first session kcal + second session kcal (standalone).
    final standaloneSecond = mergeActivitySession(
      existing: null,
      profileId: 'p1',
      date: '2026-11-07',
      steps: 2000,
      minutes: 20,
      exerciseType: 3,
      weightKg: 82,
    );
    expect(second['kcal'],
        (first['kcal'] as int) + (standaloneSecond['kcal'] as int));
    expect(second['kcal'], greaterThan(first['kcal'] as int));
    // The longer session (walk, 30 min) keeps its exercise type.
    expect(second['exerciseType'], 1);
  });

  test('a longer second session takes over the exercise type', () {
    final first = mergeActivitySession(
      existing: null,
      profileId: 'p1',
      date: '2026-11-07',
      steps: 1000,
      minutes: 10,
      exerciseType: 1,
      weightKg: 82,
    );
    final second = mergeActivitySession(
      existing: first,
      profileId: 'p1',
      date: '2026-11-07',
      steps: 0,
      minutes: 40,
      exerciseType: 3,
      weightKg: 82,
    );
    expect(second['minutes'], 50);
    expect(second['exerciseType'], 3);
  });
}
