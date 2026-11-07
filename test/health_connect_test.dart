// Health Connect workout-type mapping + auto-sync wiring.
//
// - hcWorkoutToExerciseIndex maps Health Connect workout types to the
//   app's exerciseBurn index (same order as hcExerciseType).
// - LocalStore.markDirty must invoke the onDirty callback so SyncService
//   can schedule a debounced auto-sync after any local change.
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:healthassistant/services/health_connect_service.dart';
import 'package:healthassistant/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('HC workout type maps to the right exercise index', () {
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.WALKING),
        1);
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.HIKING),
        2);
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.RUNNING),
        3);
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.BIKING),
        4);
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.SWIMMING),
        5);
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.YOGA),
        8);
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.SOCCER),
        9);
    expect(
        HealthConnectService.hcWorkoutToExerciseIndex(
            HealthWorkoutActivityType.OTHER),
        9);
  });

  test('markDirty invokes the onDirty callback (auto-sync trigger)',
      () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final local = LocalStore();
    local.onDirty = () => calls++;
    await local.markDirty('foodLog');
    expect(calls, 1);
    await local.markDirty('profiles');
    expect(calls, 2);
    local.onDirty = null;
    await local.markDirty('meds');
    expect(calls, 2);
  });
}
