// Unit tests for the notification scheduling math and sound choice.
//
// These test the pure functions in notification_service.dart — the
// flutter_local_notifications plugin itself cannot run in a unit test,
// so the plugin calls are not covered here; the CI build + a phone test
// cover those.
import 'package:flutter_test/flutter_test.dart';
import 'package:healthassistant/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('waterTimes: 08:00-21:00 every 120 min', () {
    expect(
      waterTimes('08:00', '21:00', 120),
      ['08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00'],
    );
  });

  test('waterTimes: 30-min interval and edge cases', () {
    expect(
      waterTimes('08:00', '09:00', 30),
      ['08:00', '08:30', '09:00'],
    );
    expect(waterTimes('08:00', '21:00', 0), isEmpty);
    expect(waterTimes('08:00', '21:00', -5), isEmpty);
    expect(waterTimes('', '21:00', 120), isEmpty);
    expect(waterTimes('21:00', '08:00', 120), isEmpty);
    expect(waterTimes('25:00', '21:00', 120), isEmpty);
  });

  test('parseHmMinutes accepts valid times only', () {
    expect(parseHmMinutes('08:00'), 480);
    expect(parseHmMinutes('22:30'), 1350);
    expect(parseHmMinutes('0:00'), 0);
    expect(parseHmMinutes('24:00'), isNull);
    expect(parseHmMinutes('08:60'), isNull);
    expect(parseHmMinutes(''), isNull);
    expect(parseHmMinutes('abc'), isNull);
  });

  test('nextOccurrence: future today, else tomorrow', () {
    tz.initializeTimeZones();
    final loc = tz.getLocation('Asia/Bangkok');
    final now = tz.TZDateTime(loc, 2026, 11, 7, 10, 0);
    expect(
      nextOccurrence('12:00', now),
      tz.TZDateTime(loc, 2026, 11, 7, 12, 0),
    );
    // Already passed today -> tomorrow.
    expect(
      nextOccurrence('08:00', now),
      tz.TZDateTime(loc, 2026, 11, 8, 8, 0),
    );
    // Exactly now counts as passed -> tomorrow.
    expect(
      nextOccurrence('10:00', now),
      tz.TZDateTime(loc, 2026, 11, 8, 10, 0),
    );
    expect(nextOccurrence('25:00', now), isNull);
    expect(nextOccurrence('', now), isNull);
  });
}
