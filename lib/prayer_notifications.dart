import 'package:adhan/adhan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class PrayerNotifications {
  PrayerNotifications._();

  static final PrayerNotifications instance = PrayerNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // استخدمنا قناة جديدة عمداً حتى يتخلص Android من إعداد القناة القديمة
  // التي قد تكون محفوظة بدون صوت. Android يثبت صوت القناة عند أول إنشائها.
  static const String _channelId = 'salati_adhan_makkah_v4';
  static const String _channelName = 'أذان مكة';
  static const String _channelDescription =
      'تنبيهات مواقيت الصلاة مع أذان مكة المكرمة';
  static const String _soundName = 'adhan_makkah';

  bool _initialized = false;
  bool _requesting = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone));
    } catch (e) {
      debugPrint('Timezone initialization error: $e');
      // لا نوقف التطبيق؛ نحاول الاستمرار على المنطقة المحلية الافتراضية.
    }

    const android = AndroidInitializationSettings(
      'salati_launcher_icon',
    );

    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
    );

    await _plugin.initialize(settings);

    await _createAdhanChannel();
    await _requestNotificationPermissions();

    _initialized = true;
  }

  Future<void> _createAdhanChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(_soundName),
      enableVibration: true,
      showBadge: true,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.createNotificationChannel(channel);
  }

  Future<void> _requestNotificationPermissions() async {
    if (_requesting) return;
    _requesting = true;

    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification permission request error: $e');
    } finally {
      _requesting = false;
    }
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_soundName),
        enableVibration: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> showAdhanTestNotification() async {
    await initialize();

    await _plugin.show(
      99001,
      'حان وقت الصلاة',
      'هذا اختبار لأذان مكة من تطبيق صلاتي',
      _notificationDetails(),
    );
  }

  Future<void> schedulePrayerNotifications({
    required double latitude,
    required double longitude,
    required CalculationParameters parameters,
    required Map<String, int> adjustments,
    required bool arabic,
    required bool adhanEnabled,
    required bool fajrAdhanEnabled,
    required bool dhuhrAdhanEnabled,
    required bool asrAdhanEnabled,
    required bool maghribAdhanEnabled,
    required bool ishaAdhanEnabled,
  }) async {
    await initialize();

    await _plugin.cancelAll();

    if (!adhanEnabled) {
      return;
    }

    final coordinates = Coordinates(latitude, longitude);
    final now = tz.TZDateTime.now(tz.local);

    const prayerNames = <String, String>{
      'fajr': 'الفجر',
      'dhuhr': 'الظهر',
      'asr': 'العصر',
      'maghrib': 'المغرب',
      'isha': 'العشاء',
    };

    final enabled = <String, bool>{
      'fajr': fajrAdhanEnabled,
      'dhuhr': dhuhrAdhanEnabled,
      'asr': asrAdhanEnabled,
      'maghrib': maghribAdhanEnabled,
      'isha': ishaAdhanEnabled,
    };

    for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day + dayIndex,
      );

      final times = PrayerTimes(
        coordinates,
        DateComponents(day.year, day.month, day.day),
        parameters,
      );

      final rawTimes = <String, DateTime>{
        'fajr': times.fajr,
        'dhuhr': times.dhuhr,
        'asr': times.asr,
        'maghrib': times.maghrib,
        'isha': times.isha,
      };

      int prayerIndex = 0;

      for (final entry in rawTimes.entries) {
        final key = entry.key;

        if (enabled[key] != true) {
          prayerIndex++;
          continue;
        }

        final adjusted = entry.value.add(
          Duration(minutes: adjustments[key] ?? 0),
        );

        final scheduled = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day,
          adjusted.hour,
          adjusted.minute,
          adjusted.second,
        );

        if (!scheduled.isAfter(now)) {
          prayerIndex++;
          continue;
        }

        final id = 1000 + (dayIndex * 10) + prayerIndex;
        final prayerName = prayerNames[key] ?? key;

        final title = arabic
            ? 'حان وقت صلاة $prayerName'
            : 'It is time for $key prayer';
        final body = arabic
            ? 'أذان مكة المكرمة — صلاتي'
            : 'Makkah Adhan — Salati';

        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          _notificationDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'prayer:$key',
        );

        prayerIndex++;
      }
    }
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }
}
