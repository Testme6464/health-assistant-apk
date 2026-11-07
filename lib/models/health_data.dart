// Health data models — mirrors the web app's localStorage schema
// (~/workspace/health-app/app.js defaultDB), so the web JSON export can be
// imported into the APK and the Firestore documents use the same fields.
//
// Every record carries [updatedAt] (epoch ms) and [deleted] so the sync
// layer can merge local + server changes offline-first.
library;

String newId() =>
    'id_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';

String todayStr() {
  final n = DateTime.now();
  final m = n.month.toString().padLeft(2, '0');
  final d = n.day.toString().padLeft(2, '0');
  return '${n.year}-$m-$d';
}

/// Tolerant number parsing for JSON from the web app / Firestore.
///
/// The web app stores numeric fields as STRINGS (profile age/height/
/// weight come from input .value; food kcal and weight-log weight are
/// strings too), so a strict `(v as num?)` cast throws
/// "type 'String' is not a subtype of type 'num?' in type cast" and
/// red-screens the tab. These helpers accept num, numeric String
/// (trimmed, '' -> null) or null, and never throw.
num? toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

int? toInt(dynamic v) => toNum(v)?.toInt();

double? toDouble(dynamic v) => toNum(v)?.toDouble();

/// Tolerant string coercion for JSON from the web app / Firestore.
///
/// The same class of bug as the string-number crash (a14ea84): a field the
/// code casts with `as String` / `as List` / `as bool` can arrive in a
/// different shape (a med's `times` as a comma string, a `medLog` day as a
/// string, a reminder flag as the string "true", a log date as null or a
/// number) and a strict cast throws, blanking the whole tab. These
/// helpers never throw; corrupt entries degrade to empty/default instead.
String strVal(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  return '$v';
}

/// List of strings from a List, a comma-separated String, or anything else.
List<String> strList(dynamic v) {
  if (v is List) return v.map((e) => '$e').toList();
  if (v is String) {
    return v
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return [];
}

/// Boolean from a bool, a "true"/"false"/"1"/"0" String, or a number.
bool toBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }
  if (v is num) return v != 0;
  return fallback;
}

/// Health math — identical formulas to the web app.
double? calcBmi({required double? heightCm, required double? weightKg}) {
  if (heightCm == null || weightKg == null || heightCm <= 0) return null;
  return weightKg / ((heightCm / 100) * (heightCm / 100));
}

String bmiLabel(double? bmi) {
  if (bmi == null) return '—';
  if (bmi < 18.5) return 'ပိန်လွန်းသည်';
  if (bmi < 23) return 'ပုံမှန်';
  if (bmi < 25) return 'အနည်းငယ် ဝသည်';
  if (bmi < 30) return 'ဝသည်';
  return 'အလွန်ဝသည်';
}

/// Daily calorie target (Mifflin-St Jeor BMR x 1.375 light activity).
/// lose -500, gain +300, floor 1200, rounded to 50 — same as the web app.
int calorieTargetFor({
  required double weightKg,
  required double heightCm,
  required int age,
  required bool female,
  required String goal,
  int? manualTarget,
  bool manualMode = false,
}) {
  if (manualMode) return manualTarget ?? 2000;
  var bmr = female
      ? 10 * weightKg + 6.25 * heightCm - 5 * age - 161
      : 10 * weightKg + 6.25 * heightCm - 5 * age + 5;
  var tdee = bmr * 1.375;
  if (goal == 'lose') tdee -= 500;
  if (goal == 'gain') tdee += 300;
  return (tdee / 50).round() * 50 < 1200 ? 1200 : (tdee / 50).round() * 50;
}

const Map<String, String> goalLabels = {
  'lose': 'ကိုယ်အလေးချိန်လျှော့ချရန်',
  'maintain': 'ထိန်းသိမ်းရန်',
  'gain': 'တိုးရန်',
};

/// One health profile (web app: profiles[]).
class HealthProfile {
  HealthProfile({
    required this.id,
    this.name = 'ကျွန်ုပ်',
    this.age,
    this.gender = '',
    this.heightCm,
    this.weightKg,
    this.bloodType = '',
    this.conditions = const [],
    this.familyHistory = const [],
    this.allergies = const [],
    this.goal = 'maintain',
    this.periodEnabled = false,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String name;
  int? age;
  String gender; // '' | 'male' | 'female'
  double? heightCm;
  double? weightKg;
  String bloodType;
  List<String> conditions;
  List<String> familyHistory;
  List<String> allergies;
  String goal; // lose | maintain | gain
  bool periodEnabled;
  int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'gender': gender,
        'height': heightCm,
        'weight': weightKg,
        'bloodType': bloodType,
        'conditions': conditions,
        'familyHistory': familyHistory,
        'allergies': allergies,
        'goal': goal,
        'periodEnabled': periodEnabled,
        'updatedAt': updatedAt,
      };

  factory HealthProfile.fromJson(Map<String, dynamic> j) => HealthProfile(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'ကျွန်ုပ်',
        age: toInt(j['age']),
        gender: (j['gender'] as String?) ?? '',
        heightCm: toDouble(j['height']),
        weightKg: toDouble(j['weight']),
        bloodType: (j['bloodType'] as String?) ?? '',
        conditions:
            (j['conditions'] as List?)?.map((e) => '$e').toList() ?? [],
        familyHistory:
            (j['familyHistory'] as List?)?.map((e) => '$e').toList() ?? [],
        allergies:
            (j['allergies'] as List?)?.map((e) => '$e').toList() ?? [],
        goal: (j['goal'] as String?) ?? 'maintain',
        periodEnabled: (j['periodEnabled'] as bool?) ?? false,
        updatedAt: toInt(j['updatedAt']),
      );

  double? get bmi => calcBmi(heightCm: heightCm, weightKg: weightKg);

  int calorieTarget({int? manualTarget, bool manualMode = false}) =>
      calorieTargetFor(
        weightKg: weightKg ?? 60,
        heightCm: heightCm ?? 160,
        age: age ?? 30,
        female: gender == 'female',
        goal: goal,
        manualTarget: manualTarget,
        manualMode: manualMode,
      );
}

/// One food log entry (web app: foodLog[]).
class FoodEntry {
  FoodEntry({
    required this.id,
    required this.profileId,
    required this.date,
    required this.time,
    required this.name,
    required this.kcal,
    this.amount = '',
    this.source = '',
    this.deleted = false,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String profileId;
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final String name;
  final int kcal;
  final String amount;
  final String source; // '' | 'photo-ai'
  bool deleted;
  int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'date': date,
        'time': time,
        'name': name,
        'kcal': kcal,
        'amount': amount,
        'source': source,
        'deleted': deleted,
        'updatedAt': updatedAt,
      };

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
        id: j['id'] as String,
        profileId: j['profileId'] as String,
        date: j['date'] as String,
        time: (j['time'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        kcal: toInt(j['kcal']) ?? 0,
        amount: (j['amount'] as String?) ?? '',
        source: (j['source'] as String?) ?? '',
        deleted: (j['deleted'] as bool?) ?? false,
        updatedAt: toInt(j['updatedAt']),
      );
}

/// One activity record (web app: activityLog[]).
/// Health Connect-ready fields kept from the web app:
/// steps -> StepsRecord.count, exerciseType -> ExerciseSessionRecord,
/// minutes -> duration, kcal -> ActiveCaloriesBurnedRecord, source.
class ActivityEntry {
  ActivityEntry({
    required this.id,
    required this.profileId,
    required this.date,
    this.steps = 0,
    this.minutes = 0,
    this.exerciseType = 1, // index into exerciseBurn (1 = လမ်းလျှောက်)
    this.stepsKcal = 0,
    this.exKcal = 0,
    this.kcal = 0,
    this.source = 'manual', // 'manual' | 'health-connect'
    this.deleted = false,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String profileId;
  final String date;
  int steps;
  int minutes;
  int exerciseType;
  int stepsKcal;
  int exKcal;
  int kcal;
  String source;
  bool deleted;
  int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'date': date,
        'steps': steps,
        'minutes': minutes,
        'exerciseType': exerciseType,
        'stepsKcal': stepsKcal,
        'exKcal': exKcal,
        'kcal': kcal,
        'source': source,
        'deleted': deleted,
        'updatedAt': updatedAt,
      };

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
        id: j['id'] as String,
        profileId: j['profileId'] as String,
        date: j['date'] as String,
        steps: toInt(j['steps']) ?? 0,
        minutes: toInt(j['minutes']) ?? 0,
        exerciseType: toInt(j['exerciseType']) ?? 1,
        stepsKcal: toInt(j['stepsKcal']) ?? 0,
        exKcal: toInt(j['exKcal']) ?? 0,
        kcal: toInt(j['kcal']) ?? 0,
        source: (j['source'] as String?) ?? 'manual',
        deleted: (j['deleted'] as bool?) ?? false,
        updatedAt: toInt(j['updatedAt']),
      );

  /// Health Connect-shaped view (used by the APK phase later).
  Map<String, dynamic> toHealthConnect() => {
        'steps': {'count': steps, 'source': source},
        'exerciseSession': {
          'exerciseType': exerciseType,
          'durationMinutes': minutes,
        },
        'activeCaloriesBurned': {'kcal': kcal},
      };
}

/// One medication (web app: meds[]).
class Med {
  Med({
    required this.id,
    required this.profileId,
    required this.name,
    this.dosage = '',
    this.times = const [],
    this.reason = '',
    this.supplyDays,
    this.supplyStartDate = '',
    this.deleted = false,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String profileId;
  final String name;
  final String dosage;
  final List<String> times; // ['08:00', '20:00']
  final String reason;
  final int? supplyDays;
  final String supplyStartDate;
  bool deleted;
  int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'name': name,
        'dosage': dosage,
        'times': times,
        'reason': reason,
        'supplyDays': supplyDays,
        'supplyStartDate': supplyStartDate,
        'deleted': deleted,
        'updatedAt': updatedAt,
      };

  factory Med.fromJson(Map<String, dynamic> j) => Med(
        id: j['id'] as String,
        profileId: j['profileId'] as String,
        name: (j['name'] as String?) ?? '',
        dosage: (j['dosage'] as String?) ?? '',
        times: (j['times'] as List?)?.map((e) => '$e').toList() ?? [],
        reason: (j['reason'] as String?) ?? '',
        supplyDays: toInt(j['supplyDays']),
        supplyStartDate: (j['supplyStartDate'] as String?) ?? '',
        deleted: (j['deleted'] as bool?) ?? false,
        updatedAt: toInt(j['updatedAt']),
      );
}
