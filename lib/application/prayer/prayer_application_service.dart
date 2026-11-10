import '../../execution/prayer/prayer_times_engine.dart';
import '../../prayer_notifications.dart';

/// Application bridge for prayer calculations and notification scheduling.
class PrayerApplicationService {
  PrayerApplicationService({
    PrayerTimesEngine? engine,
  }) : _engine = engine ?? PrayerTimesEngine();

  final PrayerTimesEngine _engine;

  CalculationParameters calculationParameters({
    required int method,
    required int asrSchool,
  }) =>
      _engine.parameters(method: method, asrSchool: asrSchool);

  Map<String, DateTime> calculateTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    required int method,
    required int asrSchool,
    required Map<String, int> adjustments,
  }) =>
      _engine.calculate(
        latitude: latitude,
        longitude: longitude,
        date: date,
        method: method,
        asrSchool: asrSchool,
        adjustments: adjustments,
      );

  Future<void> cancelNotifications() =>
      PrayerNotifications.instance.cancelAll();

  Future<void> showAdhanTestNotification() =>
      PrayerNotifications.instance.showAdhanTestNotification();

  Future<void> scheduleNotifications({
    required double latitude,
    required double longitude,
    required int method,
    required int asrSchool,
    required Map<String, int> adjustments,
    required bool arabic,
    required bool adhanEnabled,
    required bool fajrAdhanEnabled,
    required bool dhuhrAdhanEnabled,
    required bool asrAdhanEnabled,
    required bool maghribAdhanEnabled,
    required bool ishaAdhanEnabled,
  }) {
    return PrayerNotifications.instance.schedulePrayerNotifications(
      latitude: latitude,
      longitude: longitude,
      parameters: _engine.parameters(method: method, asrSchool: asrSchool),
      adjustments: adjustments,
      arabic: arabic,
      adhanEnabled: adhanEnabled,
      fajrAdhanEnabled: fajrAdhanEnabled,
      dhuhrAdhanEnabled: dhuhrAdhanEnabled,
      asrAdhanEnabled: asrAdhanEnabled,
      maghribAdhanEnabled: maghribAdhanEnabled,
      ishaAdhanEnabled: ishaAdhanEnabled,
    );
  }
}
