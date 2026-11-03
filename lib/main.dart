import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:adhan/adhan.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass_v3/flutter_compass_v3.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geomag/geomag.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:audioplayers/audioplayers.dart' as local_audio;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qvp_flutter/qvp_flutter.dart';

import 'prayer_notifications.dart';


// ============================================================
// QURAN SURAH INDEX — standard Madinah Mushaf page starts
// Pages are 1-based (1–604), matching the QVP page numbering.
// ============================================================
const List<String> surahNames = <String>[
  'الفاتحة', 'البقرة', 'آل عمران', 'النساء', 'المائدة', 'الأنعام',
  'الأعراف', 'الأنفال', 'التوبة', 'يونس', 'هود', 'يوسف', 'الرعد',
  'إبراهيم', 'الحجر', 'النحل', 'الإسراء', 'الكهف', 'مريم', 'طه',
  'الأنبياء', 'الحج', 'المؤمنون', 'النور', 'الفرقان', 'الشعراء',
  'النمل', 'القصص', 'العنكبوت', 'الروم', 'لقمان', 'السجدة',
  'الأحزاب', 'سبأ', 'فاطر', 'يس', 'الصافات', 'ص', 'الزمر', 'غافر',
  'فصلت', 'الشورى', 'الزخرف', 'الدخان', 'الجاثية', 'الأحقاف',
  'محمد', 'الفتح', 'الحجرات', 'ق', 'الذاريات', 'الطور', 'النجم',
  'القمر', 'الرحمن', 'الواقعة', 'الحديد', 'المجادلة', 'الحشر',
  'الممتحنة', 'الصف', 'الجمعة', 'المنافقون', 'التغابن', 'الطلاق',
  'التحريم', 'الملك', 'القلم', 'الحاقة', 'المعارج', 'نوح', 'الجن',
  'المزمل', 'المدثر', 'القيامة', 'الإنسان', 'المرسلات', 'النبأ',
  'النازعات', 'عبس', 'التكوير', 'الانفطار', 'المطففين', 'الانشقاق',
  'البروج', 'الطارق', 'الأعلى', 'الغاشية', 'الفجر', 'البلد',
  'الشمس', 'الليل', 'الضحى', 'الشرح', 'التين', 'العلق', 'القدر',
  'البينة', 'الزلزلة', 'العاديات', 'القارعة', 'التكاثر', 'العصر',
  'الهمزة', 'الفيل', 'قريش', 'الماعون', 'الكوثر', 'الكافرون',
  'النصر', 'المسد', 'الإخلاص', 'الفلق', 'الناس',
];

const List<int> surahStartPages = <int>[
  1, 2, 50, 77, 106, 128, 151, 177, 187, 208, 221, 235, 249, 255,
  262, 267, 282, 293, 305, 312, 322, 332, 342, 350, 359, 367, 377,
  385, 396, 404, 411, 415, 418, 428, 434, 440, 446, 453, 458, 467,
  477, 483, 489, 496, 499, 502, 507, 511, 515, 518, 520, 523, 526,
  528, 531, 534, 537, 542, 545, 549, 551, 553, 554, 556, 558, 560,
  562, 564, 566, 568, 570, 572, 574, 575, 577, 578, 580, 582, 583,
  585, 586, 587, 587, 589, 590, 591, 591, 592, 593, 594, 595, 595,
  596, 596, 597, 597, 598, 598, 599, 599, 600, 600, 601, 601, 601,
  602, 602, 602, 603, 603, 603, 604, 604, 604,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.salati.app.audio',
    androidNotificationChannelName: 'تلاوة القرآن',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: false,
  );

  // Do not force an orientation from the app. The operating system decides
  // whether the device is portrait or landscape according to the user's
  // phone/tablet rotation setting. The Quran reader adapts to that size.

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  runApp(const ProviderScope(child: SalatiApp()));
}

final ja.AudioPlayer _quranBackgroundPlayer = ja.AudioPlayer();
final ValueNotifier<_QuranPlaybackInfo?> _quranPlaybackInfo =
    ValueNotifier<_QuranPlaybackInfo?>(null);
final ValueNotifier<int> _quranStopSignal = ValueNotifier<int>(0);

class _QuranPlaybackInfo {
  final String surahName;
  final String reciterName;

  const _QuranPlaybackInfo({
    required this.surahName,
    required this.reciterName,
  });
}

class SalatiApp extends StatefulWidget {
  const SalatiApp({super.key});

  @override
  State<SalatiApp> createState() => _SalatiAppState();
}

class _SalatiAppState extends State<SalatiApp> {
  Locale _locale = const Locale('ar');
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      final language = prefs.getString('language') ?? 'ar';

      setState(() {
        _locale = Locale(language == 'en' ? 'en' : 'ar');
        _themeMode = prefs.getBool('darkMode') == true
            ? ThemeMode.dark
            : ThemeMode.light;
      });
    } catch (e) {
      debugPrint('Preference loading error: $e');
    }
  }

  Future<void> _setLanguage(String language) async {
    final safeLanguage = language == 'en' ? 'en' : 'ar';

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        'language',
        safeLanguage,
      );
    } catch (e) {
      debugPrint('Language saving error: $e');
    }

    if (!mounted) return;

    setState(() {
      _locale = Locale(safeLanguage);
    });
  }

  Future<void> _setTheme(bool dark) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(
        'darkMode',
        dark,
      );
    } catch (e) {
      debugPrint('Theme saving error: $e');
    }

    if (!mounted) return;

    setState(() {
      _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF176B52);
    const deepGreen = Color(0xFF0D4939);
    const softGreen = Color(0xFF2F8065);
    const gold = Color(0xFFE2BD63);
    const cream = Color(0xFFF5F0E4);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'صلاتي | Salati',
      locale: _locale,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.light,
        ).copyWith(
          primary: green,
          secondary: gold,
          tertiary: softGreen,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: cream,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: cream,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF54B58D),
          secondary: gold,
          tertiary: const Color(0xFF6FC8A4),
          surface: const Color(0xFF102B22),
        ),
        scaffoldBackgroundColor: deepGreen,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: deepGreen,
          elevation: 0,
        ),
      ),
      home: SalatiHome(
        locale: _locale,
        onLanguageChanged: _setLanguage,
        darkMode: _themeMode == ThemeMode.dark,
        onThemeChanged: _setTheme,
      ),
    );
  }
}

class SalatiHome extends StatefulWidget {
  final Locale locale;
  final ValueChanged<String> onLanguageChanged;
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  const SalatiHome({
    super.key,
    required this.locale,
    required this.onLanguageChanged,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<SalatiHome> createState() => _SalatiHomeState();
}

class _SalatiHomeState extends State<SalatiHome>
    with WidgetsBindingObserver {
  Position? _position;

  bool _loading = false;

  String? _error;

  String _place = '';

  Timer? _clock;

  DateTime _now = DateTime.now();

  int _hijriCorrection = 0;

  int _asrSchool = 0;

  int _method = 0;

  final Map<String, int> _adjustments = {};

  // ============================================================
  // QIBLA / COMPASS
  // ============================================================

  static const double _kaabaLatitude = 21.422487;
  static const double _kaabaLongitude = 39.826206;

  StreamSubscription<CompassEvent>? _compassSubscription;

  double? _magneticHeading;

  double? _compassAccuracy;

  double _magneticDeclination = 0;

  // ============================================================
  // QIBLA ARRIVAL ALERT
  // ============================================================

  final local_audio.AudioPlayer _qiblaArrivalPlayer = local_audio.AudioPlayer();

  Timer? _qiblaStableTimer;

  bool _qiblaAligned = false;

  bool _qiblaAlertPlaying = false;

  double _qiblaArrivalTolerance = 5.0;

  bool _qiblaSoundEnabled = true;

  bool _qiblaVibrationEnabled = true;

  // ============================================================
  // IQAMA SETTINGS
  // ============================================================

  static const Map<String, int> _defaultIqamaOffsets = {
    'fajr': 20,
    'dhuhr': 15,
    'asr': 15,
    'maghrib': 10,
    'isha': 15,
  };

  final Map<String, int> _iqamaOffsets = {
    'fajr': 20,
    'dhuhr': 15,
    'asr': 15,
    'maghrib': 10,
    'isha': 15,
  };

  // ============================================================
  // ADHAN SETTINGS
  // ============================================================

  bool _adhanEnabled = true;

  bool _fajrAdhanEnabled = true;

  bool _dhuhrAdhanEnabled = true;

  bool _asrAdhanEnabled = true;

  bool _maghribAdhanEnabled = true;

  bool _ishaAdhanEnabled = true;

  // ============================================================
  // MODERN SECTION NAVIGATION
  // ============================================================

  int _sectionIndex = 0;
  bool _quranWasOpen = false;


  // ============================================================
  // MY DAY - DAILY PRAYER TRACKER
  // ============================================================

  static const List<String> _dailyPrayerKeys = [
    'fajr',
    'dhuhr',
    'asr',
    'maghrib',
    'isha',
  ];

  final Map<String, bool> _dailyPrayerCompleted = {
    'fajr': false,
    'dhuhr': false,
    'asr': false,
    'maghrib': false,
    'isha': false,
  };

  String _dailyPrayerDateKey = '';

  // ============================================================
  // LANGUAGE
  // ============================================================

  bool get _arabic => widget.locale.languageCode == 'ar';

  String tr(String ar, String en) => _arabic ? ar : en;

  // ============================================================
  // PRAYER KEYS
  // ============================================================

  static const List<String> _prayerKeys = [
    'fajr',
    'sunrise',
    'dhuhr',
    'asr',
    'maghrib',
    'isha',
  ];

  static const List<String> _iqamaPrayerKeys = [
    'fajr',
    'dhuhr',
    'asr',
    'maghrib',
    'isha',
  ];

  String prayerName(String key) {
    const namesAr = {
      'fajr': 'الفجر',
      'sunrise': 'الشروق',
      'dhuhr': 'الظهر',
      'asr': 'العصر',
      'maghrib': 'المغرب',
      'isha': 'العشاء',
    };

    const namesEn = {
      'fajr': 'Fajr',
      'sunrise': 'Sunrise',
      'dhuhr': 'Dhuhr',
      'asr': 'Asr',
      'maghrib': 'Maghrib',
      'isha': 'Isha',
    };

    return (_arabic ? namesAr : namesEn)[key]!;
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _startCompass();

    _initializeAppData();

    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          final current = DateTime.now();
          setState(() {
            _now = current;
          });
          _syncDailyPrayerDateIfNeeded(current);
        }
      },
    );
  }

  void _startCompass() {
    try {
      _compassSubscription = FlutterCompass.events?.listen(
        (CompassEvent event) {
          if (!mounted) return;

          final heading = event.heading;

          if (heading == null || !heading.isFinite) {
            return;
          }

          setState(() {
            _magneticHeading = _normalize360(heading);

            if (event.accuracy != null &&
                event.accuracy!.isFinite) {
              _compassAccuracy = event.accuracy;
            }
          });

          _checkQiblaArrival();
        },
        onError: (Object error) {
          debugPrint('Compass error: $error');
        },
      );
    } catch (e) {
      debugPrint('Compass initialization error: $e');
    }
  }

  Future<void> _initializeAppData() async {
    await _loadSavedData();

    await _updateMagneticDeclination();

    await _loadAdjustments();

    await _loadIqamaSettings();

    await _loadAdhanSettings();

    await _loadQiblaSettings();

    await _loadDailyPrayerProgress();

    if (!mounted) return;

    await _refreshPrayerNotifications();
  }

  // ============================================================
  // MY DAY - DAILY PRAYER TRACKER
  // ============================================================

  String _dailyDateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadDailyPrayerProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = _dailyDateKey(DateTime.now());
      final savedDate = prefs.getString('daily_prayer_date') ?? '';

      if (savedDate != todayKey) {
        _dailyPrayerDateKey = todayKey;
        for (final key in _dailyPrayerKeys) {
          _dailyPrayerCompleted[key] = false;
          await prefs.setBool('daily_prayer_$key', false);
          await prefs.setBool(
            'daily_history_${todayKey}_$key',
            false,
          );
        }
        await prefs.setString('daily_prayer_date', todayKey);
      } else {
        _dailyPrayerDateKey = savedDate;
        for (final key in _dailyPrayerKeys) {
          _dailyPrayerCompleted[key] =
              prefs.getBool('daily_prayer_$key') ?? false;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Daily prayer progress loading error: $e');
    }
  }

  Future<void> _syncDailyPrayerDateIfNeeded(DateTime now) async {
    final todayKey = _dailyDateKey(now);

    if (_dailyPrayerDateKey.isEmpty ||
        _dailyPrayerDateKey == todayKey) {
      return;
    }

    _dailyPrayerDateKey = todayKey;

    for (final key in _dailyPrayerKeys) {
      _dailyPrayerCompleted[key] = false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('daily_prayer_date', todayKey);
      for (final key in _dailyPrayerKeys) {
        await prefs.setBool('daily_prayer_$key', false);
        await prefs.setBool(
          'daily_history_${todayKey}_$key',
          false,
        );
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Daily prayer date reset error: $e');
    }
  }

  Future<void> _toggleDailyPrayer(
    String key,
    Map<String, DateTime> times,
  ) async {
    final prayerTime = times[key];

    // تسجيل الصلاة يعتمد على اختيار المستخدم، وليس على مقارنة
    // وقت الصلاة بساعة الجهاز؛ هذا يمنع اختلافات المنطقة الزمنية
    // أو تحديث الساعة من تعطيل زر "تمت الصلاة".
    if (prayerTime == null) {
      return;
    }

    final newValue = !(_dailyPrayerCompleted[key] ?? false);

    setState(() {
      _dailyPrayerCompleted[key] = newValue;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final dateKey = _dailyDateKey(_now);
      await prefs.setBool('daily_prayer_$key', newValue);
      await prefs.setBool(
        'daily_history_${dateKey}_$key',
        newValue,
      );
      await prefs.setString(
        'daily_prayer_date',
        dateKey,
      );
    } catch (e) {
      debugPrint('Daily prayer progress saving error: $e');
    }
  }

  int get _completedDailyPrayers =>
      _dailyPrayerKeys.where(
        (key) => _dailyPrayerCompleted[key] ?? false,
      ).length;

  Future<List<int>> _loadWeeklyPrayerStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final stats = <int>[];

      for (int offset = 6; offset >= 0; offset--) {
        final date = DateTime(
          today.year,
          today.month,
          today.day - offset,
        );
        final dateKey = _dailyDateKey(date);
        int count = 0;

        for (final key in _dailyPrayerKeys) {
          if (offset == 0) {
            await prefs.setBool(
              'daily_history_${dateKey}_$key',
              _dailyPrayerCompleted[key] ?? false,
            );
          }

          if (prefs.getBool('daily_history_${dateKey}_$key') == true) {
            count++;
          }
        }
        stats.add(count);
      }

      return stats;
    } catch (e) {
      debugPrint('Weekly prayer statistics error: $e');
      return List<int>.filled(7, 0);
    }
  }

  // ============================================================
  // MAGNETIC DECLINATION
  // ============================================================

  Future<void> _updateMagneticDeclination() async {
    final position = _position;

    if (position == null) {
      if (mounted) {
        setState(() {
          _magneticDeclination = 0;
        });
      }
      return;
    }

    try {
      final result = GeoMag().calculate(
        position.latitude,
        position.longitude,
      );

      if (!result.dec.isFinite) {
        return;
      }

      if (mounted) {
        setState(() {
          _magneticDeclination = result.dec;
        });
      }
    } catch (e) {
      debugPrint(
        'Magnetic declination error: $e',
      );
    }
  }

  double _normalize360(double value) {
    final result = value % 360;

    if (result < 0) {
      return result + 360;
    }

    return result;
  }

  double _normalize180(double value) {
    final normalized = _normalize360(value);

    return normalized > 180
        ? normalized - 360
        : normalized;
  }

  double? get _trueHeading {
    if (_magneticHeading == null) {
      return null;
    }

    return _normalize360(
      _magneticHeading! + _magneticDeclination,
    );
  }

  // ============================================================
  // QIBLA BEARING
  // ============================================================

  double? _calculateQiblaBearing() {
    final position = _position;

    if (position == null) {
      return null;
    }

    final lat1 =
        position.latitude * math.pi / 180;

    final lon1 =
        position.longitude * math.pi / 180;

    final lat2 =
        _kaabaLatitude * math.pi / 180;

    final lon2 =
        _kaabaLongitude * math.pi / 180;

    final deltaLon = lon2 - lon1;

    final y =
        math.sin(deltaLon) * math.cos(lat2);

    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) *
            math.cos(lat2) *
            math.cos(deltaLon);

    final bearing =
        math.atan2(y, x) * 180 / math.pi;

    return _normalize360(bearing);
  }

  double? get _qiblaRelativeAngle {
    final qibla = _calculateQiblaBearing();

    final heading = _trueHeading;

    if (qibla == null || heading == null) {
      return null;
    }

    return _normalize180(
      qibla - heading,
    );
  }

  String _qiblaDirectionText() {
    final angle = _qiblaRelativeAngle;

    if (angle == null) {
      return tr(
        'جاري تحديد اتجاه الهاتف...',
        'Reading phone direction...',
      );
    }

    final rounded = angle.abs().round();

    if (rounded <= 3) {
      return tr(
        'القبلة أمامك مباشرة',
        'Qibla is directly ahead',
      );
    }

    if (angle > 0) {
      return tr(
        'القبلة إلى اليمين بمقدار $rounded°',
        'Qibla is $rounded° to the right',
      );
    }

    return tr(
      'القبلة إلى اليسار بمقدار $rounded°',
      'Qibla is $rounded° to the left',
    );
  }

  // ============================================================
  // QIBLA ARRIVAL ALERT
  // ============================================================

  void _checkQiblaArrival() {
    final angle = _qiblaRelativeAngle;

    if (angle == null) {
      _qiblaStableTimer?.cancel();
      if (_qiblaAligned && mounted) {
        setState(() {
          _qiblaAligned = false;
        });
      }
      return;
    }

    final isInside =
        angle.abs() <= _qiblaArrivalTolerance;

    if (!isInside) {
      _qiblaStableTimer?.cancel();

      if (_qiblaAligned && mounted) {
        setState(() {
          _qiblaAligned = false;
        });
      }
      return;
    }

    if (_qiblaAligned ||
        _qiblaStableTimer?.isActive == true) {
      return;
    }

    // Require the direction to remain inside the target zone
    // briefly before confirming arrival. This prevents false alerts
    // caused by a single noisy compass reading.
    _qiblaStableTimer = Timer(
      const Duration(milliseconds: 700),
      () async {
        final currentAngle = _qiblaRelativeAngle;

        if (!mounted ||
            currentAngle == null ||
            currentAngle.abs() >
                _qiblaArrivalTolerance) {
          return;
        }

        setState(() {
          _qiblaAligned = true;
        });

        if (_qiblaVibrationEnabled) {
          await HapticFeedback.mediumImpact();
        }

        if (_qiblaSoundEnabled) {
          await _playQiblaArrivalSound();
        }
      },
    );
  }

  Future<void> _playQiblaArrivalSound() async {
    if (_qiblaAlertPlaying) {
      return;
    }

    _qiblaAlertPlaying = true;

    try {
      await _qiblaArrivalPlayer.stop();
      await _qiblaArrivalPlayer.play(
        local_audio.AssetSource('sounds/qibla_arrival.mp3'),
        volume: 0.65,
      );
    } catch (e) {
      debugPrint(
        'Qibla arrival sound error: $e',
      );
    } finally {
      _qiblaAlertPlaying = false;
    }
  }

  // ============================================================
  // QIBLA SETTINGS
  // ============================================================

  Future<void> _loadQiblaSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        _qiblaSoundEnabled =
            prefs.getBool('qibla_sound_enabled') ?? true;

        _qiblaVibrationEnabled =
            prefs.getBool('qibla_vibration_enabled') ?? true;

        final savedTolerance =
            prefs.getDouble('qibla_arrival_tolerance');

        if (savedTolerance == 3.0 ||
            savedTolerance == 5.0 ||
            savedTolerance == 10.0) {
          _qiblaArrivalTolerance = savedTolerance!;
        }
      });
    } catch (e) {
      debugPrint('Qibla settings loading error: $e');
    }
  }

  Future<void> _saveQiblaSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(
        'qibla_sound_enabled',
        _qiblaSoundEnabled,
      );

      await prefs.setBool(
        'qibla_vibration_enabled',
        _qiblaVibrationEnabled,
      );

      await prefs.setDouble(
        'qibla_arrival_tolerance',
        _qiblaArrivalTolerance,
      );
    } catch (e) {
      debugPrint('Qibla settings saving error: $e');
    }
  }

  Future<void> _showQiblaSettingsSheet(
    ColorScheme scheme,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final tolerance = _qiblaArrivalTolerance;

            return Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('إعدادات القبلة', 'Qibla settings'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  tr(
                                    'تحكمّي بطريقة التنبيه ودقة الوصول إلى القبلة.',
                                    'Control the arrival alert and Qibla accuracy.',
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildQiblaSettingSwitch(
                        scheme: scheme,
                        icon: Icons.volume_up_rounded,
                        title: tr('صوت الوصول إلى القبلة', 'Qibla arrival sound'),
                        subtitle: tr(
                          'تشغيل نغمة قصيرة عند الوصول إلى الاتجاه الصحيح.',
                          'Play a short tone when the correct direction is reached.',
                        ),
                        value: _qiblaSoundEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            _qiblaSoundEnabled = value;
                          });
                          setState(() {});
                          _saveQiblaSettings();
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildQiblaSettingSwitch(
                        scheme: scheme,
                        icon: Icons.vibration_rounded,
                        title: tr('اهتزاز الوصول', 'Arrival vibration'),
                        subtitle: tr(
                          'اهتزاز خفيف مع تأكيد اتجاه القبلة.',
                          'A gentle vibration with Qibla confirmation.',
                        ),
                        value: _qiblaVibrationEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            _qiblaVibrationEnabled = value;
                          });
                          setState(() {});
                          _saveQiblaSettings();
                        },
                      ),
                      const SizedBox(height: 18),
                      Text(
                        tr('دقة الوصول إلى القبلة', 'Arrival tolerance'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(
                          'كلما كانت الزاوية أصغر كان التنبيه أدق.',
                          'A smaller angle makes the alert more precise.',
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildToleranceChoice(
                            scheme,
                            3.0,
                            tr('دقيق ±3°', 'Precise ±3°'),
                            setSheetState,
                          ),
                          const SizedBox(width: 8),
                          _buildToleranceChoice(
                            scheme,
                            5.0,
                            tr('متوازن ±5°', 'Balanced ±5°'),
                            setSheetState,
                          ),
                          const SizedBox(width: 8),
                          _buildToleranceChoice(
                            scheme,
                            10.0,
                            tr('مرن ±10°', 'Flexible ±10°'),
                            setSheetState,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 19,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                tr(
                                  'إذا كانت دقة الحساس ضعيفة، حرّكي الهاتف على شكل رقم 8 وابتعدي عن المعادن والمغناطيس ثم أعيدي المحاولة.',
                                  'If sensor accuracy is low, move the phone in a figure-8, keep it away from metal and magnets, then try again.',
                                ),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.45,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQiblaSettingSwitch({
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildToleranceChoice(
    ColorScheme scheme,
    double value,
    String label,
    StateSetter setSheetState,
  ) {
    final selected = _qiblaArrivalTolerance == value;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setSheetState(() {
            _qiblaArrivalTolerance = value;
          });
          setState(() {});
          _qiblaStableTimer?.cancel();
          _qiblaAligned = false;
          _saveQiblaSettings();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.45),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // REFRESH NOTIFICATIONS
  // ============================================================

  Future<void> _refreshPrayerNotifications() async {
    final position = _position;

    if (position == null) {
      return;
    }

    try {
      await PrayerNotifications.instance
          .schedulePrayerNotifications(
        latitude: position.latitude,
        longitude: position.longitude,
        parameters: _parameters(),
        adjustments:
            Map<String, int>.from(_adjustments),
        arabic: _arabic,
        adhanEnabled: _adhanEnabled,
        fajrAdhanEnabled:
            _fajrAdhanEnabled,
        dhuhrAdhanEnabled:
            _dhuhrAdhanEnabled,
        asrAdhanEnabled:
            _asrAdhanEnabled,
        maghribAdhanEnabled:
            _maghribAdhanEnabled,
        ishaAdhanEnabled:
            _ishaAdhanEnabled,
      );
    } catch (e) {
      debugPrint(
        'Prayer notifications scheduling error: $e',
      );
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // The Quran reader owns its own orientation/viewport lifecycle.
    // Do not change the parent section during Android metric transitions.
  }

  @override
  void dispose() {
    _clock?.cancel();

    _compassSubscription?.cancel();
    _qiblaStableTimer?.cancel();
    _qiblaArrivalPlayer.dispose();
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // ============================================================
  // LOAD SAVED DATA
  // ============================================================

  Future<void> _loadSavedData() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      final lat =
          prefs.getDouble('latitude');

      final lon =
          prefs.getDouble('longitude');

      if (!mounted) return;

      setState(() {
        if (lat != null &&
            lon != null &&
            lat >= -90 &&
            lat <= 90 &&
            lon >= -180 &&
            lon <= 180) {
          _position = Position(
            latitude: lat,
            longitude: lon,
            timestamp: DateTime.tryParse(
                  prefs.getString(
                        'locationTime',
                      ) ??
                      '',
                ) ??
                DateTime.now(),
            accuracy:
                prefs.getDouble('accuracy') ?? 0,
            altitude:
                prefs.getDouble('altitude') ?? 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );

          _place =
              prefs.getString('place') ?? '';
        }

        _hijriCorrection =
            prefs.getInt('hijriCorrection') ??
                0;

        _asrSchool =
            prefs.getInt('asrSchool') ?? 0;

        _method =
            prefs.getInt('method') ?? 0;
      });
    } catch (e) {
      debugPrint(
        'Saved data loading error: $e',
      );
    }
  }

  // ============================================================
  // LOAD IQAMA SETTINGS
  // ============================================================

  Future<void> _loadIqamaSettings() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      for (final key in _iqamaPrayerKeys) {
        _iqamaOffsets[key] =
            prefs.getInt('iqama_$key') ??
                _defaultIqamaOffsets[key]!;
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint(
        'Iqama settings loading error: $e',
      );
    }
  }

  Future<void> _saveIqamaOffset(
    String key,
    int value,
  ) async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setInt(
        'iqama_$key',
        value,
      );
    } catch (e) {
      debugPrint(
        'Iqama setting saving error: $e',
      );
    }
  }

  // ============================================================
  // LOAD ADHAN SETTINGS
  // ============================================================

  Future<void> _loadAdhanSettings() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        _adhanEnabled =
            prefs.getBool('adhanEnabled') ??
                true;

        _fajrAdhanEnabled =
            prefs.getBool(
                  'fajrAdhanEnabled',
                ) ??
                true;

        _dhuhrAdhanEnabled =
            prefs.getBool(
                  'dhuhrAdhanEnabled',
                ) ??
                true;

        _asrAdhanEnabled =
            prefs.getBool(
                  'asrAdhanEnabled',
                ) ??
                true;

        _maghribAdhanEnabled =
            prefs.getBool(
                  'maghribAdhanEnabled',
                ) ??
                true;

        _ishaAdhanEnabled =
            prefs.getBool(
                  'ishaAdhanEnabled',
                ) ??
                true;
      });
    } catch (e) {
      debugPrint(
        'Adhan settings loading error: $e',
      );
    }
  }

  // ============================================================
  // SAVE ADHAN SETTING
  // ============================================================

  Future<void> _saveAdhanSetting(
    String key,
    bool value,
  ) async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setBool(
        key,
        value,
      );
    } catch (e) {
      debugPrint(
        'Adhan setting saving error: $e',
      );
    }
  }

  // ============================================================
  // SET ALL ADHAN
  // ============================================================

  Future<void> _setAllAdhan(
    bool value,
  ) async {
    setState(() {
      _adhanEnabled = value;
      _fajrAdhanEnabled = value;
      _dhuhrAdhanEnabled = value;
      _asrAdhanEnabled = value;
      _maghribAdhanEnabled = value;
      _ishaAdhanEnabled = value;
    });

    await _saveAdhanSetting(
      'adhanEnabled',
      value,
    );

    await _saveAdhanSetting(
      'fajrAdhanEnabled',
      value,
    );

    await _saveAdhanSetting(
      'dhuhrAdhanEnabled',
      value,
    );

    await _saveAdhanSetting(
      'asrAdhanEnabled',
      value,
    );

    await _saveAdhanSetting(
      'maghribAdhanEnabled',
      value,
    );

    await _saveAdhanSetting(
      'ishaAdhanEnabled',
      value,
    );

    await _refreshPrayerNotifications();
  }

  // ============================================================
  // SET SINGLE ADHAN
  // ============================================================

  Future<void> _setSingleAdhan(
    String prayer,
    bool value,
  ) async {
    if (!_adhanEnabled && value) {
      setState(() {
        _adhanEnabled = true;
      });

      await _saveAdhanSetting(
        'adhanEnabled',
        true,
      );
    }

    setState(() {
      switch (prayer) {
        case 'fajr':
          _fajrAdhanEnabled = value;
          break;

        case 'dhuhr':
          _dhuhrAdhanEnabled = value;
          break;

        case 'asr':
          _asrAdhanEnabled = value;
          break;

        case 'maghrib':
          _maghribAdhanEnabled = value;
          break;

        case 'isha':
          _ishaAdhanEnabled = value;
          break;
      }
    });

    await _saveAdhanSetting(
      '${prayer}AdhanEnabled',
      value,
    );

    await _refreshPrayerNotifications();
  }

  // ============================================================
  // LOCATION
  // ============================================================

  Future<void> _getLocation() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final enabled =
          await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        if (mounted) {
          setState(() {
            _error = tr(
              'خدمة الموقع مغلقة. فعّلي GPS ثم أعيدي المحاولة.',
              'Location services are off. Enable GPS and try again.',
            );
          });
        }

        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
          LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _error = tr(
              'لم يتم منح إذن الموقع.',
              'Location permission was denied.',
            );
          });
        }

        return;
      }

      if (permission ==
          LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _error = tr(
              'إذن الموقع مرفوض نهائيًا. افتحي إعدادات التطبيق.',
              'Location permission is permanently denied. Open app settings.',
            );
          });
        }

        return;
      }

      final position =
          await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit:
              Duration(seconds: 25),
        ),
      );

      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setDouble(
        'latitude',
        position.latitude,
      );

      await prefs.setDouble(
        'longitude',
        position.longitude,
      );

      await prefs.setDouble(
        'accuracy',
        position.accuracy,
      );

      await prefs.setDouble(
        'altitude',
        position.altitude,
      );

      await prefs.setString(
        'locationTime',
        position.timestamp.toIso8601String(),
      );

      if (!mounted) return;

      setState(() {
        _position = position;
        _place = '';
      });

      await _updateMagneticDeclination();

      await _refreshPrayerNotifications();

      if (mounted) {
        _showMessage(
          tr(
            'تم تحديث الموقع بنجاح',
            'Location updated',
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'Location error: $e',
      );

      if (!mounted) return;

      setState(() {
        _error = tr(
          'تعذر تحديد الموقع. تحققي من GPS وحاولي مجددًا.',
          'Could not determine location. Check GPS and try again.',
        );
      });

      _showMessage(_error!);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteLocation() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      await prefs.remove('latitude');
      await prefs.remove('longitude');
      await prefs.remove('accuracy');
      await prefs.remove('altitude');
      await prefs.remove('locationTime');
      await prefs.remove('place');

      if (!mounted) return;

      setState(() {
        _position = null;
        _place = '';
        _magneticDeclination = 0;
      });

      try {
        await PrayerNotifications.instance
            .cancelAll();
      } catch (e) {
        debugPrint(
          'Prayer notifications cancellation error: $e',
        );
      }

      if (mounted) {
        _showMessage(
          tr(
            'تم حذف الموقع والتنبيهات المجدولة',
            'Location and scheduled notifications cleared',
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'Location deletion error: $e',
      );

      _showMessage(
        tr(
          'تعذر حذف الموقع المحفوظ',
          'Could not delete saved location',
        ),
      );
    }
  }

  Future<void> _openLocationSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint(
        'Opening app settings error: $e',
      );
    }
  }

  // ============================================================
  // SAVE GENERAL SETTING
  // ============================================================

  Future<void> _saveSetting(
    String key,
    int value,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      key,
      value,
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // CALCULATION PARAMETERS
  // ============================================================

  CalculationParameters _parameters() {
    CalculationParameters params;

    switch (_method) {
      case 1:
        params =
            CalculationMethod.umm_al_qura
                .getParameters();
        break;

      case 2:
        params =
            CalculationMethod.egyptian
                .getParameters();
        break;

      case 3:
        params =
            CalculationMethod.karachi
                .getParameters();
        break;

      case 4:
        params =
            CalculationMethod.north_america
                .getParameters();
        break;

      case 5:
        params =
            CalculationMethod.kuwait
                .getParameters();
        break;

      case 6:
        params =
            CalculationMethod.qatar
                .getParameters();
        break;

      default:
        params =
            CalculationMethod
                .muslim_world_league
                .getParameters();
    }

    params.madhab =
        _asrSchool == 1
            ? Madhab.hanafi
            : Madhab.shafi;

    return params;
  }

  // ============================================================
  // CALCULATE PRAYER TIMES
  // ============================================================

  Map<String, DateTime> _calculateTimes() {
    final position = _position;

    if (position == null) {
      return {};
    }

    final coordinates = Coordinates(
      position.latitude,
      position.longitude,
    );

    final date =
        DateComponents.from(_now);

    final times = PrayerTimes(
      coordinates,
      date,
      _parameters(),
    );

    final raw = <String, DateTime>{
      'fajr': times.fajr,
      'sunrise': times.sunrise,
      'dhuhr': times.dhuhr,
      'asr': times.asr,
      'maghrib': times.maghrib,
      'isha': times.isha,
    };

    return raw.map(
      (key, value) {
        final adjusted = value.add(
          Duration(
            minutes:
                _adjustments[key] ?? 0,
          ),
        );

        return MapEntry(
          key,
          adjusted,
        );
      },
    );
  }

  // ============================================================
  // IQAMA TIME
  // ============================================================

  DateTime? _iqamaTime(
    String key,
    Map<String, DateTime> times,
  ) {
    final adhanTime = times[key];

    if (adhanTime == null) {
      return null;
    }

    if (!_iqamaPrayerKeys.contains(key)) {
      return null;
    }

    return adhanTime.add(
      Duration(
        minutes:
            _iqamaOffsets[key] ?? 0,
      ),
    );
  }

  // ============================================================
  // FORMAT DIGITAL TIME
  // ============================================================

  String _formatDigitalTime(
    DateTime time,
  ) {
    final hour =
        time.hour % 12 == 0
            ? 12
            : time.hour % 12;

    final minute = time.minute
        .toString()
        .padLeft(2, '0');

    if (_arabic) {
      return '${_arabicDigits(hour)}:${_arabicDigits(minute)}';
    }

    return '$hour:$minute';
  }

  // ============================================================
  // FORMAT TIME
  // ============================================================

  String _formatTime(
    DateTime time,
  ) {
    final hour =
        time.hour % 12 == 0
            ? 12
            : time.hour % 12;

    final minute = time.minute
        .toString()
        .padLeft(2, '0');

    final period =
        time.hour >= 12 ? 'PM' : 'AM';

    if (_arabic) {
      final h = _arabicDigits(hour);
      final m = _arabicDigits(minute);

      return '$h:$m ${time.hour >= 12 ? 'م' : 'ص'}';
    }

    return '$hour:$minute $period';
  }

  String _arabicDigits(Object value) {
    const western =
        '0123456789';

    const eastern =
        '٠١٢٣٤٥٦٧٨٩';

    return value
        .toString()
        .split('')
        .map(
          (c) {
            final index =
                western.indexOf(c);

            return index < 0
                ? c
                : eastern[index];
          },
        )
        .join();
  }

  // ============================================================
  // DATE
  // ============================================================

  String _dateText() {
    final d = _now;

    const weekdaysAr = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];

    const weekdaysEn = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const monthsAr = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    const monthsEn = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final weekdayIndex = d.weekday - 1;
    final weekday = _arabic
        ? weekdaysAr[weekdayIndex]
        : weekdaysEn[weekdayIndex];

    final month = _arabic
        ? monthsAr[d.month - 1]
        : monthsEn[d.month - 1];

    final day = _arabicDigits(d.day);
    final year = _arabicDigits(d.year);

    final adjustedDate = d.add(
      Duration(
        days: _hijriCorrection,
      ),
    );

    final hijri = HijriCalendar.fromDate(
      adjustedDate,
    );

    final hijriDay = _arabic
        ? _arabicDigits(hijri.hDay)
        : hijri.hDay.toString();
    final hijriYear = _arabic
        ? _arabicDigits(hijri.hYear)
        : hijri.hYear.toString();

    return _arabic
        ? '$weekday، $day $month $year  •  $hijriDay ${hijri.longMonthName} $hijriYear هـ'
        : '$weekday, ${d.day} $month ${d.year}  •  ${hijri.hDay} ${hijri.longMonthName} ${hijri.hYear} AH';
  }

  // ============================================================
  // NEXT PRAYER
  // ============================================================

  MapEntry<String, DateTime>? _nextPrayer(
    Map<String, DateTime> times,
  ) {
    for (final key in _prayerKeys) {
      if (key == 'sunrise') {
        continue;
      }

      final time = times[key];

      if (time != null &&
          time.isAfter(_now)) {
        return MapEntry(
          key,
          time,
        );
      }
    }

    if (times['fajr'] != null) {
      return MapEntry(
        'fajr',
        times['fajr']!.add(
          const Duration(days: 1),
        ),
      );
    }

    return null;
  }

  // ============================================================
  // COUNTDOWN
  // ============================================================

  String _countdown(
    Duration duration,
  ) {
    final hours =
        duration.inHours;

    final minutes =
        duration.inMinutes.remainder(60);

    final seconds =
        duration.inSeconds.remainder(60);

    String two(int value) =>
        value.toString().padLeft(2, '0');

    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  // ============================================================
  // ADJUST PRAYER
  // ============================================================

  Future<void> _adjustPrayer(
    String key,
    int delta,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    final value =
        (_adjustments[key] ?? 0) + delta;

    if (value == 0) {
      _adjustments.remove(key);

      await prefs.remove(
        'adjust_$key',
      );
    } else {
      _adjustments[key] = value;

      await prefs.setInt(
        'adjust_$key',
        value,
      );
    }

    if (mounted) {
      setState(() {});
    }

    await _refreshPrayerNotifications();
  }

  // ============================================================
  // LOAD ADJUSTMENTS
  // ============================================================

  Future<void> _loadAdjustments() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      for (final key in _prayerKeys) {
        final value =
            prefs.getInt(
                  'adjust_$key',
                ) ??
                0;

        if (value != 0) {
          _adjustments[key] = value;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint(
        'Prayer adjustments loading error: $e',
      );
    }
  }

  // ============================================================
  // MODERN SECTIONED UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final times = _calculateTimes();
    final next = _nextPrayer(times);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final size = MediaQuery.sizeOf(context);
    // The Quran section alone uses true edge-to-edge full-screen mode.
    // Prayer/home/settings keep their normal system bars and navigation.
    final immersiveQuran = _sectionIndex == 4;

    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope<void>(
        canPop: !_quranWasOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_quranWasOpen) {
            // Android back / system back exits the Quran section first instead
            // of closing the whole Salati app.
            _goToSection(0);
          }
        },
        child: Scaffold(
        backgroundColor: immersiveQuran
            ? Colors.black
            : theme.scaffoldBackgroundColor,
        body: SafeArea(
          top: !immersiveQuran,
          bottom: !immersiveQuran,
          left: true,
          right: true,
          child: Column(
            children: [
              if (!immersiveQuran) _buildModernHeader(scheme),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: immersiveQuran
                            ? null
                            : (details) {
                                final velocity = details.primaryVelocity ?? 0;
                                if (velocity.abs() < 250) return;

                                // Preserve RTL/LTR section swipe navigation.
                                final delta = _arabic
                                    ? (velocity > 0 ? -1 : 1)
                                    : (velocity > 0 ? 1 : -1);
                                final nextIndex = _sectionIndex + delta;
                                if (nextIndex >= 0 && nextIndex <= 3) {
                                  _goToSection(nextIndex);
                                }
                              },
                        child: IndexedStack(
                          index: _sectionIndex,
                          children: [
                            _buildModernHomePage(times, next, scheme),
                            _buildModernPrayerPage(times, next, scheme),
                            _buildModernQiblaPage(scheme),
                            _buildModernAdhkarPage(scheme),
                            // IMPORTANT: QVP must not be mounted while the Quran
                            // section is hidden. IndexedStack lays out all children,
                            // and mounting QVP offstage can give it an invalid
                            // viewport and cause the Quran to become black.
                            // Visibility(maintainState: false) replaces it with
                            // a harmless placeholder until section 4 is selected.
                            Visibility(
                              visible: _sectionIndex == 4,
                              maintainState: false,
                              maintainAnimation: false,
                              maintainSize: false,
                              maintainSemantics: false,
                              maintainInteractivity: false,
                              child: _buildModernQuranPage(scheme),
                            ),
                            _buildModernSettingsPage(scheme),
                          ],
                        ),
                      ),
                    ),
                    if (!immersiveQuran) _buildQuranMiniPlayer(),
                  ],
                ),
              ),
              if (!immersiveQuran) _buildModernNavigation(scheme),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(ColorScheme scheme) {
    final title = [
      tr('الرئيسية', 'Home'),
      tr('مواقيت الصلاة', 'Prayer times'),
      tr('اتجاه القبلة', 'Qibla'),
      tr('الأذكار والأدعية', 'Adhkar & Duas'),
      tr('المصحف الشريف', 'Holy Quran'),
      tr('الإعدادات', 'Settings'),
    ][_sectionIndex];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF176B52),
                  Color(0xFF0D4939),
                ],
              ),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF176B52).withValues(alpha: .16),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: const Icon(
              Icons.nightlight_round,
              color: Color(0xFFE2BD63),
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'صلاتي',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('تغيير اللغة', 'Change language'),
            onPressed: () => widget.onLanguageChanged(_arabic ? 'en' : 'ar'),
            icon: const Icon(Icons.translate_rounded),
          ),
          IconButton(
            tooltip: tr('الإعدادات', 'Settings'),
            onPressed: () => _goToSection(5),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  void _goToSection(int index) {
    if (index < 0 || index > 5 || !mounted) return;

    _quranWasOpen = index == 4;
    setState(() => _sectionIndex = index);
  }

  Widget _buildModernNavigation(ColorScheme scheme) {
    const icons = [
      Icons.home_rounded,
      Icons.access_time_filled_rounded,
      Icons.explore_rounded,
      Icons.menu_book_rounded,
      Icons.menu_book_rounded,
      Icons.settings_rounded,
    ];

    final labels = [
      tr('الرئيسية', 'Home'),
      tr('الصلاة', 'Prayer'),
      tr('القبلة', 'Qibla'),
      tr('الأذكار', 'Adhkar'),
      tr('المصحف', 'Quran'),
      tr('الإعدادات', 'Settings'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: List.generate(6, (index) {
          final selected = _sectionIndex == index;

          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _goToSection(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 52,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE2BD63).withValues(alpha: .18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icons[index],
                      size: 22,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _modernPageScroll({
    required List<Widget> children,
    EdgeInsets padding = const EdgeInsets.fromLTRB(16, 4, 16, 20),
  }) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: padding,
      children: children,
    );
  }

  Widget _buildModernHomePage(
    Map<String, DateTime> times,
    MapEntry<String, DateTime>? next,
    ColorScheme scheme,
  ) {
    return _modernPageScroll(
      children: [
        _buildModernHero(scheme),
        const SizedBox(height: 12),
        _buildModernDateStrip(scheme),
        const SizedBox(height: 12),
        _buildModernNextPrayer(next, scheme),
        const SizedBox(height: 12),
        _buildModernPrayerMiniGrid(times, next, scheme),
        const SizedBox(height: 12),
        _buildMyDayCard(times, scheme),
        const SizedBox(height: 12),
        _buildModernQuranCard(scheme),
        const SizedBox(height: 12),
        _buildModernQiblaMiniCard(scheme),
        const SizedBox(height: 12),
        _buildWeeklyPrayerCard(scheme),
        const SizedBox(height: 12),
        _buildLocationCard(scheme),
        const SizedBox(height: 12),
        _buildModernQuickTiles(scheme),
        const SizedBox(height: 16),
        _buildModernQuoteCard(scheme),
      ],
    );
  }

  Widget _buildModernHero(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF176B52),
            Color(0xFF0D4939),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176B52).withValues(alpha: .20),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('صلاتي', 'Salati'),
                  style: const TextStyle(
                    color: Color(0xFFE2BD63),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'رفيقك اليومي مع الصلاة',
                    'Your daily companion for prayer',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  tr(
                    'مواقيتك، قبلتك، وأورادك في مكان واحد.',
                    'Prayer times, Qibla and daily worship in one place.',
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .78),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .09),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE2BD63).withValues(alpha: .70),
                width: 1.2,
              ),
            ),
            child: const Icon(
              Icons.nightlight_round,
              color: Color(0xFFE2BD63),
              size: 42,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDateStrip(ColorScheme scheme) {
    final adjustedDate = _now.add(
      Duration(days: _hijriCorrection),
    );
    final hijri = HijriCalendar.fromDate(adjustedDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE2BD63).withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE2BD63).withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFF9A7325),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_now.day}/${_now.month}/${_now.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr(
                    '${hijri.hDay} ${hijri.longMonthName} ${hijri.hYear} هـ',
                    '${hijri.hDay} ${hijri.longMonthName} ${hijri.hYear} AH',
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            _arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildModernNextPrayer(
    MapEntry<String, DateTime>? next,
    ColorScheme scheme,
  ) {
    final nextTime = next?.value;
    final duration = nextTime == null ? Duration.zero : nextTime.difference(_now);

    final countdown = duration.isNegative
        ? '00:00:00'
        : '${duration.inHours.toString().padLeft(2, '0')}:'
            '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:'
            '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    final name = next == null
        ? tr('لا توجد بيانات', 'No data')
        : prayerName(next.key);
    final time = nextTime == null ? '--:--' : _formatTime(nextTime);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF176B52),
            Color(0xFF0D4939),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF176B52).withValues(alpha: .18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.wb_sunny_rounded,
                color: Color(0xFFE2BD63),
                size: 26,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  tr('الصلاة القادمة', 'Next prayer'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .76),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            countdown,
            style: const TextStyle(
              color: Color(0xFFE2BD63),
              fontSize: 29,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _modernMetric(
                  tr('الأذان', 'Adhan'),
                  time,
                  Icons.notifications_active_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _modernMetric(
                  tr('الموقع', 'Location'),
                  _place.isEmpty ? tr('جارٍ التحديد', 'Locating') : _place,
                  Icons.location_on_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modernMetric(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFE2BD63), size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .65),
                    fontSize: 9,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernPrayerMiniGrid(
    Map<String, DateTime> times,
    MapEntry<String, DateTime>? next,
    ColorScheme scheme,
  ) {
    final keys = _iqamaPrayerKeys;

    return Row(
      children: keys.map((key) {
        final time = times[key];
        final selected = next?.key == key;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
              decoration: BoxDecoration(
                color: selected ? scheme.primary : scheme.surface,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: selected
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: .40),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: .16),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  Icon(
                    _prayerIcon(key),
                    size: 18,
                    color: selected
                        ? const Color(0xFFE2BD63)
                        : scheme.primary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    prayerName(key),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    time == null ? '--:--' : _formatTime(time),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: selected
                          ? Colors.white
                          : scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _prayerIcon(String key) {
    switch (key) {
      case 'fajr':
        return Icons.wb_twilight_rounded;
      case 'dhuhr':
        return Icons.wb_sunny_rounded;
      case 'asr':
        return Icons.wb_sunny_outlined;
      case 'maghrib':
        return Icons.wb_twilight_outlined;
      case 'isha':
        return Icons.nightlight_round;
      default:
        return Icons.access_time_rounded;
    }
  }

  Widget _buildModernQiblaMiniCard(ColorScheme scheme) {
    final relative = _qiblaRelativeAngle;
    final aligned =
        relative != null && relative.abs() <= _qiblaArrivalTolerance;

    return InkWell(
      borderRadius: BorderRadius.circular(23),
      onTap: () => _goToSection(2),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: aligned
                ? const [
                    Color(0xFF176B52),
                    Color(0xFF0D4939),
                  ]
                : [
                    scheme.surface,
                    scheme.surfaceContainerHighest.withValues(alpha: .35),
                  ],
          ),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: aligned
                ? const Color(0xFFE2BD63).withValues(alpha: .70)
                : scheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: aligned
                    ? Colors.white.withValues(alpha: .10)
                    : scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.explore_rounded,
                color: aligned ? const Color(0xFFE2BD63) : scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aligned
                        ? tr('اتجاه القبلة صحيح', 'Qibla aligned')
                        : tr('القبلة', 'Qibla'),
                    style: TextStyle(
                      color: aligned ? Colors.white : scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _qiblaDirectionText(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: aligned
                          ? Colors.white.withValues(alpha: .78)
                          : scheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: aligned
                  ? const Color(0xFFE2BD63)
                  : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernQuickTiles(ColorScheme scheme) {
    final items = [
      (
        Icons.notifications_active_rounded,
        tr('الأذان', 'Adhan'),
        () => _showAdhanSettings(),
      ),
      (
        Icons.explore_rounded,
        tr('القبلة', 'Qibla'),
        () => _goToSection(2),
      ),
      (
        Icons.check_circle_rounded,
        tr('يومي في صلاتي', 'My Day'),
        () => _showMyDayFocus(scheme),
      ),
      (
        Icons.menu_book_rounded,
        tr('المصحف الشريف', 'Holy Quran'),
        () => _goToSection(4),
      ),
      (
        Icons.location_on_rounded,
        tr('الموقع', 'Location'),
        () => _getLocation(),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 2.45,
      ),
      itemBuilder: (context, index) {
        final item = items[index];

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: item.$3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Row(
              children: [
                Icon(item.$1, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMyDayFocus(ColorScheme scheme) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildMyDayCard(_calculateTimes(), scheme),
                  const SizedBox(height: 10),
                  _buildWeeklyPrayerCard(scheme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernPrayerPage(
    Map<String, DateTime> times,
    MapEntry<String, DateTime>? next,
    ColorScheme scheme,
  ) {
    return _modernPageScroll(
      children: [
        _buildModernNextPrayer(next, scheme),
        const SizedBox(height: 12),
        _buildPrayerHeader(scheme),
        const SizedBox(height: 8),
        if (_position == null)
          _buildNoLocationCard(scheme)
        else
          ..._prayerKeys.map((key) {
            final time = times[key];
            if (time == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _buildPrayerCard(
                key,
                time,
                times,
                next?.key == key,
                scheme,
              ),
            );
          }),
        const SizedBox(height: 6),
        _buildLocationCard(scheme),
      ],
    );
  }

  Widget _buildModernQiblaPage(ColorScheme scheme) {
    return _modernPageScroll(
      children: [
        _buildQiblaSectionHeader(scheme),
        const SizedBox(height: 8),
        _buildQiblaCompass(scheme),
        const SizedBox(height: 12),
        _buildQiblaModernInfoCard(scheme),
      ],
    );
  }

  Widget _buildQiblaModernInfoCard(ColorScheme scheme) {
    final relative = _qiblaRelativeAngle;
    final accuracy = _compassAccuracy;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2BD63).withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Color(0xFF9A7325),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('حالة البوصلة', 'Compass status'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      accuracy == null
                          ? tr(
                              'جاري قراءة حساس الهاتف',
                              'Reading the phone sensor',
                            )
                          : accuracy.abs() <= 5
                              ? tr('جودة ممتازة', 'Excellent quality')
                              : tr('تحتاج إلى معايرة', 'Calibration recommended'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (relative != null)
                Text(
                  '${relative.abs().round()}°',
                  style: const TextStyle(
                    color: Color(0xFF9A7325),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showQiblaSettingsSheet(scheme),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(tr('إعدادات القبلة', 'Qibla settings')),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerLinkedAdhkarCard(
    Map<String, DateTime> times,
    ColorScheme scheme,
  ) {
    final now = _now;
    final next = _nextPrayer(times);

    int suggestedCategory = 2;
    String arTitle = 'ورد مرتبط بالصلاة';
    String enTitle = 'Prayer-linked remembrance';
    String arSubtitle = 'يختار لك الذكر المناسب حسب وقت اليوم';
    String enSubtitle = 'The app suggests the suitable remembrance for this time';
    IconData icon = Icons.access_time_rounded;

    final fajr = times['fajr'];
    final dhuhr = times['dhuhr'];
    final asr = times['asr'];
    final maghrib = times['maghrib'];
    final isha = times['isha'];

    if (fajr != null && now.isAfter(fajr) && dhuhr != null && now.isBefore(dhuhr)) {
      suggestedCategory = 0;
      arTitle = 'حان وقت أذكار الصباح';
      enTitle = 'Morning adhkar time';
      arSubtitle = 'بعد الفجر إلى ما قبل الظهر';
      enSubtitle = 'From Fajr until before Dhuhr';
      icon = Icons.wb_sunny_rounded;
    } else if (asr != null && now.isAfter(asr) && maghrib != null && now.isBefore(maghrib)) {
      suggestedCategory = 1;
      arTitle = 'حان وقت أذكار المساء';
      enTitle = 'Evening adhkar time';
      arSubtitle = 'نافذة مناسبة لورد المساء';
      enSubtitle = 'A suitable window for evening remembrance';
      icon = Icons.nightlight_round;
    } else if (isha != null && now.isAfter(isha)) {
      suggestedCategory = 3;
      arTitle = 'ورد ما قبل النوم';
      enTitle = 'Before-sleep remembrance';
      arSubtitle = 'يمكنك بدء أذكار النوم الآن';
      enSubtitle = 'You can start your sleep adhkar now';
      icon = Icons.bedtime_rounded;
    } else if (next != null) {
      arTitle = 'الورد التالي: بعد ${prayerName(next.key)}';
      enTitle = 'Next: after ${prayerName(next.key)}';
      arSubtitle = 'افتح أذكار ما بعد الصلاة بعد أداء الصلاة';
      enSubtitle = 'Open after-prayer adhkar after completing the prayer';
      icon = _prayerIcon(next.key);
    }

    final nextText = next == null
        ? tr('مواقيت الصلاة غير متاحة', 'Prayer times are unavailable')
        : tr(
            'الصلاة القادمة: ${prayerName(next.key)} • ${_formatTime(next.value)}',
            'Next prayer: ${prayerName(next.key)} • ${_formatTime(next.value)}',
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: .07),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF176B52), Color(0xFF0D4939)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFFE2BD63), size: 27),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(arTitle, enTitle),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(arSubtitle, enSubtitle),
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextText,
                      style: TextStyle(fontSize: 10.5, color: scheme.primary, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => _showDhikrCategorySheet(suggestedCategory, scheme),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(tr('فتح', 'Open')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 17, color: scheme.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    tr(
                      'الفجر ← أذكار الصباح  •  كل صلاة ← أذكار ما بعد الصلاة  •  العصر/المغرب ← أذكار المساء  •  العشاء ← أذكار النوم',
                      'Fajr → morning  •  each prayer → after-prayer  •  Asr/Maghrib → evening  •  Isha → sleep',
                    ),
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernAdhkarPage(ColorScheme scheme) {
    final categories = <({
      IconData icon,
      String ar,
      String en,
      String subAr,
      String subEn,
      int count,
    })>[
      (icon: Icons.wb_sunny_rounded, ar: 'أذكار الصباح', en: 'Morning adhkar', subAr: 'ورد بداية اليوم المأثور', subEn: 'Authentic morning remembrance', count: 10),
      (icon: Icons.nightlight_round, ar: 'أذكار المساء', en: 'Evening adhkar', subAr: 'ورد نهاية اليوم المأثور', subEn: 'Authentic evening remembrance', count: 10),
      (icon: Icons.favorite_rounded, ar: 'أذكار بعد الصلاة', en: 'After-prayer adhkar', subAr: 'أذكار ما بعد الصلوات', subEn: 'Remembrance after prayer', count: 8),
      (icon: Icons.bedtime_rounded, ar: 'أذكار النوم', en: 'Sleep adhkar', subAr: 'ورد ما قبل النوم', subEn: 'Before-sleep remembrance', count: 7),
      (icon: Icons.wb_twilight_rounded, ar: 'أذكار الاستيقاظ', en: 'Waking adhkar', subAr: 'ما يقال عند الاستيقاظ', subEn: 'Remembrance upon waking', count: 4),
      (icon: Icons.menu_book_rounded, ar: 'أدعية القرآن', en: 'Quranic duas', subAr: 'أدعية ثابتة من القرآن الكريم', subEn: 'Supplications from the Quran', count: 10),
      (icon: Icons.home_rounded, ar: 'أذكار المنزل', en: 'Home adhkar', subAr: 'الدخول والخروج والمنزل', subEn: 'Entering and leaving home', count: 6),
      (icon: Icons.mosque_rounded, ar: 'أذكار المسجد', en: 'Masjid adhkar', subAr: 'الدخول والخروج والصلاة', subEn: 'Masjid remembrance', count: 6),
      (icon: Icons.directions_car_rounded, ar: 'أذكار السفر', en: 'Travel adhkar', subAr: 'السفر والركوب والعودة', subEn: 'Travel and riding remembrance', count: 7),
      (icon: Icons.restaurant_rounded, ar: 'أذكار الطعام والشراب', en: 'Food & drink', subAr: 'قبل الطعام وبعده', subEn: 'Before and after eating', count: 6),
      (icon: Icons.water_drop_rounded, ar: 'أذكار الوضوء', en: 'Wudu adhkar', subAr: 'قبل الوضوء وبعده', subEn: 'Before and after ablution', count: 4),
      (icon: Icons.checkroom_rounded, ar: 'أذكار اللباس', en: 'Clothing adhkar', subAr: 'لبس الثوب وخلعه', subEn: 'Clothing remembrance', count: 4),
      (icon: Icons.cloud_rounded, ar: 'أذكار المطر والطقس', en: 'Rain & weather', subAr: 'المطر والرعد والريح', subEn: 'Rain, thunder and wind', count: 7),
      (icon: Icons.healing_rounded, ar: 'أذكار المرض والهم', en: 'Illness & distress', subAr: 'للكرب والمرض والهم', subEn: 'For illness, worry and distress', count: 8),
      (icon: Icons.family_restroom_rounded, ar: 'أدعية الأسرة والوالدين', en: 'Family & parents', subAr: 'للوالدين والأهل والذرية', subEn: 'For parents, family and children', count: 8),
      (icon: Icons.auto_awesome_rounded, ar: 'أذكار متنوعة', en: 'General adhkar', subAr: 'استغفار وتسبيح وتهليل وحوقلة', subEn: 'Istighfar, tasbih and general dhikr', count: 12),
    ];

    return _modernPageScroll(
      children: [
        _buildSectionTitle(
          tr('الأذكار والأدعية', 'Adhkar & Duas'),
          tr(
            'مكتبة واسعة مرتبة حسب الوقت والموقف مع عدّاد تفاعلي',
            'A large library organized by time and situation with an interactive counter',
          ),
          Icons.menu_book_rounded,
          scheme,
        ),
        const SizedBox(height: 6),
        _buildPrayerLinkedAdhkarCard(_calculateTimes(), scheme),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF176B52), Color(0xFF0D4939)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2BD63).withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFE2BD63), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('وردك اليومي', 'Your daily wird'),
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('ابدأ بأذكار الصباح أو اختر أي قسم يناسبك.', 'Start with morning adhkar or choose any section.'),
                      style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showDhikrCategorySheet(0, scheme),
                color: const Color(0xFFE2BD63),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 31),
                tooltip: tr('ابدأ', 'Start'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...categories.asMap().entries.map(
          (entry) {
            final item = entry.value;
            final index = entry.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _showDhikrCategorySheet(index, scheme),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .035),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          gradient: const LinearGradient(colors: [Color(0xFF176B52), Color(0xFF0D4939)]),
                        ),
                        child: Icon(item.icon, color: const Color(0xFFE2BD63), size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.ar, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(
                              _arabic ? item.subAr : item.subEn,
                              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr('${item.count} أذكار متاحة', '${item.count} adhkar available'),
                              style: TextStyle(fontSize: 10, color: scheme.primary, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      Icon(_arabic ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        _buildModernQuoteCard(scheme),
      ],
    );
  }

  List<({String title, String text, int count, String source})> _dhikrItemsForCategory(int index) {
    switch (index) {
      case 0:
        return [
          (title: 'أصبحنا وأصبح الملك لله', text: 'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ، رَبِّ أَسْأَلُكَ خَيْرَ مَا فِي هَذَا الْيَوْمِ وَخَيْرَ مَا بَعْدَهُ، وَأَعُوذُ بِكَ مِنْ شَرِّ مَا فِي هَذَا الْيَوْمِ وَشَرِّ مَا بَعْدَهُ.', count: 1, source: 'صحيح مسلم 2723'),
          (title: 'اللهم بك أصبحنا', text: 'اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ.', count: 1, source: 'أبو داود والترمذي'),
          (title: 'سيد الاستغفار', text: 'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي، فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ.', count: 1, source: 'صحيح البخاري'),
          (title: 'رضيت بالله ربًا', text: 'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ صَلَّى اللَّهُ عَلَيْهِ وَسَلَّمَ نَبِيًّا.', count: 3, source: 'أبو داود والترمذي'),
          (title: 'حسبي الله', text: 'حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ، عَلَيْهِ تَوَكَّلْتُ، وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ.', count: 7, source: 'أبو داود'),
          (title: 'سبحان الله وبحمده', text: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ.', count: 100, source: 'صحيح مسلم'),
        ];
      case 1:
        return [
          (title: 'أمسينا وأمسى الملك لله', text: 'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ، رَبِّ أَسْأَلُكَ خَيْرَ مَا فِي هَذِهِ اللَّيْلَةِ وَخَيْرَ مَا بَعْدَهَا، وَأَعُوذُ بِكَ مِنْ شَرِّ مَا فِي هَذِهِ اللَّيْلَةِ وَشَرِّ مَا بَعْدَهَا.', count: 1, source: 'صحيح مسلم 2723'),
          (title: 'اللهم بك أمسينا', text: 'اللَّهُمَّ بِكَ أَمْسَيْنَا، وَبِكَ أَصْبَحْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ الْمَصِيرُ.', count: 1, source: 'أبو داود والترمذي'),
          (title: 'سيد الاستغفار', text: 'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي، فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ.', count: 1, source: 'صحيح البخاري'),
          (title: 'المعوذات', text: 'قُلْ هُوَ اللَّهُ أَحَدٌ، قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ، قُلْ أَعُوذُ بِرَبِّ النَّاسِ.', count: 3, source: 'أبو داود والترمذي'),
          (title: 'آية الكرسي', text: 'اللَّهُ لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ، لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ... لَهُ الْعَلِيُّ الْعَظِيمُ.', count: 1, source: 'البقرة: 255'),
        ];
      case 2:
        return [
          (title: 'الاستغفار بعد الصلاة', text: 'أَسْتَغْفِرُ اللَّهَ، أَسْتَغْفِرُ اللَّهَ، أَسْتَغْفِرُ اللَّهَ، اللَّهُمَّ أَنْتَ السَّلَامُ، وَمِنْكَ السَّلَامُ، تَبَارَكْتَ يَا ذَا الْجَلَالِ وَالْإِكْرَامِ.', count: 1, source: 'صحيح مسلم 591'),
          (title: 'لا إله إلا الله', text: 'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ.', count: 3, source: 'البخاري ومسلم'),
          (title: 'التسبيح والتحميد والتكبير', text: 'سُبْحَانَ اللَّهِ، وَالْحَمْدُ لِلَّهِ، وَاللَّهُ أَكْبَرُ.', count: 33, source: 'البخاري ومسلم'),
          (title: 'ختام الذكر بعد الصلاة', text: 'لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ، اللَّهُمَّ لَا مَانِعَ لِمَا أَعْطَيْتَ، وَلَا مُعْطِيَ لِمَا مَنَعْتَ، وَلَا يَنْفَعُ ذَا الْجَدِّ مِنْكَ الْجَدُّ.', count: 1, source: 'البخاري ومسلم'),
          (title: 'آية الكرسي', text: 'اللَّهُ لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ، لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ... وَهُوَ الْعَلِيُّ الْعَظِيمُ.', count: 1, source: 'البقرة: 255'),
        ];
      case 3:
        return [
          (title: 'باسمك اللهم أموت وأحيا', text: 'بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا.', count: 1, source: 'صحيح البخاري ومسلم'),
          (title: 'آية الكرسي', text: 'اللَّهُ لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ، لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ... وَهُوَ الْعَلِيُّ الْعَظِيمُ.', count: 1, source: 'البقرة: 255'),
          (title: 'الإخلاص والفلق والناس', text: 'قُلْ هُوَ اللَّهُ أَحَدٌ، قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ، قُلْ أَعُوذُ بِرَبِّ النَّاسِ.', count: 3, source: 'السنة النبوية'),
          (title: 'آخر آيتين من البقرة', text: 'آمَنَ الرَّسُولُ بِمَا أُنْزِلَ إِلَيْهِ مِنْ رَبِّهِ... لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا.', count: 1, source: 'البقرة: 285-286'),
          (title: 'التسبيح قبل النوم', text: 'سُبْحَانَ اللَّهِ، وَالْحَمْدُ لِلَّهِ، وَاللَّهُ أَكْبَرُ.', count: 33, source: 'صحيح البخاري ومسلم'),
        ];
      case 4:
        return [
          (title: 'الحمد لله الذي أحيانا', text: 'الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ.', count: 1, source: 'صحيح البخاري'),
          (title: 'غفرانك', text: 'الْحَمْدُ لِلَّهِ الَّذِي عَافَانِي فِي جَسَدِي، وَرَدَّ عَلَيَّ رُوحِي، وَأَذِنَ لِي بِذِكْرِهِ.', count: 1, source: 'الترمذي'),
          (title: 'الحمد لله', text: 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ.', count: 1, source: 'ذكر مشروع'),
        ];
      case 5:
        return [
          (title: 'ربنا آتنا في الدنيا حسنة', text: 'رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ.', count: 1, source: 'البقرة: 201'),
          (title: 'رب اشرح لي صدري', text: 'رَبِّ اشْرَحْ لِي صَدْرِي، وَيَسِّرْ لِي أَمْرِي، وَاحْلُلْ عُقْدَةً مِنْ لِسَانِي، يَفْقَهُوا قَوْلِي.', count: 1, source: 'طه: 25-28'),
          (title: 'رب زدني علمًا', text: 'وَقُلْ رَبِّ زِدْنِي عِلْمًا.', count: 1, source: 'طه: 114'),
          (title: 'ربنا لا تزغ قلوبنا', text: 'رَبَّنَا لَا تُزِغْ قُلُوبَنَا بَعْدَ إِذْ هَدَيْتَنَا وَهَبْ لَنَا مِنْ لَدُنْكَ رَحْمَةً إِنَّكَ أَنْتَ الْوَهَّابُ.', count: 1, source: 'آل عمران: 8'),
          (title: 'ربنا هب لنا من أزواجنا', text: 'رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا.', count: 1, source: 'الفرقان: 74'),
          (title: 'رب اغفر لي ولوالدي', text: 'رَبِّ اغْفِرْ لِي وَلِوَالِدَيَّ وَلِلْمُؤْمِنِينَ يَوْمَ يَقُومُ الْحِسَابُ.', count: 1, source: 'إبراهيم: 41'),
          (title: 'ربنا أفرغ علينا صبرًا', text: 'رَبَّنَا أَفْرِغْ عَلَيْنَا صَبْرًا وَتَوَفَّنَا مُسْلِمِينَ.', count: 1, source: 'الأعراف: 126'),
          (title: 'لا إله إلا أنت سبحانك', text: 'لَا إِلَهَ إِلَّا أَنْتَ سُبْحَانَكَ إِنِّي كُنْتُ مِنَ الظَّالِمِينَ.', count: 1, source: 'الأنبياء: 87'),
        ];
      case 6:
        return [
          (title: 'دخول المنزل', text: 'بِسْمِ اللَّهِ وَلَجْنَا، وَبِسْمِ اللَّهِ خَرَجْنَا، وَعَلَى اللَّهِ رَبِّنَا تَوَكَّلْنَا.', count: 1, source: 'أبو داود'),
          (title: 'الخروج من المنزل', text: 'بِسْمِ اللَّهِ، تَوَكَّلْتُ عَلَى اللَّهِ، وَلَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ.', count: 1, source: 'أبو داود والترمذي'),
          (title: 'البركة في البيت', text: 'السَّلَامُ عَلَيْكُمْ وَرَحْمَةُ اللَّهِ وَبَرَكَاتُهُ.', count: 1, source: 'آداب السلام'),
          (title: 'عند رؤية ما يعجب', text: 'مَا شَاءَ اللَّهُ، لَا قُوَّةَ إِلَّا بِاللَّهِ.', count: 1, source: 'الكهف: 39'),
        ];
      case 7:
        return [
          (title: 'دخول المسجد', text: 'اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ.', count: 1, source: 'صحيح مسلم'),
          (title: 'الخروج من المسجد', text: 'اللَّهُمَّ إِنِّي أَسْأَلُكَ مِنْ فَضْلِكَ.', count: 1, source: 'صحيح مسلم'),
          (title: 'بين السجدتين', text: 'رَبِّ اغْفِرْ لِي، رَبِّ اغْفِرْ لِي.', count: 1, source: 'أبو داود'),
          (title: 'بعد الأذان', text: 'اللَّهُمَّ رَبَّ هَذِهِ الدَّعْوَةِ التَّامَّةِ وَالصَّلَاةِ الْقَائِمَةِ، آتِ مُحَمَّدًا الْوَسِيلَةَ وَالْفَضِيلَةَ، وَابْعَثْهُ مَقَامًا مَحْمُودًا الَّذِي وَعَدْتَهُ.', count: 1, source: 'صحيح البخاري'),
        ];
      case 8:
        return [
          (title: 'دعاء الركوب', text: 'سُبْحَانَ الَّذِي سَخَّرَ لَنَا هَذَا وَمَا كُنَّا لَهُ مُقْرِنِينَ، وَإِنَّا إِلَى رَبِّنَا لَمُنْقَلِبُونَ.', count: 1, source: 'الزخرف: 13-14'),
          (title: 'دعاء السفر', text: 'اللَّهُمَّ إِنَّا نَسْأَلُكَ فِي سَفَرِنَا هَذَا الْبِرَّ وَالتَّقْوَى، وَمِنَ الْعَمَلِ مَا تَرْضَى.', count: 1, source: 'صحيح مسلم'),
          (title: 'تكملة دعاء السفر', text: 'اللَّهُمَّ هَوِّنْ عَلَيْنَا سَفَرَنَا هَذَا وَاطْوِ عَنَّا بُعْدَهُ، اللَّهُمَّ أَنْتَ الصَّاحِبُ فِي السَّفَرِ وَالْخَلِيفَةُ فِي الْأَهْلِ.', count: 1, source: 'صحيح مسلم'),
          (title: 'عند النزول في مكان', text: 'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ.', count: 1, source: 'صحيح مسلم'),
          (title: 'عند الرجوع', text: 'آيِبُونَ، تَائِبُونَ، عَابِدُونَ، لِرَبِّنَا حَامِدُونَ.', count: 1, source: 'صحيح البخاري ومسلم'),
        ];
      case 9:
        return [
          (title: 'قبل الطعام', text: 'بِسْمِ اللَّهِ.', count: 1, source: 'صحيح البخاري ومسلم'),
          (title: 'نسي التسمية', text: 'بِسْمِ اللَّهِ فِي أَوَّلِهِ وَآخِرِهِ.', count: 1, source: 'أبو داود والترمذي'),
          (title: 'بعد الطعام', text: 'الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنِي هَذَا وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ.', count: 1, source: 'أبو داود والترمذي'),
          (title: 'حمد الله بعد الطعام', text: 'الْحَمْدُ لِلَّهِ حَمْدًا كَثِيرًا طَيِّبًا مُبَارَكًا فِيهِ، غَيْرَ مَكْفِيٍّ وَلَا مُوَدَّعٍ وَلَا مُسْتَغْنًى عَنْهُ رَبَّنَا.', count: 1, source: 'صحيح البخاري'),
        ];
      case 10:
        return [
          (title: 'قبل الوضوء', text: 'بِسْمِ اللَّهِ.', count: 1, source: 'أبو داود'),
          (title: 'بعد الوضوء', text: 'أَشْهَدُ أَنْ لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ.', count: 1, source: 'صحيح مسلم'),
          (title: 'زيادة بعد الوضوء', text: 'اللَّهُمَّ اجْعَلْنِي مِنَ التَّوَّابِينَ، وَاجْعَلْنِي مِنَ الْمُتَطَهِّرِينَ.', count: 1, source: 'الترمذي'),
        ];
      case 11:
        return [
          (title: 'لبس الثوب', text: 'الْحَمْدُ لِلَّهِ الَّذِي كَسَانِي هَذَا الثَّوْبَ وَرَزَقَنِيهِ مِنْ غَيْرِ حَوْلٍ مِنِّي وَلَا قُوَّةٍ.', count: 1, source: 'أبو داود والترمذي'),
          (title: 'لبس الجديد', text: 'اللَّهُمَّ لَكَ الْحَمْدُ أَنْتَ كَسَوْتَنِيهِ، أَسْأَلُكَ خَيْرَهُ وَخَيْرَ مَا صُنِعَ لَهُ، وَأَعُوذُ بِكَ مِنْ شَرِّهِ وَشَرِّ مَا صُنِعَ لَهُ.', count: 1, source: 'أبو داود والترمذي'),
          (title: 'خلع الثوب', text: 'بِسْمِ اللَّهِ.', count: 1, source: 'الترمذي'),
        ];
      case 12:
        return [
          (title: 'عند نزول المطر', text: 'اللَّهُمَّ صَيِّبًا نَافِعًا.', count: 1, source: 'صحيح البخاري'),
          (title: 'بعد نزول المطر', text: 'مُطِرْنَا بِفَضْلِ اللَّهِ وَرَحْمَتِهِ.', count: 1, source: 'صحيح البخاري ومسلم'),
          (title: 'عند سماع الرعد', text: 'سُبْحَانَ الَّذِي يُسَبِّحُ الرَّعْدُ بِحَمْدِهِ وَالْمَلَائِكَةُ مِنْ خِيفَتِهِ.', count: 1, source: 'أثر عن عبد الله بن الزبير'),
          (title: 'عند اشتداد الريح', text: 'اللَّهُمَّ إِنِّي أَسْأَلُكَ خَيْرَهَا، وَخَيْرَ مَا فِيهَا، وَخَيْرَ مَا أُرْسِلَتْ بِهِ، وَأَعُوذُ بِكَ مِنْ شَرِّهَا وَشَرِّ مَا فِيهَا وَشَرِّ مَا أُرْسِلَتْ بِهِ.', count: 1, source: 'صحيح مسلم'),
        ];
      case 13:
        return [
          (title: 'دعاء الكرب', text: 'لَا إِلَهَ إِلَّا اللَّهُ الْعَظِيمُ الْحَلِيمُ، لَا إِلَهَ إِلَّا اللَّهُ رَبُّ الْعَرْشِ الْعَظِيمِ، لَا إِلَهَ إِلَّا اللَّهُ رَبُّ السَّمَاوَاتِ وَرَبُّ الْأَرْضِ وَرَبُّ الْعَرْشِ الْكَرِيمِ.', count: 1, source: 'صحيح البخاري ومسلم'),
          (title: 'دعاء يونس', text: 'لَا إِلَهَ إِلَّا أَنْتَ سُبْحَانَكَ إِنِّي كُنْتُ مِنَ الظَّالِمِينَ.', count: 1, source: 'الأنبياء: 87'),
          (title: 'عند الهم والحزن', text: 'اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْهَمِّ وَالْحَزَنِ، وَأَعُوذُ بِكَ مِنَ الْعَجْزِ وَالْكَسَلِ، وَأَعُوذُ بِكَ مِنَ الْجُبْنِ وَالْبُخْلِ، وَأَعُوذُ بِكَ مِنْ غَلَبَةِ الدَّيْنِ وَقَهْرِ الرِّجَالِ.', count: 1, source: 'صحيح البخاري'),
          (title: 'للمريض', text: 'أَسْأَلُ اللَّهَ الْعَظِيمَ رَبَّ الْعَرْشِ الْعَظِيمِ أَنْ يَشْفِيَكَ.', count: 7, source: 'أبو داود والترمذي'),
          (title: 'دعاء الشفاء', text: 'اللَّهُمَّ رَبَّ النَّاسِ، أَذْهِبِ الْبَأْسَ، اشْفِ أَنْتَ الشَّافِي، لَا شِفَاءَ إِلَّا شِفَاؤُكَ، شِفَاءً لَا يُغَادِرُ سَقَمًا.', count: 1, source: 'صحيح البخاري ومسلم'),
        ];
      case 14:
        return [
          (title: 'للوالدين', text: 'رَبِّ ارْحَمْهُمَا كَمَا رَبَّيَانِي صَغِيرًا.', count: 1, source: 'الإسراء: 24'),
          (title: 'للذرية', text: 'رَبِّ هَبْ لِي مِنْ لَدُنْكَ ذُرِّيَّةً طَيِّبَةً إِنَّكَ سَمِيعُ الدُّعَاءِ.', count: 1, source: 'آل عمران: 38'),
          (title: 'للأسرة', text: 'رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا.', count: 1, source: 'الفرقان: 74'),
          (title: 'للمغفرة', text: 'رَبَّنَا اغْفِرْ لَنَا وَلِإِخْوَانِنَا الَّذِينَ سَبَقُونَا بِالْإِيمَانِ.', count: 1, source: 'الحشر: 10'),
          (title: 'للرزق الحلال', text: 'رَبِّ إِنِّي لِمَا أَنْزَلْتَ إِلَيَّ مِنْ خَيْرٍ فَقِيرٌ.', count: 1, source: 'القصص: 24'),
        ];
      default:
        return [
          (title: 'سبحان الله وبحمده', text: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ.', count: 100, source: 'صحيح البخاري ومسلم'),
          (title: 'سبحان الله العظيم', text: 'سُبْحَانَ اللَّهِ الْعَظِيمِ.', count: 100, source: 'ذكر مشروع'),
          (title: 'لا إله إلا الله', text: 'لَا إِلَهَ إِلَّا اللَّهُ.', count: 100, source: 'ذكر عظيم'),
          (title: 'الله أكبر', text: 'اللَّهُ أَكْبَرُ.', count: 100, source: 'ذكر مشروع'),
          (title: 'الحمد لله', text: 'الْحَمْدُ لِلَّهِ.', count: 100, source: 'ذكر مشروع'),
          (title: 'أستغفر الله', text: 'أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْهِ.', count: 100, source: 'صحيح البخاري ومسلم'),
          (title: 'لا حول ولا قوة إلا بالله', text: 'لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ.', count: 100, source: 'صحيح البخاري ومسلم'),
          (title: 'الصلاة على النبي ﷺ', text: 'اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى نَبِيِّنَا مُحَمَّدٍ.', count: 10, source: 'ذكر مشروع'),
        ];
    }
  }

  Future<void> _showDhikrCategorySheet(int index, ColorScheme scheme) async {
    final items = _dhikrItemsForCategory(index);
    if (items.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final progress = List<int>.filled(items.length, 0);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.sizeOf(context).height * .90,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(width: 42, height: 5, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(8))),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(15)),
                            child: Icon(Icons.menu_book_rounded, color: scheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _dhikrCategoryTitle(index),
                                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  tr('${items.length} أذكار • اضغط تم للتقدم', '${items.length} adhkar • tap Done to progress'),
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final done = progress[i] >= item.count;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: done ? scheme.primaryContainer.withValues(alpha: .45) : scheme.surface,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: done ? scheme.primary.withValues(alpha: .45) : scheme.outlineVariant.withValues(alpha: .45)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                                      child: Text('${progress[i]}/${item.count}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 11)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(item.text, textAlign: TextAlign.right, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 17, height: 1.9, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 9),
                                Text(item.source, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 11),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: done ? null : () => setSheetState(() => progress[i]++),
                                        icon: Icon(done ? Icons.check_circle_rounded : Icons.touch_app_rounded, size: 18),
                                        label: Text(done ? tr('تم الذكر', 'Completed') : tr('تم', 'Done')),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: tr('إعادة العداد', 'Reset counter'),
                                      onPressed: progress[i] == 0 ? null : () => setSheetState(() => progress[i] = 0),
                                      icon: const Icon(Icons.refresh_rounded),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _dhikrCategoryTitle(int index) {
    const ar = [
      'أذكار الصباح', 'أذكار المساء', 'أذكار بعد الصلاة', 'أذكار النوم',
      'أذكار الاستيقاظ', 'أدعية القرآن', 'أذكار المنزل', 'أذكار المسجد',
      'أذكار السفر', 'أذكار الطعام والشراب', 'أذكار الوضوء', 'أذكار اللباس',
      'أذكار المطر والطقس', 'أذكار المرض والهم', 'أدعية الأسرة والوالدين', 'أذكار متنوعة',
    ];
    const en = [
      'Morning adhkar', 'Evening adhkar', 'After-prayer adhkar', 'Sleep adhkar',
      'Waking adhkar', 'Quranic duas', 'Home adhkar', 'Masjid adhkar',
      'Travel adhkar', 'Food & drink', 'Wudu adhkar', 'Clothing adhkar',
      'Rain & weather', 'Illness & distress', 'Family & parents', 'General adhkar',
    ];
    return _arabic ? ar[index] : en[index];
  }


  // ============================================================
  // QURAN SECTION
  // ============================================================

  Widget _buildQuranMiniPlayer() {
    return ValueListenableBuilder<_QuranPlaybackInfo?>(
      valueListenable: _quranPlaybackInfo,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.bottomCenter,
          child: StreamBuilder<ja.PlayerState>(
            stream: _quranBackgroundPlayer.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final playing = state?.playing ?? _quranBackgroundPlayer.playing;
              final busy = state?.processingState == ja.ProcessingState.loading ||
                  state?.processingState == ja.ProcessingState.buffering;
              return SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .16),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: scheme.primaryContainer,
                        child: Icon(Icons.menu_book_rounded, color: scheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.surahName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              info.reciterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: playing ? 'إيقاف مؤقت' : 'متابعة',
                        onPressed: busy
                            ? null
                            : () async {
                                if (_quranBackgroundPlayer.playing) {
                                  await _quranBackgroundPlayer.pause();
                                } else {
                                  await _quranBackgroundPlayer.play();
                                }
                              },
                        icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                        iconSize: 34,
                      ),
                      IconButton(
                        tooltip: 'إيقاف نهائي',
                        onPressed: () async {
                          await _quranBackgroundPlayer.stop();
                          _quranStopSignal.value++;
                          _quranPlaybackInfo.value = null;
                        },
                        icon: const Icon(Icons.stop_circle_rounded),
                        iconSize: 30,
                      ),
                      IconButton(
                        tooltip: 'إغلاق المشغل',
                        onPressed: () async {
                          await _quranBackgroundPlayer.stop();
                          _quranStopSignal.value++;
                          _quranPlaybackInfo.value = null;
                        },
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 24,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildModernQuranCard(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _goToSection(4),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF176B52),
              Color(0xFF0D4939),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF176B52).withValues(alpha: .16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: const Color(0xFFE2BD63).withValues(alpha: .55),
                ),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: Color(0xFFE2BD63),
                size: 29,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    _arabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('المصحف الشريف', 'Holy Quran'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'قراءة المصحف برواية حفص • ٦٠٤ صفحات',
                      'Hafs Mushaf • 604 pages',
                    ),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .76),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _arabic
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              color: const Color(0xFFE2BD63),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernQuranPage(ColorScheme scheme) {
    return SalatiQuranReader(
      darkMode: widget.darkMode,
      onThemeChanged: widget.onThemeChanged,
    );
  }

  Widget _buildModernSettingsPage(ColorScheme scheme) {
    final items = [
      (
        Icons.notifications_active_rounded,
        tr('الأذان والتنبيهات', 'Adhan & notifications'),
        tr(
          'إعدادات الأذان والصوت والتنبيهات',
          'Adhan, sound and notification settings',
        ),
        _showAdhanSettings,
      ),
      (
        Icons.explore_rounded,
        tr('إعدادات القبلة', 'Qibla settings'),
        tr('الصوت والاهتزاز ودقة الوصول', 'Sound, vibration and tolerance'),
        () => _showQiblaSettingsSheet(scheme),
      ),
      (
        Icons.location_on_rounded,
        tr('الموقع', 'Location'),
        tr('تحديث الموقع وتحديد المدينة', 'Update location and city'),
        _getLocation,
      ),
      (
        Icons.tune_rounded,
        tr('الإعدادات العامة', 'General settings'),
        tr(
          'اللغة والمظهر وطريقة الحساب وضبط المواقيت',
          'Language, theme, calculation and prayer adjustments',
        ),
        _showSettings,
      ),
    ];

    return _modernPageScroll(
      children: [
        _buildSectionTitle(
          tr('الإعدادات', 'Settings'),
          tr(
            'كل إعدادات التطبيق في مكان واحد',
            'All app settings in one place',
          ),
          Icons.settings_rounded,
          scheme,
        ),
        const SizedBox(height: 2),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: item.$4,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .45),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(item.$1, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$2,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.$3,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _arabic
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildModernQuoteCard(scheme),
      ],
    );
  }

  Widget _buildModernQuoteCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF176B52), Color(0xFF0D4939)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFFE2BD63),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('صلاتك نور يومك', 'Let prayer illuminate your day'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
    String subtitle,
    IconData icon,
    ColorScheme scheme,
  ) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF176B52),
                Color(0xFF0D4939),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFE2BD63),
            size: 24,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // QIBLA SECTION HEADER
  // ============================================================

  Widget _buildQiblaSectionHeader(
    ColorScheme scheme,
  ) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.explore_rounded,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'اتجاه القبلة',
                  'Qibla direction',
                ),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                tr(
                  'بوصلة مستقلة لتحديد اتجاه مكة من موقعك',
                  'Independent compass for the direction of Makkah',
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // QIBLA COMPASS CARD
  // ============================================================

  Widget _buildQiblaCompass(
    ColorScheme scheme,
  ) {
    final qibla =
        _calculateQiblaBearing();

    final heading =
        _trueHeading;

    final relative =
        _qiblaRelativeAngle;

    final hasLocation =
        _position != null;

    final compassReady =
        heading != null &&
        relative != null;

    String accuracyText;

    if (_compassAccuracy == null) {
      accuracyText = tr(
        'جاري معايرة البوصلة',
        'Compass is calibrating',
      );
    } else {
      final accuracy =
          _compassAccuracy!
              .abs()
              .round();

      if (accuracy <= 5) {
        accuracyText = tr(
          'دقة جيدة ±$accuracy°',
          'Good accuracy ±$accuracy°',
        );
      } else {
        accuracyText = tr(
          'تحتاج البوصلة إلى معايرة ±$accuracy°',
          'Compass needs calibration ±$accuracy°',
        );
      }
    }

    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        18,
        20,
        18,
        18,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius:
            BorderRadius.circular(26),
        border: Border.all(
          color: scheme.outlineVariant
              .withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: 0.04),
            blurRadius: 18,
            offset:
                const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color:
                      scheme.primaryContainer,
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                ),
                child: Icon(
                  Icons.explore_rounded,
                  color:
                      scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'اتجاه القبلة',
                        'Qibla direction',
                      ),
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(
                        'تحديد القبلة بواسطة GPS وحساس اتجاه الهاتف',
                        'GPS and phone heading based Qibla',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          if (!hasLocation)
            _buildQiblaLocationRequired(
              scheme,
            )
          else
            Column(
              children: [
                SizedBox(
                  width: 285,
                  height: 285,
                  child: Stack(
                    alignment:
                        Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(
                          285,
                          285,
                        ),
                        painter:
                            _QiblaCompassPainter(
                          scheme: scheme,
                        ),
                      ),

                      if (compassReady)
                        Transform.rotate(
                          angle:
                              relative! *
                                  math.pi /
                                  180,
                          child: CustomPaint(
                            size:
                                const Size(
                              285,
                              285,
                            ),
                            painter:
                                _QiblaPointerPainter(
                              color: _qiblaAligned
                                  ? Colors.green.shade600
                                  : scheme.primary,
                            ),
                          ),
                        )
                      else
                        Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              Icons
                                  .explore_outlined,
                              size: 44,
                              color: scheme
                                  .primary,
                            ),
                            const SizedBox(
                              height: 8,
                            ),
                            Text(
                              tr(
                                'جاري تشغيل البوصلة',
                                'Starting compass',
                              ),
                              style:
                                  TextStyle(
                                color: scheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                      Container(
                        width: 56,
                        height: 56,
                        decoration:
                            BoxDecoration(
                          shape:
                              BoxShape.circle,
                          color:
                              scheme.surface,
                          border:
                              Border.all(
                            color: scheme
                                .primary
                                .withValues(
                              alpha: 0.35,
                            ),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons
                              .mosque_rounded,
                          color:
                              scheme.primary,
                          size: 29,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  _qiblaAligned
                      ? tr(
                          '✓ اتجاه القبلة صحيح',
                          '✓ Qibla direction is correct',
                        )
                      : _qiblaDirectionText(),
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                    color: _qiblaAligned
                        ? Colors.green.shade600
                        : scheme.primary,
                  ),
                ),

                const SizedBox(height: 10),

                AnimatedContainer(
                  duration: const Duration(
                    milliseconds: 220,
                  ),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: _qiblaAligned
                        ? Colors.green.withValues(alpha: 0.10)
                        : scheme.surfaceContainerHighest
                            .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _qiblaAligned
                          ? Colors.green.shade600
                              .withValues(alpha: 0.45)
                          : scheme.outlineVariant
                              .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _qiblaAligned
                            ? Icons.check_circle_rounded
                            : Icons.notifications_none_rounded,
                        size: 21,
                        color: _qiblaAligned
                            ? Colors.green.shade600
                            : scheme.primary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _qiblaAligned
                              ? tr(
                                  'وصلتِ إلى اتجاه القبلة — يمكنكِ تثبيت الهاتف.',
                                  'You reached the Qibla direction — hold the phone steady.',
                                )
                              : tr(
                                  'سيصدر تنبيه لطيف عند الوصول إلى نطاق القبلة ±${_qiblaArrivalTolerance.toStringAsFixed(0)}°.',
                                  'A gentle alert will sound when you enter the ±${_qiblaArrivalTolerance.toStringAsFixed(0)}° Qibla zone.',
                                ),
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: _qiblaAligned
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: _qiblaAligned
                                ? Colors.green.shade700
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                 if (relative != null)
                   _buildQiblaAlignmentMeter(
                     scheme,
                     relative,
                   ),

                 const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child:
                          _buildCompassInfo(
                        scheme,
                        tr(
                          'اتجاه القبلة',
                          'Qibla bearing',
                        ),
                        qibla == null
                            ? '--'
                            : '${qibla.toStringAsFixed(1)}°',
                        Icons
                            .location_searching_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child:
                          _buildCompassInfo(
                        scheme,
                        tr(
                          'اتجاه الهاتف',
                          'Phone heading',
                        ),
                        heading == null
                            ? '--'
                            : '${heading.toStringAsFixed(1)}°',
                        Icons
                            .navigation_rounded,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: scheme
                          .onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        accuracyText,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: () => _showQiblaSettingsSheet(scheme),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    tr('إعدادات تنبيه القبلة', 'Qibla alert settings'),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(
                    11,
                  ),
                  decoration:
                      BoxDecoration(
                    color: scheme
                        .surfaceContainerHighest
                        .withValues(
                      alpha: 0.55,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons
                            .screen_rotation_alt_rounded,
                        size: 18,
                        color:
                            scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(
                            'لأفضل دقة: حرّكي الهاتف بشكل رقم 8 وابتعدي عن المعادن والمغناطيس.',
                            'For best accuracy, move the phone in a figure-8 and keep it away from metal and magnets.',
                          ),
                          style:
                              TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: scheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildQiblaAlignmentMeter(
    ColorScheme scheme,
    double relative,
  ) {
    final deviation = relative.abs();
    final tolerance = _qiblaArrivalTolerance;
    final progress = (1 - (deviation / 90)).clamp(0.0, 1.0);
    final inZone = deviation <= tolerance;

    final status = inZone
        ? tr(
            'أنت داخل نطاق القبلة',
            'You are inside the Qibla zone',
          )
        : deviation <= 15
            ? tr(
                'اقتربت من القبلة',
                'You are close to the Qibla',
              )
            : tr(
                'وجّه الهاتف نحو القبلة',
                'Turn the phone toward the Qibla',
              );

    final direction = relative > 0
        ? tr('إلى اليمين', 'to the right')
        : relative < 0
            ? tr('إلى اليسار', 'to the left')
            : tr('مباشرة', 'directly');

    final deviationText = deviation < 0.1
        ? tr('0° — في الاتجاه الصحيح', '0° — perfectly aligned')
        : tr(
            '${deviation.toStringAsFixed(1)}° $direction',
            '${deviation.toStringAsFixed(1)}° $direction',
          );

    final statusColor = inZone
        ? Colors.green.shade600
        : scheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: inZone
            ? Colors.green.withValues(alpha: 0.08)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: inZone
              ? Colors.green.shade600.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                inZone
                    ? Icons.check_circle_rounded
                    : Icons.compare_arrows_rounded,
                size: 20,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              Text(
                deviationText,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(
                tr('ابتعد', 'Off'),
                style: TextStyle(
                  fontSize: 9.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  tr(
                    'كلما امتلأ المؤشر اقتربت من القبلة',
                    'The fuller the meter, the closer you are',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                tr('القبلة', 'Qibla'),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompassInfo(
    ColorScheme scheme,
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: scheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: scheme.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style:
                      const TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.bold,
                    fontFeatures: [
                      FontFeature
                          .tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQiblaLocationRequired(
    ColorScheme scheme,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 24,
      ),
      child: Column(
        children: [
          Icon(
            Icons.location_off_rounded,
            size: 50,
            color: scheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'حددي موقعك أولًا لتحديد اتجاه القبلة بدقة',
              'Set your location first to determine the Qibla accurately',
            ),
            textAlign:
                TextAlign.center,
            style: const TextStyle(
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                _showLocationIntroduction,
            icon: const Icon(
              Icons.my_location_rounded,
            ),
            label: Text(
              tr(
                'تحديد الموقع',
                'Set location',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MY DAY CARD
  // ============================================================

  Widget _buildMyDayCard(
    Map<String, DateTime> times,
    ColorScheme scheme,
  ) {
    final completed = _completedDailyPrayers;
    const total = 5;
    final progress = completed / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primaryContainer,
            scheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.today_rounded,
                  color: scheme.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('يومي في صلاتي', 'My Day in Prayer'),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr(
                        'تابع صلواتك الخمس خلال اليوم',
                        'Track your five daily prayers',
                      ),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _arabic
                      ? '${_arabicDigits(completed)}/${_arabicDigits(total)}'
                      : '$completed/$total',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: _dailyPrayerKeys.map((key) {
              final prayerTime = times[key];
              final completedPrayer =
                  _dailyPrayerCompleted[key] ?? false;
              final available =
                  prayerTime != null && !prayerTime.isAfter(_now);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: prayerTime != null
                        ? () => _toggleDailyPrayer(key, times)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 2,
                      ),
                      decoration: BoxDecoration(
                        color: completedPrayer
                            ? scheme.primary
                            : scheme.surface.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: completedPrayer
                              ? scheme.primary
                              : scheme.outlineVariant.withValues(
                                  alpha: 0.45,
                                ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            completedPrayer
                                ? Icons.check_circle_rounded
                                : available
                                    ? _prayerIcon(key)
                                    : Icons.lock_clock_rounded,
                            size: 19,
                            color: completedPrayer
                                ? scheme.onPrimary
                                : available
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            prayerName(key),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: completedPrayer
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                completed == total
                    ? Icons.celebration_rounded
                    : Icons.info_outline_rounded,
                size: 17,
                color: scheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  completed == total
                      ? tr(
                          'ما شاء الله، أتممت صلوات اليوم الخمس.',
                          'MashaAllah, you completed all five prayers today.',
                        )
                      : tr(
                          'اضغط على الصلاة لتسجيل إتمامها، واضغط مرة أخرى لإلغاء التسجيل.',
                          'Tap a prayer to mark it completed. Tap again to undo.',
                        ),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WEEKLY PRAYER HISTORY
  // ============================================================

  Widget _buildWeeklyPrayerCard(ColorScheme scheme) {
    return FutureBuilder<List<int>>(
      future: _loadWeeklyPrayerStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? List<int>.filled(7, 0);
        final weeklyCompleted = stats.fold<int>(
          0,
          (sum, value) => sum + value,
        );
        const weeklyTotal = 35;
        final weeklyProgress = weeklyCompleted / weeklyTotal;

        const weekdaysAr = [
          'الإث', 'الث', 'الأر', 'الخ', 'الج', 'السب', 'الأح',
        ];
        const weekdaysEn = [
          'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
        ];

        final today = DateTime.now();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.insights_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('سجل صلاتي هذا الأسبوع', 'My Prayer This Week'),
                          style: Theme.of(context)
                              .textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr(
                            'تابع إنجازك خلال آخر 7 أيام',
                            'Track your progress over the last 7 days',
                          ),
                          style: Theme.of(context)
                              .textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _arabic
                        ? '${_arabicDigits(weeklyCompleted)}/35'
                        : '$weeklyCompleted/35',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: weeklyProgress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: List.generate(7, (index) {
                  final date = DateTime(
                    today.year,
                    today.month,
                    today.day - (6 - index),
                  );
                  final count = stats[index];
                  final isToday = index == 6;
                  final dayLabel = _arabic
                      ? weekdaysAr[date.weekday - 1]
                      : weekdaysEn[date.weekday - 1];

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isToday
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: isToday
                                ? scheme.primary.withValues(alpha: 0.35)
                                : scheme.outlineVariant.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              dayLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              date.day.toString(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isToday ? scheme.primary : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Icon(
                              count == 5
                                  ? Icons.check_circle_rounded
                                  : count > 0
                                      ? Icons.circle_rounded
                                      : Icons.remove_circle_outline_rounded,
                              size: 16,
                              color: count == 5
                                  ? scheme.primary
                                  : count > 0
                                      ? scheme.primary.withValues(alpha: 0.65)
                                      : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _arabic
                                  ? '${_arabicDigits(count)}/5'
                                  : '$count/5',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // PRAYER HEADER
  // ============================================================

  Widget _buildPrayerHeader(
    ColorScheme scheme,
  ) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration:
              BoxDecoration(
            color:
                scheme.primaryContainer,
            borderRadius:
                BorderRadius.circular(14),
          ),
          child: Icon(
            Icons
                .access_time_filled_rounded,
            color:
                scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'مواقيت الصلاة',
                  'Prayer times',
                ),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              Text(
                tr(
                  'الأذان والإقامة حسب موقعك',
                  'Adhan and iqama for your location',
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                  color: scheme
                      .onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: tr(
            'إعدادات المواقيت',
            'Prayer settings',
          ),
          onPressed:
              _showSettings,
          icon: const Icon(
            Icons.tune_rounded,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PRAYER CARD
  // ============================================================

  Widget _buildPrayerCard(
    String key,
    DateTime adhanTime,
    Map<String, DateTime> times,
    bool isNext,
    ColorScheme scheme,
  ) {
    final iqamaTime =
        _iqamaTime(key, times);

    final adjustment =
        _adjustments[key] ?? 0;

    final isIqamaAvailable =
        iqamaTime != null;

    final background =
        isNext
            ? scheme.primaryContainer
            : Theme.of(context)
                .colorScheme
                .surface;

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      decoration:
          BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color: isNext
              ? scheme.primary
                  .withValues(
                  alpha: 0.35,
                )
              : scheme
                  .outlineVariant
                  .withValues(
                  alpha: 0.45,
                ),
        ),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration:
                      BoxDecoration(
                    color: isNext
                        ? scheme.primary
                        : scheme
                            .surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                  ),
                  child: Icon(
                    _prayerIcon(key),
                    color: isNext
                        ? scheme.onPrimary
                        : scheme
                            .onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              prayerName(key),
                              style:
                                  const TextStyle(
                                fontSize: 17,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isNext) ...[
                            const SizedBox(
                              width: 6,
                            ),
                            Container(
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration:
                                  BoxDecoration(
                                color:
                                    scheme.primary,
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  20,
                                ),
                              ),
                              child: Text(
                                tr(
                                  'القادمة',
                                  'NEXT',
                                ),
                                style:
                                    TextStyle(
                                  color:
                                      scheme.onPrimary,
                                  fontSize: 9,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        key == 'sunrise'
                            ? tr(
                                'وقت الشروق',
                                'Sunrise time',
                              )
                            : tr(
                                'الأذان والإقامة',
                                'Adhan & Iqama',
                              ),
                        style:
                            TextStyle(
                          color: scheme
                              .onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    _buildDigitalTimeBox(
                      label: tr(
                        'الأذان',
                        'ADHAN',
                      ),
                      time:
                          _formatDigitalTime(
                        adhanTime,
                      ),
                      active: isNext,
                      scheme: scheme,
                    ),
                    if (isIqamaAvailable) ...[
                      const SizedBox(
                        height: 6,
                      ),
                      _buildDigitalTimeBox(
                        label: tr(
                          'الإقامة',
                          'IQAMA',
                        ),
                        time:
                            _formatDigitalTime(
                          iqamaTime,
                        ),
                        active: false,
                        scheme: scheme,
                        iqama: true,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (key != 'sunrise') ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration:
                    BoxDecoration(
                  color: scheme
                      .surfaceContainerHighest
                      .withValues(
                    alpha: 0.55,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color:
                          scheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        tr(
                          'ضبط حسب توقيت المسجد',
                          'Adjust for local mosque',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme
                              .onSurfaceVariant,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ),
                    _buildAdjustButton(
                      icon:
                          Icons.remove_rounded,
                      onPressed: () =>
                          _adjustPrayer(
                        key,
                        -1,
                      ),
                      scheme: scheme,
                    ),
                    const SizedBox(width: 6),
                    Container(
                      constraints:
                          const BoxConstraints(
                        minWidth: 54,
                      ),
                      alignment:
                          Alignment.center,
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 7,
                        vertical: 6,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            scheme.surface,
                        borderRadius:
                            BorderRadius.circular(
                          10,
                        ),
                      ),
                      child: Text(
                        adjustment == 0
                            ? tr(
                                '0 دقيقة',
                                '0 min',
                              )
                            : '${adjustment > 0 ? '+' : ''}$adjustment ${tr('د', 'min')}',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 12,
                          color: adjustment ==
                                  0
                              ? scheme
                                  .onSurfaceVariant
                              : scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildAdjustButton(
                      icon:
                          Icons.add_rounded,
                      onPressed: () =>
                          _adjustPrayer(
                        key,
                        1,
                      ),
                      scheme: scheme,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DIGITAL TIME BOX
  // ============================================================

  Widget _buildDigitalTimeBox({
    required String label,
    required String time,
    required bool active,
    required ColorScheme scheme,
    bool iqama = false,
  }) {
    final background =
        active
            ? scheme.primary
            : iqama
                ? const Color(0xFFE9F2EC)
                : scheme
                    .surfaceContainerHighest;

    final foreground =
        active
            ? scheme.onPrimary
            : iqama
                ? const Color(0xFF176B52)
                : scheme.onSurface;

    return Container(
      constraints:
          const BoxConstraints(
        minWidth: 112,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration:
          BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight:
                  FontWeight.bold,
              letterSpacing: 0.5,
              color:
                  foreground.withValues(
                alpha: 0.72,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            time,
            style: TextStyle(
              fontSize: 19,
              height: 1.05,
              fontWeight:
                  FontWeight.w800,
              fontFeatures: const [
                FontFeature
                    .tabularFigures(),
              ],
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ADJUST BUTTON
  // ============================================================

  Widget _buildAdjustButton({
    required IconData icon,
    required VoidCallback onPressed,
    required ColorScheme scheme,
  }) {
    return Material(
      color: scheme.primaryContainer,
      borderRadius:
          BorderRadius.circular(10),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(10),
        onTap: onPressed,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 19,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WELCOME / QURAN CARD
  // ============================================================

  Widget _buildWelcomeCard(
    ColorScheme scheme,
  ) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        20,
        25,
        20,
        18,
      ),
      decoration:
          BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(
              scheme.primary,
              scheme.tertiary,
              0.5,
            )!,
          ],
          begin:
              Alignment.topRight,
          end:
              Alignment.bottomLeft,
        ),
        borderRadius:
            BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  scheme.onPrimary,
              fontSize: 20,
              height: 1.8,
              fontWeight:
                  FontWeight.w600,
              fontFamily:
                  'serif',
              fontFamilyFallback: const [
                'Noto Naskh Arabic',
                'Amiri',
              ],
            ),
          ),

          const SizedBox(height: 10),

          Container(
            width: 55,
            height: 2,
            decoration:
                BoxDecoration(
              color: scheme.onPrimary
                  .withValues(
                alpha: 0.45,
              ),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            '﴿ إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَابًا مَوْقُوتًا ﴾',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  scheme.onPrimary,
              fontSize: 21,
              height: 1.9,
              fontWeight:
                  FontWeight.w600,
              fontFamily:
                  'serif',
              fontFamilyFallback: const [
                'Noto Naskh Arabic',
                'Amiri',
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            height: 1,
            color: scheme.onPrimary
                .withValues(
              alpha: 0.20,
            ),
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                color:
                    scheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(_now),
                style: TextStyle(
                  color:
                      scheme.onPrimary,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                  fontFeatures: const [
                    FontFeature
                        .tabularFigures(),
                  ],
                ),
              ),
              const Spacer(),
              Icon(
                Icons.calendar_month,
                color:
                    scheme.onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DATE CARD
  // ============================================================

  Widget _buildDateCard(
    ColorScheme scheme,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(16),
      decoration:
          BoxDecoration(
        color: scheme.surface,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: scheme
              .outlineVariant
              .withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(
              color:
                  scheme.primaryContainer,
              borderRadius:
                  BorderRadius.circular(
                13,
              ),
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              color:
                  scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _dateText(),
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NEXT PRAYER CARD
  // ============================================================

  Widget _buildNextPrayerCard(
    MapEntry<String, DateTime>? next,
    ColorScheme scheme,
  ) {
    final remaining =
        next == null
            ? Duration.zero
            : next.value
                .difference(_now);

    return Container(
      padding:
          const EdgeInsets.all(20),
      decoration:
          BoxDecoration(
        gradient: LinearGradient(
          begin:
              Alignment.topRight,
          end:
              Alignment.bottomLeft,
          colors: [
            scheme.secondaryContainer,
            Color.lerp(
              scheme.secondaryContainer,
              scheme.surface,
              0.35,
            )!,
          ],
        ),
        borderRadius:
            BorderRadius.circular(24),
        border: Border.all(
          color: scheme
              .outlineVariant
              .withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                color: scheme
                    .onSecondaryContainer,
              ),
              const SizedBox(width: 7),
              Text(
                tr(
                  'الصلاة القادمة',
                  'Next prayer',
                ),
                style: TextStyle(
                  color: scheme
                      .onSecondaryContainer,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            next == null
                ? tr(
                    'حددي موقعك أولًا',
                    'Set your location first',
                  )
                : prayerName(
                    next.key,
                  ),
            style: TextStyle(
              color: scheme
                  .onSecondaryContainer,
              fontSize: 27,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            next == null
                ? '--:--:--'
                : _countdown(
                    remaining,
                  ),
            style: TextStyle(
              color: scheme
                  .onSecondaryContainer,
              fontSize: 32,
              fontWeight:
                  FontWeight.bold,
              fontFeatures: const [
                FontFeature
                    .tabularFigures(),
              ],
            ),
          ),
          if (next != null)
            Text(
              '${tr('موعد الأذان', 'Adhan time')}: ${_formatTime(next.value)}',
              style: TextStyle(
                color: scheme
                    .onSecondaryContainer,
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // NO LOCATION
  // ============================================================

  Widget _buildNoLocationCard(
    ColorScheme scheme,
  ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding:
            const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 44,
              color:
                  scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'حددي موقعك لحساب المواقيت بدقة',
                'Set your location to calculate prayer times',
              ),
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _showLocationIntroduction,
              icon: const Icon(
                Icons.my_location_rounded,
              ),
              label: Text(
                tr(
                  'تحديد الموقع',
                  'Set location',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOCATION CARD
  // ============================================================

  Widget _buildLocationCard(
    ColorScheme scheme,
  ) {
    final p = _position;

    if (p == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color:
                      scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(
                      'معلومات الموقع',
                      'Location information',
                    ),
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _getLocation,
                  icon: const Icon(
                    Icons.refresh_rounded,
                  ),
                  tooltip: tr(
                    'تحديث الموقع',
                    'Refresh location',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow(
              tr(
                'خط العرض',
                'Latitude',
              ),
              p.latitude
                  .toStringAsFixed(6),
            ),
            _infoRow(
              tr(
                'خط الطول',
                'Longitude',
              ),
              p.longitude
                  .toStringAsFixed(6),
            ),
            _infoRow(
              tr(
                'الارتفاع',
                'Altitude',
              ),
              '${p.altitude.toStringAsFixed(1)} m',
            ),
            _infoRow(
              tr(
                'دقة القياس',
                'Accuracy',
              ),
              '${p.accuracy.toStringAsFixed(1)} m',
            ),
            _infoRow(
              tr(
                'آخر تحديث',
                'Last update',
              ),
              p.timestamp
                  .toLocal()
                  .toString()
                  .split('.')
                  .first,
            ),
            if (_place.isNotEmpty)
              _infoRow(
                tr(
                  'المكان',
                  'Place',
                ),
                _place,
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _deleteLocation,
              icon: const Icon(
                Icons.delete_outline,
              ),
              label: Text(
                tr(
                  'حذف الموقع المحفوظ',
                  'Delete saved location',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign:
                  TextAlign.end,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // QUICK SETTINGS
  // ============================================================

  Widget _buildQuickSettings(
    ColorScheme scheme,
  ) {
    return Card(
      elevation: 0,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(
              Icons.dark_mode_outlined,
            ),
            title: Text(
              tr(
                'الوضع الداكن',
                'Dark mode',
              ),
            ),
            value:
                widget.darkMode,
            onChanged:
                widget.onThemeChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.language_rounded,
            ),
            title: Text(
              tr(
                'لغة التطبيق',
                'App language',
              ),
            ),
            subtitle: Text(
              _arabic
                  ? 'العربية'
                  : 'English',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () =>
                widget.onLanguageChanged(
              _arabic ? 'en' : 'ar',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons
                  .notifications_active_outlined,
            ),
            title: Text(
              tr(
                'إعدادات الأذان',
                'Adhan settings',
              ),
            ),
            subtitle: Text(
              _adhanEnabled
                  ? tr(
                      'الأذان مفعّل',
                      'Adhan enabled',
                    )
                  : tr(
                      'الأذان متوقف',
                      'Adhan disabled',
                    ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap:
                _showAdhanSettings,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.tune_rounded,
            ),
            title: Text(
              tr(
                'إعدادات المواقيت',
                'Prayer settings',
              ),
            ),
            subtitle: Text(
              tr(
                'طريقة الحساب والإقامة وتصحيح المواقيت',
                'Calculation, iqama and time adjustment',
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap:
                _showSettings,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ADHAN TEST
  // ============================================================

  Future<void> _testMakkahAdhan(
    BuildContext sheetContext,
  ) async {
    try {
      await PrayerNotifications
          .instance
          .showAdhanTestNotification();

      if (!mounted ||
          !sheetContext.mounted) {
        return;
      }

      ScaffoldMessenger.of(
        sheetContext,
      ).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'تم إرسال اختبار أذان مكة. تحققي من الإشعار والصوت.',
              'Makkah adhan test notification sent. Check the notification and sound.',
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Adhan test error: $e',
      );

      if (!mounted ||
          !sheetContext.mounted) {
        return;
      }

      ScaffoldMessenger.of(
        sheetContext,
      ).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'تعذر تشغيل اختبار الأذان.',
              'Could not start the adhan test.',
            ),
          ),
        ),
      );
    }
  }

  // ============================================================
  // ADHAN SETTINGS SCREEN
  // ============================================================

  Future<void> _showAdhanSettings() async {
    bool master = _adhanEnabled;
    bool fajr =
        _fajrAdhanEnabled;
    bool dhuhr =
        _dhuhrAdhanEnabled;
    bool asr =
        _asrAdhanEnabled;
    bool maghrib =
        _maghribAdhanEnabled;
    bool isha =
        _ishaAdhanEnabled;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            return SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  20,
                  8,
                  20,
                  24,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      tr(
                        'إعدادات الأذان',
                        'Adhan settings',
                      ),
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        'يمكنك التحكم بالأذان لكل صلاة بشكل مستقل.',
                        'Control the adhan independently for each prayer.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: Theme.of(
                        context,
                      )
                          .colorScheme
                          .secondaryContainer,
                      child: Padding(
                        padding:
                            const EdgeInsets
                                .all(14),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .stretch,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      Theme.of(
                                    context,
                                  )
                                          .colorScheme
                                          .primary,
                                  child: Icon(
                                    Icons
                                        .volume_up_rounded,
                                    color: Theme.of(
                                      context,
                                    )
                                        .colorScheme
                                        .onPrimary,
                                  ),
                                ),
                                const SizedBox(
                                  width: 12,
                                ),
                                Expanded(
                                  child:
                                      Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        tr(
                                          'اختبار أذان مكة الآن',
                                          'Test Makkah adhan now',
                                        ),
                                        style:
                                            const TextStyle(
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          fontSize:
                                              16,
                                        ),
                                      ),
                                      const SizedBox(
                                          height: 3),
                                      Text(
                                        tr(
                                          'تجربة الإشعار وصوت أذان مكة المكرمة فورًا.',
                                          'Test the notification and Makkah adhan sound immediately.',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(
                                height: 12),
                            FilledButton.icon(
                              onPressed: () =>
                                  _testMakkahAdhan(
                                context,
                              ),
                              icon: const Icon(
                                Icons
                                    .play_circle_fill_rounded,
                              ),
                              label: Text(
                                tr(
                                  'تشغيل اختبار الأذان',
                                  'Play adhan test',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(
                        height: 16),
                    Card(
                      elevation: 0,
                      color: Theme.of(
                        context,
                      )
                          .colorScheme
                          .primaryContainer,
                      child:
                          SwitchListTile(
                        secondary: Icon(
                          master
                              ? Icons
                                  .notifications_active_rounded
                              : Icons
                                  .notifications_off_rounded,
                        ),
                        title: Text(
                          tr(
                            'الأذان لجميع الصلوات',
                            'Adhan for all prayers',
                          ),
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        subtitle:
                            Text(
                          master
                              ? tr(
                                  'مفعّل',
                                  'Enabled',
                                )
                              : tr(
                                  'متوقف',
                                  'Disabled',
                                ),
                        ),
                        value: master,
                        onChanged:
                            (value) {
                          setSheetState(
                            () {
                              master =
                                  value;

                              if (!value) {
                                fajr =
                                    false;
                                dhuhr =
                                    false;
                                asr =
                                    false;
                                maghrib =
                                    false;
                                isha =
                                    false;
                              } else {
                                fajr =
                                    true;
                                dhuhr =
                                    true;
                                asr =
                                    true;
                                maghrib =
                                    true;
                                isha =
                                    true;
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(
                        height: 16),
                    SwitchListTile(
                      secondary:
                          const Icon(
                        Icons
                            .nightlight_round,
                      ),
                      title: Text(
                        tr(
                          'أذان الفجر',
                          'Fajr adhan',
                        ),
                      ),
                      subtitle: Text(
                        tr(
                          'أذان مكة المكرمة',
                          'Makkah adhan',
                        ),
                      ),
                      value: fajr,
                      onChanged: master
                          ? (value) {
                              setSheetState(
                                () {
                                  fajr =
                                      value;
                                },
                              );
                            }
                          : null,
                    ),
                    const Divider(
                        height: 1),
                    SwitchListTile(
                      secondary:
                          const Icon(
                        Icons
                            .wb_sunny_rounded,
                      ),
                      title: Text(
                        tr(
                          'أذان الظهر',
                          'Dhuhr adhan',
                        ),
                      ),
                      subtitle: Text(
                        tr(
                          'أذان مكة المكرمة',
                          'Makkah adhan',
                        ),
                      ),
                      value: dhuhr,
                      onChanged: master
                          ? (value) {
                              setSheetState(
                                () {
                                  dhuhr =
                                      value;
                                },
                              );
                            }
                          : null,
                    ),
                    const Divider(
                        height: 1),
                    SwitchListTile(
                      secondary:
                          const Icon(
                        Icons.sunny,
                      ),
                      title: Text(
                        tr(
                          'أذان العصر',
                          'Asr adhan',
                        ),
                      ),
                      subtitle: Text(
                        tr(
                          'أذان مكة المكرمة',
                          'Makkah adhan',
                        ),
                      ),
                      value: asr,
                      onChanged: master
                          ? (value) {
                              setSheetState(
                                () {
                                  asr =
                                      value;
                                },
                              );
                            }
                          : null,
                    ),
                    const Divider(
                        height: 1),
                    SwitchListTile(
                      secondary:
                          const Icon(
                        Icons
                            .wb_twilight_rounded,
                      ),
                      title: Text(
                        tr(
                          'أذان المغرب',
                          'Maghrib adhan',
                        ),
                      ),
                      subtitle: Text(
                        tr(
                          'أذان مكة المكرمة',
                          'Makkah adhan',
                        ),
                      ),
                      value: maghrib,
                      onChanged: master
                          ? (value) {
                              setSheetState(
                                () {
                                  maghrib =
                                      value;
                                },
                              );
                            }
                          : null,
                    ),
                    const Divider(
                        height: 1),
                    SwitchListTile(
                      secondary:
                          const Icon(
                        Icons
                            .nights_stay_rounded,
                      ),
                      title: Text(
                        tr(
                          'أذان العشاء',
                          'Isha adhan',
                        ),
                      ),
                      subtitle: Text(
                        tr(
                          'أذان مكة المكرمة',
                          'Makkah adhan',
                        ),
                      ),
                      value: isha,
                      onChanged: master
                          ? (value) {
                              setSheetState(
                                () {
                                  isha =
                                      value;
                                },
                              );
                            }
                          : null,
                    ),
                    const SizedBox(
                        height: 20),
                    FilledButton.icon(
                      onPressed:
                          () async {
                        _adhanEnabled =
                            master;

                        _fajrAdhanEnabled =
                            fajr;

                        _dhuhrAdhanEnabled =
                            dhuhr;

                        _asrAdhanEnabled =
                            asr;

                        _maghribAdhanEnabled =
                            maghrib;

                        _ishaAdhanEnabled =
                            isha;

                        await _saveAdhanSetting(
                          'adhanEnabled',
                          master,
                        );

                        await _saveAdhanSetting(
                          'fajrAdhanEnabled',
                          fajr,
                        );

                        await _saveAdhanSetting(
                          'dhuhrAdhanEnabled',
                          dhuhr,
                        );

                        await _saveAdhanSetting(
                          'asrAdhanEnabled',
                          asr,
                        );

                        await _saveAdhanSetting(
                          'maghribAdhanEnabled',
                          maghrib,
                        );

                        await _saveAdhanSetting(
                          'ishaAdhanEnabled',
                          isha,
                        );

                        if (!context
                            .mounted) {
                          return;
                        }

                        Navigator.pop(
                          context,
                        );

                        if (mounted) {
                          setState(
                              () {});
                        }

                        await _refreshPrayerNotifications();

                        if (mounted) {
                          _showMessage(
                            tr(
                              'تم حفظ إعدادات الأذان وجدولة التنبيهات.',
                              'Adhan settings saved and notifications rescheduled.',
                            ),
                          );
                        }
                      },
                      icon:
                          const Icon(
                        Icons
                            .check_circle_outline,
                      ),
                      label: Text(
                        tr(
                          'حفظ إعدادات الأذان',
                          'Save adhan settings',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // LOCATION INTRODUCTION
  // ============================================================

  Future<void> _showLocationIntroduction() async {
    final accepted =
        await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
        icon: const Icon(
          Icons.location_on_rounded,
          size: 36,
        ),
        title: Text(
          tr(
            'السماح بالوصول إلى الموقع',
            'Location access',
          ),
        ),
        content: Text(
          tr(
            'يحتاج تطبيق صلاتي إلى موقعك لحساب مواقيت الصلاة وتحديد اتجاه القبلة بدقة. تُحفظ الإحداثيات على جهازك.',
            'Salati uses your location to calculate prayer times and determine the Qibla direction accurately. Coordinates are saved on your device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
              false,
            ),
            child: Text(
              tr(
                'ليس الآن',
                'Not now',
              ),
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              true,
            ),
            child: Text(
              tr(
                'متابعة',
                'Continue',
              ),
            ),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await _getLocation();
    }

    if (_error != null &&
        mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) =>
            AlertDialog(
          title: Text(
            tr(
              'تعذر تحديد الموقع',
              'Location unavailable',
            ),
          ),
          content:
              Text(_error!),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child: Text(
                tr(
                  'إغلاق',
                  'Close',
                ),
              ),
            ),
            if (_error!.contains(
                  'إعدادات',
                ) ||
                _error!.contains(
                  'settings',
                ))
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );

                  _openLocationSettings();
                },
                child: Text(
                  tr(
                    'فتح الإعدادات',
                    'Open settings',
                  ),
                ),
              ),
          ],
        ),
      );
    }
  }

  // ============================================================
  // PRAYER SETTINGS
  // ============================================================

  Future<void> _showSettings() async {
    int method = _method;

    int school = _asrSchool;

    int hijri =
        _hijriCorrection;

    final iqamaValues =
        Map<String, int>.from(
      _iqamaOffsets,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            return SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  20,
                  8,
                  20,
                  24,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      tr(
                        'إعدادات صلاتي',
                        'Salati settings',
                      ),
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                        height: 20),
                    Text(
                      tr(
                        'طريقة حساب المواقيت',
                        'Calculation method',
                      ),
                    ),
                    const SizedBox(
                        height: 8),
                    DropdownButtonFormField<int>(
                      value: method,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(
                        border:
                            OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            tr(
                              'رابطة العالم الإسلامي',
                              'Muslim World League',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text(
                            tr(
                              'أم القرى',
                              'Umm Al-Qura',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text(
                            tr(
                              'الهيئة المصرية',
                              'Egyptian',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text(
                            tr(
                              'كراتشي',
                              'Karachi',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 4,
                          child: Text(
                            tr(
                              'أمريكا الشمالية',
                              'North America',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 5,
                          child: Text(
                            tr(
                              'الكويت',
                              'Kuwait',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 6,
                          child: Text(
                            tr(
                              'قطر',
                              'Qatar',
                            ),
                          ),
                        ),
                      ],
                      onChanged:
                          (value) {
                        if (value !=
                            null) {
                          setSheetState(
                            () => method =
                                value,
                          );
                        }
                      },
                    ),
                    const SizedBox(
                        height: 20),
                    Text(
                      tr(
                        'طريقة حساب العصر',
                        'Asr calculation',
                      ),
                    ),
                    RadioListTile<int>(
                      value: 0,
                      groupValue: school,
                      title: Text(
                        tr(
                          'الشافعي',
                          'Shafi',
                        ),
                      ),
                      onChanged: (v) {
                        if (v !=
                            null) {
                          setSheetState(
                            () => school =
                                v,
                          );
                        }
                      },
                    ),
                    RadioListTile<int>(
                      value: 1,
                      groupValue: school,
                      title: Text(
                        tr(
                          'الحنفي',
                          'Hanafi',
                        ),
                      ),
                      onChanged: (v) {
                        if (v !=
                            null) {
                          setSheetState(
                            () => school =
                                v,
                          );
                        }
                      },
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Icon(
                          Icons
                              .timer_rounded,
                          color: Theme.of(
                            context,
                          )
                              .colorScheme
                              .primary,
                        ),
                        const SizedBox(
                            width: 8),
                        Expanded(
                          child: Text(
                            tr(
                              'مواقيت الإقامة',
                              'Iqama times',
                            ),
                            style:
                                const TextStyle(
                              fontSize:
                                  17,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                        height: 5),
                    Text(
                      tr(
                        'تُحسب الإقامة بعد الأذان حسب المدة التي تحددينها لمسجد المنطقة.',
                        'Iqama is calculated after adhan using the interval set for your local mosque.',
                      ),
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color: Theme.of(
                          context,
                        )
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(
                        height: 12),
                    ..._iqamaPrayerKeys
                        .map(
                      (key) {
                        return Padding(
                          padding:
                              const EdgeInsets
                                  .only(
                            bottom: 8,
                          ),
                          child:
                              Container(
                            decoration:
                                BoxDecoration(
                              color: Theme.of(
                                context,
                              )
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(
                                alpha:
                                    0.45,
                              ),
                              borderRadius:
                                  BorderRadius.circular(
                                15,
                              ),
                            ),
                            child:
                                ListTile(
                              leading:
                                  Icon(
                                _prayerIcon(
                                  key,
                                ),
                              ),
                              title:
                                  Text(
                                prayerName(
                                  key,
                                ),
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .w600,
                                ),
                              ),
                              subtitle:
                                  Text(
                                '${tr('بعد الأذان', 'After adhan')}: ${iqamaValues[key]} ${tr('دقيقة', 'min')}',
                              ),
                              trailing:
                                  DropdownButton<int>(
                                value:
                                    iqamaValues[
                                        key],
                                underline:
                                    const SizedBox
                                        .shrink(),
                                items:
                                    List.generate(
                                  13,
                                  (index) {
                                    final minutes =
                                        index *
                                            5;

                                    return DropdownMenuItem<
                                        int>(
                                      value:
                                          minutes,
                                      child:
                                          Text(
                                        '$minutes',
                                      ),
                                    );
                                  },
                                ),
                                onChanged:
                                    (value) {
                                  if (value ==
                                      null) {
                                    return;
                                  }

                                  setSheetState(
                                    () {
                                      iqamaValues[
                                          key] = value;
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(
                        height: 12),
                    const Divider(),
                    Text(
                      tr(
                        'تصحيح التاريخ الهجري',
                        'Hijri date adjustment',
                      ),
                    ),
                    const SizedBox(
                        height: 8),
                    DropdownButtonFormField<int>(
                      value: hijri,
                      decoration:
                          const InputDecoration(
                        border:
                            OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: -2,
                          child: Text(
                            tr(
                              'ناقص يومين',
                              'Minus 2 days',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: -1,
                          child: Text(
                            tr(
                              'ناقص يوم',
                              'Minus 1 day',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            tr(
                              'بدون تعديل',
                              'No adjustment',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text(
                            tr(
                              'زائد يوم',
                              'Plus 1 day',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text(
                            tr(
                              'زائد يومين',
                              'Plus 2 days',
                            ),
                          ),
                        ),
                      ],
                      onChanged:
                          (v) {
                        if (v !=
                            null) {
                          setSheetState(
                            () => hijri =
                                v,
                          );
                        }
                      },
                    ),
                    const SizedBox(
                        height: 20),
                    FilledButton(
                      onPressed:
                          () async {
                        _method =
                            method;

                        _asrSchool =
                            school;

                        _hijriCorrection =
                            hijri;

                        _iqamaOffsets
                          ..clear()
                          ..addAll(
                            iqamaValues,
                          );

                        try {
                          await _saveSetting(
                            'method',
                            method,
                          );

                          await _saveSetting(
                            'asrSchool',
                            school,
                          );

                          await _saveSetting(
                            'hijriCorrection',
                            hijri,
                          );

                          for (final key
                              in _iqamaPrayerKeys) {
                            await _saveIqamaOffset(
                              key,
                              iqamaValues[
                                  key]!,
                            );
                          }
                        } catch (e) {
                          debugPrint(
                            'Settings saving error: $e',
                          );
                        }

                        if (!context
                            .mounted) {
                          return;
                        }

                        Navigator.pop(
                          context,
                        );

                        if (mounted) {
                          setState(
                              () {});
                        }

                        await _refreshPrayerNotifications();

                        if (mounted) {
                          _showMessage(
                            tr(
                              'تم حفظ إعدادات المواقيت والإقامة.',
                              'Prayer and iqama settings saved.',
                            ),
                          );
                        }
                      },
                      child: Text(
                        tr(
                          'حفظ الإعدادات',
                          'Save settings',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================
// QIBLA COMPASS PAINTER
// ============================================================

class _QiblaCompassPainter
    extends CustomPainter {
  final ColorScheme scheme;

  const _QiblaCompassPainter({
    required this.scheme,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        math.min(
          size.width,
          size.height,
        ) /
            2 -
        12;

    final outerPaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color =
              scheme.primary.withValues(
            alpha: 0.35,
          );

    canvas.drawCircle(
      center,
      radius,
      outerPaint,
    );

    final innerPaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 1
          ..color =
              scheme.outlineVariant
                  .withValues(
            alpha: 0.8,
          );

    canvas.drawCircle(
      center,
      radius - 17,
      innerPaint,
    );

    final tickPaint =
        Paint()
          ..strokeWidth = 1.4
          ..color =
              scheme.onSurfaceVariant
                  .withValues(
            alpha: 0.45,
          );

    for (int i = 0; i < 360; i += 5) {
      final angle =
          (i - 90) *
              math.pi /
              180;

      final isMajor =
          i % 30 == 0;

      final outer =
          radius - 4;

      final inner =
          radius -
              (isMajor ? 17 : 11);

      final start = Offset(
        center.dx +
            math.cos(angle) *
                inner,
        center.dy +
            math.sin(angle) *
                inner,
      );

      final end = Offset(
        center.dx +
            math.cos(angle) *
                outer,
        center.dy +
            math.sin(angle) *
                outer,
      );

      canvas.drawLine(
        start,
        end,
        tickPaint,
      );
    }

    _drawCardinal(
      canvas,
      center,
      radius,
      'N',
      0,
      scheme.primary,
    );

    _drawCardinal(
      canvas,
      center,
      radius,
      'E',
      90,
      scheme.onSurfaceVariant,
    );

    _drawCardinal(
      canvas,
      center,
      radius,
      'S',
      180,
      scheme.onSurfaceVariant,
    );

    _drawCardinal(
      canvas,
      center,
      radius,
      'W',
      270,
      scheme.onSurfaceVariant,
    );

    final smallPaint =
        Paint()
          ..color =
              scheme.primary.withValues(
            alpha: 0.12,
          )
          ..style =
              PaintingStyle.fill;

    canvas.drawCircle(
      center,
      38,
      smallPaint,
    );
  }

  void _drawCardinal(
    Canvas canvas,
    Offset center,
    double radius,
    String text,
    double degrees,
    Color color,
  ) {
    final angle =
        (degrees - 90) *
            math.pi /
            180;

    final position = Offset(
      center.dx +
          math.cos(angle) *
              (radius - 32),
      center.dy +
          math.sin(angle) *
              (radius - 32),
    );

    final textPainter =
        TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize:
              text == 'N' ? 18 : 14,
          fontWeight:
              FontWeight.bold,
        ),
      ),
      textDirection:
          TextDirection.ltr,
    );

    textPainter.layout();

    textPainter.paint(
      canvas,
      Offset(
        position.dx -
            textPainter.width / 2,
        position.dy -
            textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(
    covariant _QiblaCompassPainter oldDelegate,
  ) {
    return oldDelegate.scheme !=
        scheme;
  }
}

// ============================================================
// QIBLA POINTER PAINTER
// ============================================================

class _QiblaPointerPainter
    extends CustomPainter {
  final Color color;

  const _QiblaPointerPainter({
    required this.color,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final pointerPaint =
        Paint()
          ..color = color
          ..style =
              PaintingStyle.fill;

    final shadowPaint =
        Paint()
          ..color = Colors.black
              .withValues(
            alpha: 0.12,
          )
          ..style =
              PaintingStyle.fill;

    final path = Path();

    path.moveTo(
      center.dx,
      center.dy - 105,
    );

    path.lineTo(
      center.dx - 16,
      center.dy - 54,
    );

    path.lineTo(
      center.dx,
      center.dy - 64,
    );

    path.lineTo(
      center.dx + 16,
      center.dy - 54,
    );

    path.close();

    canvas.save();

    canvas.translate(
      0,
      3,
    );

    canvas.drawPath(
      path,
      shadowPaint,
    );

    canvas.restore();

    canvas.drawPath(
      path,
      pointerPaint,
    );

    final smallPath =
        Path();

    smallPath.moveTo(
      center.dx,
      center.dy - 87,
    );

    smallPath.lineTo(
      center.dx - 7,
      center.dy - 62,
    );

    smallPath.lineTo(
      center.dx,
      center.dy - 68,
    );

    smallPath.lineTo(
      center.dx + 7,
      center.dy - 62,
    );

    smallPath.close();

    final highlightPaint =
        Paint()
          ..color = Colors.white
              .withValues(
            alpha: 0.75,
          );

    canvas.drawPath(
      smallPath,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _QiblaPointerPainter oldDelegate,
  ) {
    return oldDelegate.color !=
        color;
  }
}


// ============================================================
// SALATI QVP QURAN READER
// ============================================================


class _QuranReciter {
  final int id;
  final String name;
  final String moshafName;
  final String server;

  const _QuranReciter({
    required this.id,
    required this.name,
    required this.moshafName,
    required this.server,
  });

  factory _QuranReciter.fromJson(Map<String, dynamic> json) {
    final rawMoshaf = json['moshaf'];
    final list = rawMoshaf is List ? rawMoshaf : const <dynamic>[];

    Map<String, dynamic>? selected;
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final total = int.tryParse('${m['surah_total'] ?? 0}') ?? 0;
      final server = '${m['server'] ?? ''}'.trim();
      if (server.isEmpty) continue;
      if (total >= 114) {
        selected = m;
        break;
      }
      selected ??= m;
    }

    selected ??= <String, dynamic>{};

    final server = '${selected['server'] ?? ''}'.trim();
    final id = int.tryParse('${json['id'] ?? 5}') ?? 5;

    return _QuranReciter(
      id: id,
      name: '${json['name'] ?? 'قارئ'}'.trim(),
      moshafName: '${selected['name'] ?? 'رواية حفص عن عاصم'}'.trim(),
      server: server,
    );
  }
}

class _QuranTiming {
  final int ayah;
  final int startMs;
  final int endMs;

  const _QuranTiming({
    required this.ayah,
    required this.startMs,
    required this.endMs,
  });
}

class _LocalQuranAudio {
  final String path;
  final int reciterId;

  const _LocalQuranAudio({
    required this.path,
    required this.reciterId,
  });
}

class _QuranAudioSegment {
  final int surah;
  final int ayah;
  final int startMs;
  final int endMs;

  const _QuranAudioSegment({
    required this.surah,
    required this.ayah,
    required this.startMs,
    required this.endMs,
  });
}

class SalatiQuranReader extends StatefulWidget {
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  const SalatiQuranReader({
    super.key,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<SalatiQuranReader> createState() => _SalatiQuranReaderState();
}

class _SalatiQuranReaderState extends State<SalatiQuranReader>
    with WidgetsBindingObserver {
  // Keep the Quran index inside the reader state so every reader method
  // resolves the data explicitly and does not depend on outer scope lookup.
  static const List<String> _surahNames = surahNames;
  static const List<int> _surahStartPages = surahStartPages;
  static const int _firstPage = 1;
  static const int _lastPage = 604;
  static const String _lastQuranPageKey = 'salati_quran_last_page';

  QvpEngine? _engine;
  QvpPage? _page;
  QvpViewController? _viewController;
  GlobalKey<QvpPageViewState> _viewKey =
      GlobalKey<QvpPageViewState>();

  int _pageNumber = 1;
  int _highlightHandle = 0;
  bool _loading = true;
  String? _error;
  bool _systemUiHidden = false;
  bool _lastLandscape = false;
  bool _rotationRefreshing = false;
  int _qvpViewGeneration = 0;

  // Quran interaction/audio state. This layer is deliberately isolated from
  // the QVP rotation/scroll lifecycle below so the stable reader viewport is
  // not recreated by audio or long-press actions.
  final Dio _quranDio = Dio();
  final ja.AudioPlayer _quranPlayer = _quranBackgroundPlayer;
  Timer? _longPressTimer;
  Offset? _pointerDownPosition;
  int _longPressToken = 0;
  int _playbackToken = 0;
  int _lastStopSignal = 0;
  bool _audioBusy = false;
  bool _downloadBusy = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  int _repeatCount = 1;
  double _playbackSpeed = 1.0;
  _QuranReciter _selectedReciter = const _QuranReciter(
    id: 5,
    name: 'أحمد بن علي العجمي',
    moshafName: 'حفص عن عاصم',
    server: 'https://server10.mp3quran.net/ajm/',
  );
  List<_QuranReciter> _reciters = const <_QuranReciter>[];
  final Map<String, List<_QuranTiming>> _timingsCache = {};
  final Map<String, String> _downloadedAudioPaths = {};

  // MP3Quran exposes ayah-level timing only for a subset of reads. We keep
  // that catalogue locally so the app never makes a timing request for a
  // reader that cannot provide it. Full-surah offline playback does not
  // depend on timing data.
  Set<int> _timingReadIds = <int>{};
  bool _timingReadsLoaded = false;
  bool _timingReadsLoading = false;

  bool get _selectedReciterHasAyahTiming =>
      _timingReadIds.contains(_selectedReciter.id);

  bool get _isDark => widget.darkMode;

  void _onGlobalQuranStopSignal() {
    final signal = _quranStopSignal.value;
    if (signal == _lastStopSignal) return;
    _lastStopSignal = signal;
    _playbackToken++;
    _clearCurrentHighlight();
    if (mounted) {
      setState(() {
        _audioBusy = false;
      });
    }
  }

  void _clearCurrentHighlight() {
    final page = _page;
    if (page != null && !page.isDisposed && _highlightHandle != 0) {
      page.removeHighlight(_highlightHandle);
    }
    _highlightHandle = 0;
  }

  Future<void> _stopQuranPlayback({bool clearInfo = true}) async {
    _playbackToken++;
    try {
      await _quranPlayer.stop();
    } catch (_) {}
    _clearCurrentHighlight();
    if (clearInfo) {
      _quranPlaybackInfo.value = null;
    }
    if (mounted) {
      setState(() {
        _audioBusy = false;
      });
    }
  }

  void _recreateQvpViewport({bool replaceController = false}) {
    final oldController = _viewController;
    _qvpViewGeneration++;
    _viewKey = GlobalKey<QvpPageViewState>(
      debugLabel: 'salati-qvp-$_qvpViewGeneration',
    );

    if (replaceController) {
      _viewController = QvpViewController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (oldController != null && !identical(oldController, _viewController)) {
          oldController.dispose();
        }
      });
    }
  }

  int _surahNumberForPage(int page) {
    var result = 1;
    for (var i = 0; i < _surahStartPages.length; i++) {
      if (_surahStartPages[i] <= page) {
        result = i + 1;
      } else {
        break;
      }
    }
    return result;
  }

  String get _currentSurahName =>
      _surahNames[_surahNumberForPage(_pageNumber) - 1];

  String _padPage(int page) => page.toString().padLeft(3, '0');

  Future<ByteData> _loadQvpAsset(int page) async {
    final padded = _padPage(page);
    final candidates = <String>[
      'assets/quran/pages/$padded.qvp',
      'assets/qvp/pages/$padded.qvp',
      'assets/quran/$padded.qvp',
      'assets/qvp/$padded.qvp',
      'assets/pages/$padded.qvp',
    ];

    Object? lastError;

    for (final path in candidates) {
      try {
        return await rootBundle.load(path);
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(
      'لم يتم العثور على ملف صفحة المصحف $padded.qvp. '
      'تأكد من أن بيانات QVP مضافة إلى assets. '
      'آخر خطأ: $lastError',
    );
  }

  Future<String?> _loadWordsSidecar(int page) async {
    final padded = _padPage(page);
    final candidates = <String>[
      'assets/quran/pages/$padded.words.json',
      'assets/qvp/pages/$padded.words.json',
      'assets/quran/$padded.words.json',
      'assets/qvp/$padded.words.json',
      'assets/pages/$padded.words.json',
    ];

    for (final path in candidates) {
      try {
        return await rootBundle.loadString(path);
      } catch (_) {}
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _lastStopSignal = _quranStopSignal.value;
    _quranStopSignal.addListener(_onGlobalQuranStopSignal);
    WidgetsBinding.instance.addObserver(this);
    _viewController = QvpViewController();
    _initializeQuran();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSystemUi(MediaQuery.sizeOf(context).width >
        MediaQuery.sizeOf(context).height);
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.of(context);
    final logicalWidth = view.physicalSize.width / view.devicePixelRatio;
    final logicalHeight = view.physicalSize.height / view.devicePixelRatio;
    _syncSystemUi(logicalWidth > logicalHeight);

    // OrientationBuilder handles the QVP rebuild after the new size has
    // actually been laid out. Do not call QVP.fit() during this unstable
    // metrics transition because Android may emit several metric changes.
  }

  void _refreshQvpAfterRotation(bool landscape) {
    if (!mounted || _rotationRefreshing) return;

    // Android can resize the Flutter window before the QVP renderer has
    // finished adapting to the new viewport. Rebuilding only the QVP view
    // after the new orientation is laid out avoids the persistent grey/blank
    // surface while keeping the same decoded Quran page.
    setState(() => _rotationRefreshing = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final oldController = _viewController;
      _qvpViewGeneration++;
      _viewKey = GlobalKey<QvpPageViewState>(
        debugLabel: 'salati-qvp-rotation-$_qvpViewGeneration',
      );
      _viewController = QvpViewController();

      oldController?.dispose();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _rotationRefreshing = false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _page == null) return;
          _fitReaderForOrientation(landscape);
        });
      });
    });
  }

  void _syncSystemUi(bool _) {
    // The Quran section is a true reading mode: hide the status/navigation
    // bars in both portrait and landscape, without affecting other sections.
    if (!_systemUiHidden) {
      _systemUiHidden = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _initializeQuran() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPage = prefs.getInt(_lastQuranPageKey);
      if (savedPage != null &&
          savedPage >= _firstPage &&
          savedPage <= _lastPage) {
        _pageNumber = savedPage;
      }

      final engine = QvpEngine.open();
      if (!mounted) {
        engine.dispose();
        return;
      }

      setState(() {
        _engine = engine;
        _loading = true;
        _error = null;
      });

      await _loadPage(_pageNumber, initial: true);
    } catch (e, st) {
      debugPrint('QVP Quran initialization error: $e\n$st');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadPage(
    int requestedPage, {
    bool initial = false,
  }) async {
    final engine = _engine;
    if (engine == null) return;

    final target = requestedPage.clamp(_firstPage, _lastPage);

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _loadQvpAsset(target);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      final newPage = engine.loadPage(bytes);

      final words = await _loadWordsSidecar(target);
      if (words != null) {
        newPage.attachWords(words);
      }

      final oldPage = _page;

      if (!mounted) {
        newPage.dispose();
        return;
      }

      // Give every loaded page a fresh QVP view state. This avoids a stale
      // renderer/viewport surviving a page change, which is especially
      // important in dark mode where the next page could otherwise render
      // as an almost-black surface on some GPUs.
      _recreateQvpViewport();

      setState(() {
        _page = newPage;
        _pageNumber = target;
        _loading = false;
        _error = null;
        _highlightHandle = 0;
      });

      // Persist the last Quran page so rotation/recreation never returns
      // the reader to Al-Fatihah. This also restores the same page after
      // reopening the Quran section or restarting the app.
      unawaited(_saveLastQuranPage(target));

      if (oldPage != null && !oldPage.isDisposed) {
        // Do not dispose the previous QVP page in the same frame as the new
        // page is attached. On some devices/GPUs that can invalidate the
        // renderer and leave the next dark-mode page almost black.
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          if (!oldPage.isDisposed) {
            oldPage.dispose();
          }
        });
      }

      _fitReaderForOrientation(
        MediaQuery.sizeOf(context).width >
            MediaQuery.sizeOf(context).height,
      );
    } catch (e, st) {
      debugPrint('QVP page load error ($target): $e\n$st');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _fitReaderForOrientation(bool landscape, {int retry = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _page == null) return;

      // First fit the complete printed page. A second frame is used because
      // QVP applies the fit after the current layout pass.
      _viewKey.currentState?.fit();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _page == null) return;

        if (!landscape) {
          _viewController?.fit();
          return;
        }

        final layout = _page!.currentLayout;
        final controller = _viewController;
        final viewport = controller?.viewport ?? Size.zero;
        if (layout == null || controller == null || viewport.width <= 0) {
          // Rotation can take a few layout frames on Android. Retry a small
          // bounded number of times instead of leaving the landscape reader
          // blank or creating an endless post-frame loop.
          if (retry < 3) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _fitReaderForOrientation(landscape, retry: retry + 1);
              }
            });
          }
          return;
        }

        // The current layout is fitted to the landscape height. Calculate the
        // exact magnification needed to make the printed page almost as wide
        // as the screen. This is intentionally based on the actual viewport
        // rather than a fixed 1.28x value, so it adapts to every phone size.
        final fittedWidth =
            layout.contentW * layout.scale * controller.scale;
        if (fittedWidth <= 0) return;

        final targetWidth = viewport.width * 0.96;
        final factor = (targetWidth / fittedWidth)
            .clamp(1.0, 3.5)
            .toDouble();

        controller.zoomBy(factor);

        // Keep the enlarged page inside vertical reading bounds after the
        // programmatic landscape zoom. The user can then drag from top to
        // bottom without the page getting stuck at an invalid offset.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _page == null) return;
          final latestLayout = _page!.currentLayout;
          final latestViewport = controller.viewport;
          if (latestLayout == null || latestViewport.height <= 0) return;
          final renderedHeight = latestLayout.contentH *
              latestLayout.scale *
              controller.scale;
          if (renderedHeight <= latestViewport.height) return;
          final topLimit = -latestLayout.offsetY;
          final bottomLimit = latestViewport.height -
              (latestLayout.offsetY + renderedHeight);
          controller.offsetY = controller.offsetY.clamp(
            bottomLimit,
            topLimit,
          ).toDouble();
          controller.notifyListeners();
        });
      });
    });
  }

  Future<void> _saveLastQuranPage(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastQuranPageKey, page);
    } catch (e) {
      debugPrint('Quran last-page save error: $e');
    }
  }

  ({double min, double max})? _landscapeVerticalBounds() {
    final page = _page;
    final controller = _viewController;
    if (page == null || controller == null) return null;

    final layout = page.currentLayout;
    final viewport = controller.viewport;
    if (layout == null || viewport.height <= 0 || layout.slots.isEmpty) {
      return null;
    }

    // QVP exposes each printed line's top/bottom in layout viewport pixels.
    // Using these actual line bounds is more reliable than using contentH: it
    // lets the very last line become visible instead of stopping early because
    // of the page's internal bottom padding.
    var firstTop = double.infinity;
    var lastBottom = double.negativeInfinity;
    for (final slot in layout.slots) {
      if (slot.$1 < firstTop) firstTop = slot.$1;
      if (slot.$2 > lastBottom) lastBottom = slot.$2;
    }

    if (!firstTop.isFinite || !lastBottom.isFinite) return null;

    final scale = controller.scale;
    const edgePadding = 14.0;

    // QVP's view transform is offset + layoutPx * controller.scale.
    // Positive finger-down movement moves the page down; negative movement
    // (swipe upward) moves the page toward the final Quran lines.
    final minOffset =
        viewport.height - (layout.offsetY + lastBottom * scale) - edgePadding;
    final maxOffset =
        -(layout.offsetY + firstTop * scale) + edgePadding;

    if (minOffset >= maxOffset) return null;
    return (min: minOffset, max: maxOffset);
  }

  void _panLandscapeVertically(double deltaY) {
    final controller = _viewController;
    final bounds = _landscapeVerticalBounds();
    if (controller == null || bounds == null) return;

    final nextOffsetY = (controller.offsetY + deltaY).clamp(
      bounds.min,
      bounds.max,
    );

    controller.set(offsetY: nextOffsetY.toDouble());
    controller.refresh();
  }

  void _previousPage() {
    if (_loading) return;
    if (_pageNumber > _firstPage) {
      _loadPage(_pageNumber - 1);
    }
  }

  void _nextPage() {
    if (_loading) return;
    if (_pageNumber < _lastPage) {
      _loadPage(_pageNumber + 1);
    }
  }

  Future<void> _showSurahPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * .78,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        Icon(Icons.menu_book_rounded),
                        SizedBox(width: 10),
                        Text(
                          'سور القرآن الكريم',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                      itemCount: _surahNames.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final page = _surahStartPages[index];
                        final selected = index + 1 ==
                            _surahNumberForPage(_pageNumber);

                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              const Color(0xFF176B52).withValues(alpha: .10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: selected
                                ? const Color(0xFF176B52)
                                : const Color(0xFFE8F0EB),
                            foregroundColor: selected
                                ? Colors.white
                                : const Color(0xFF176B52),
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            'سورة ${_surahNames[index]}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text('صفحة $page'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FutureBuilder<String?>(
                                future: _downloadedPathIfExists(index + 1),
                                builder: (context, snapshot) {
                                  final downloaded = snapshot.data != null;
                                  return IconButton(
                                    tooltip: downloaded ? 'محملة' : 'تحميل السورة',
                                    onPressed: downloaded
                                        ? null
                                        : () async {
                                            Navigator.pop(sheetContext);
                                            await Future<void>.delayed(const Duration(milliseconds: 120));
                                            if (!mounted) return;
                                            await _runOfflineDownloadWithProgress(
                                              title: 'تحميل سورة ${_surahNames[index]}',
                                              completionMessage: 'تم تحميل سورة ${_surahNames[index]} بنجاح للاستماع بدون إنترنت',
                                              task: (report) => _downloadSurahAudio(
                                                index + 1,
                                                onProgress: report,
                                              ),
                                            );
                                          },
                                    icon: Icon(
                                      downloaded
                                          ? Icons.download_done_rounded
                                          : Icons.download_for_offline_rounded,
                                      color: downloaded
                                          ? const Color(0xFF176B52)
                                          : null,
                                    ),
                                  );
                                },
                              ),
                              const Icon(Icons.chevron_left_rounded),
                            ],
                          ),
                          onTap: () =>
                              Navigator.pop(sheetContext, page),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      await _loadPage(selected);
    }
  }

  void _highlightWord(int word) {
    final page = _page;
    if (page == null || page.isDisposed || word < 0) return;

    if (_highlightHandle != 0) {
      page.removeHighlight(_highlightHandle);
    }

    _highlightHandle = page.highlight(
      T.word(word),
      const QvpHighlightStyle(
        mode: 'both',
        ink: '#176B52',
        band: '#2F806533',
        radius: 1.5,
        ms: 180,
      ),
    );

    setState(() {});
  }


  bool _pageContainsAyah(QvpPage page, int surah, int ayah) {
    if (page.isDisposed) return false;
    for (final key in page.ayahKeys()) {
      if (key.$1 == surah && key.$2 == ayah) return true;
    }
    return false;
  }

  void _highlightRecitationAyah(int surah, int ayah) {
    final page = _page;
    if (page == null || page.isDisposed || surah <= 0 || ayah <= 0) return;

    if (_highlightHandle != 0) {
      page.removeHighlight(_highlightHandle);
    }

    _highlightHandle = page.highlight(
      T.ayah(surah, ayah),
      const QvpHighlightStyle(
        mode: 'both',
        ink: '#176B52',
        band: '#176B5233',
        radius: 1.5,
        ms: 180,
      ),
    );

    if (mounted) setState(() {});
  }

  Future<bool> _syncQuranPageToAyah(
    int surah,
    int ayah,
    int token,
  ) async {
    if (token != _playbackToken || !mounted) return false;

    final current = _page;
    if (current != null && _pageContainsAyah(current, surah, ayah)) {
      _highlightRecitationAyah(surah, ayah);
      return true;
    }

    // Timings are ayah-based. When playback reaches an ayah that is not on
    // the currently displayed Mushaf page, move forward page-by-page until
    // the exact ayah is found. This keeps the printed Mushaf itself unchanged
    // and lets QVP determine the real ayah boundaries on each page.
    final surahStart = _surahStartPages[surah - 1];
    final currentPage = _pageNumber;
    final forwardStart = currentPage < surahStart ? surahStart : currentPage + 1;

    for (var candidate = forwardStart; candidate <= _lastPage; candidate++) {
      if (token != _playbackToken || !mounted) return false;

      if (candidate != _pageNumber) {
        await _loadPage(candidate);
      }

      final loaded = _page;
      if (loaded != null && _pageContainsAyah(loaded, surah, ayah)) {
        _highlightRecitationAyah(surah, ayah);
        return true;
      }

      // Once we have moved beyond this surah, there is no reason to continue
      // scanning the remaining 604-page Mushaf.
      if (_surahNumberForPage(_pageNumber) > surah) break;
    }

    // This is mainly for the case where the user manually moved the Mushaf
    // ahead while audio was already playing. Search backward inside the same
    // surah without inventing any page/ayah mapping.
    final backwardEnd = currentPage - 1;
    for (var candidate = backwardEnd; candidate >= surahStart; candidate--) {
      if (token != _playbackToken || !mounted) return false;
      await _loadPage(candidate);
      final loaded = _page;
      if (loaded != null && _pageContainsAyah(loaded, surah, ayah)) {
        _highlightRecitationAyah(surah, ayah);
        return true;
      }
    }

    return false;
  }

  Future<bool> _prepareRecitationSegment(
    _QuranAudioSegment segment,
    int token,
  ) async {
    if (token != _playbackToken || !mounted) return false;

    final ok = await _syncQuranPageToAyah(
      segment.surah,
      segment.ayah,
      token,
    );

    if (!ok) {
      debugPrint(
        'Quran recitation sync: ayah ${segment.surah}:${segment.ayah} was not found on a QVP page.',
      );
    }

    return ok && token == _playbackToken;
  }


  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pointerDownPosition = null;
  }

  void _onQuranPointerDown(PointerDownEvent event) {
    _cancelLongPress();
    _pointerDownPosition = event.localPosition;
    final token = ++_longPressToken;
    _longPressTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || token != _longPressToken) return;
      final position = _pointerDownPosition;
      if (position == null) return;
      _openAyahActionsAt(position);
    });
  }

  void _onQuranPointerMove(PointerMoveEvent event) {
    final start = _pointerDownPosition;
    if (start == null) return;
    if ((event.localPosition - start).distance > 14) {
      _cancelLongPress();
      _longPressToken++;
    }
  }

  void _onQuranPointerUp(PointerEvent event) {
    _cancelLongPress();
    _longPressToken++;
  }

  Future<void> _openAyahActionsForWord(int wordIndex) async {
    final page = _page;
    if (page == null || page.isDisposed) return;
    if (wordIndex < 0 || wordIndex >= page.words.length) return;

    final word = page.words[wordIndex];
    final surah = word.surah;
    final ayah = word.ayah;
    if (surah <= 0 || ayah <= 0) return;

    if (_highlightHandle != 0 && !page.isDisposed) {
      page.removeHighlight(_highlightHandle);
    }
    _highlightHandle = page.highlight(
      T.ayah(surah, ayah),
      const QvpHighlightStyle(
        mode: 'both',
        ink: '#176B52',
        band: '#176B5233',
        radius: 1.5,
        ms: 220,
      ),
    );
    if (mounted) setState(() {});

    await _loadRecitersIfNeeded();
    if (!mounted) return;
    await _showAyahActionsSheet(surah, ayah);
  }

  Future<void> _openAyahActionsAt(Offset position) async {
    final page = _page;
    if (page == null || page.isDisposed) return;

    final hit = page.hitTestView(position.dx, position.dy);
    if (hit == null || hit.word < 0 || hit.word >= page.words.length) {
      return;
    }

    final word = page.words[hit.word];
    final surah = word.surah;
    final ayah = word.ayah;
    if (surah <= 0 || ayah <= 0) return;

    if (_highlightHandle != 0 && !page.isDisposed) {
      page.removeHighlight(_highlightHandle);
    }
    _highlightHandle = page.highlight(
      T.ayah(surah, ayah),
      const QvpHighlightStyle(
        mode: 'both',
        ink: '#176B52',
        band: '#176B5233',
        radius: 1.5,
        ms: 220,
      ),
    );
    if (mounted) setState(() {});

    await _loadRecitersIfNeeded();
    if (!mounted) return;
    await _showAyahActionsSheet(surah, ayah);
  }

  Future<void> _loadTimingReadIds() async {
    if (_timingReadsLoaded || _timingReadsLoading) return;
    _timingReadsLoading = true;
    try {
      final response = await _quranDio.get(
        'https://mp3quran.net/api/v3/ayat_timing/reads',
        options: Options(responseType: ResponseType.json),
      );
      final raw = response.data;
      final ids = <int>{};
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final id = int.tryParse('${item['id'] ?? 0}') ?? 0;
          if (id > 0) ids.add(id);
        }
      }
      _timingReadIds = ids;
      _timingReadsLoaded = true;
    } catch (e) {
      // Do not block the reciter list if the timing catalogue is temporarily
      // unavailable. A later timing request can still be attempted for a
      // reader whose timings are already known/cached.
      debugPrint('Quran timing reads load error: $e');
    } finally {
      _timingReadsLoading = false;
    }
  }

  Future<void> _loadRecitersIfNeeded() async {
    if (_reciters.isNotEmpty) {
      await _loadTimingReadIds();
      return;
    }

    try {
      final responses = await Future.wait<dynamic>([
        _quranDio.get(
          'https://mp3quran.net/api/v3/reciters',
          queryParameters: const {'language': 'ar'},
          options: Options(responseType: ResponseType.json),
        ),
        _quranDio.get(
          'https://mp3quran.net/api/v3/ayat_timing/reads',
          options: Options(responseType: ResponseType.json),
        ),
      ], eagerError: false);

      final reciterResponse = responses.isNotEmpty ? responses[0] : null;
      final timingResponse = responses.length > 1 ? responses[1] : null;

      final timingIds = <int>{};
      final timingRaw = timingResponse?.data;
      if (timingRaw is List) {
        for (final item in timingRaw) {
          if (item is! Map) continue;
          final id = int.tryParse('${item['id'] ?? 0}') ?? 0;
          if (id > 0) timingIds.add(id);
        }
      }
      if (timingIds.isNotEmpty) {
        _timingReadIds = timingIds;
        _timingReadsLoaded = true;
      }

      final raw = reciterResponse?.data is Map
          ? reciterResponse.data['reciters']
          : null;
      if (raw is List) {
        final list = <_QuranReciter>[];
        for (final item in raw) {
          if (item is! Map) continue;
          try {
            final reciter = _QuranReciter.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (reciter.server.isNotEmpty) list.add(reciter);
          } catch (_) {}
        }
        if (list.isNotEmpty && mounted) {
          setState(() {
            _reciters = list;
            if (!_reciters.any((r) => r.id == _selectedReciter.id)) {
              _selectedReciter = _reciters.first;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Quran reciters load error: $e');
    }

    if (!_timingReadsLoaded) {
      await _loadTimingReadIds();
    }
  }

  Future<void> _showAyahActionsSheet(int surah, int ayah) async {
    final page = _page;
    if (page == null || page.isDisposed) return;

    final ayahText = page.text(T.ayah(surah, ayah)).trim();
    final surahName = surah >= 1 && surah <= _surahNames.length
        ? _surahNames[surah - 1]
        : 'السورة $surah';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF176B52), Color(0xFF0D4939)],
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Icon(
                            Icons.menu_book_rounded,
                            color: Color(0xFFE2BD63),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'سورة $surahName • الآية $ayah',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'صفحة $_pageNumber • ${_selectedReciter.name}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (ayahText.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '﴿ $ayahText ﴾',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.play_circle_fill_rounded,
                      title: 'استماع إلى الآية',
                      subtitle: 'تشغيل الآية المحددة فقط',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _playAyah(surah, ayah);
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.library_music_rounded,
                      title: 'استماع إلى الصفحة',
                      subtitle: 'تشغيل آيات الصفحة الحالية من بدايتها',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _playCurrentPage();
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.menu_book_rounded,
                      title: 'استماع إلى السورة كاملة',
                      subtitle: 'من بداية السورة إلى نهايتها',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _playSurah(surah);
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.download_for_offline_rounded,
                      title: 'تحميل للاستماع بدون إنترنت',
                      subtitle: 'الآية أو الصفحة أو السورة حسب اختيارك',
                      onTap: () async {
                        await _showDownloadPicker(sheetContext, surah, ayah);
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.repeat_rounded,
                      title: 'التكرار',
                      subtitle: 'عدد مرات تكرار الآية أو المقطع',
                      onTap: () async {
                        await _showRepeatPicker(sheetContext);
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.speed_rounded,
                      title: 'سرعة التلاوة',
                      subtitle: '${_playbackSpeed.toStringAsFixed(2)}×',
                      onTap: () async {
                        await _showSpeedPicker(sheetContext);
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.person_rounded,
                      title: 'اختيار القارئ',
                      subtitle: '${_selectedReciter.name} — ${_selectedReciter.moshafName}',
                      onTap: () async {
                        await _showReciterPicker(sheetContext);
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.menu_book_outlined,
                      title: 'تفسير الآية',
                      subtitle: 'عرض التفسير في صفحة مستقلة داخل التطبيق',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _showTafsir(surah, ayah, ayahText, surahName);
                      },
                    ),
                    _quranActionTile(
                      sheetContext,
                      icon: Icons.copy_rounded,
                      title: 'نسخ الآية',
                      subtitle: 'نسخ نص الآية إلى الحافظة',
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: ayahText));
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('تم نسخ الآية')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _quranActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF176B52).withValues(alpha: .10),
        foregroundColor: const Color(0xFF176B52),
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    );
  }

  Future<void> _showDownloadPicker(
    BuildContext context,
    int surah,
    int ayah,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.download_for_offline_rounded),
                title: Text(
                  'ماذا تريد حفظه؟',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  'يظهر لك تقدم التحميل، وعند الاكتمال يصلك إشعار بالحفظ.',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.format_quote_rounded),
                title: const Text('تحميل الآية'),
                subtitle: const Text(
                  'يحفظ تلاوة السورة الحاوية للآية لاستخدامها أوفلاين.',
                ),
                onTap: () => Navigator.pop(sheetContext, 'ayah'),
              ),
              ListTile(
                leading: const Icon(Icons.library_music_rounded),
                title: const Text('تحميل الصفحة'),
                subtitle: const Text(
                  'يحفظ سور الصفحة المطلوبة للاستماع إليها بدون إنترنت.',
                ),
                onTap: () => Navigator.pop(sheetContext, 'page'),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: const Text('تحميل السورة كاملة'),
                subtitle: const Text('يحفظ السورة كاملة على الجهاز.'),
                onTap: () => Navigator.pop(sheetContext, 'surah'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    // Close the action sheet before showing the in-page download indicator.
    // The download UI is now part of the Quran reader itself, so it cannot
    // disappear behind a modal route.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    try {
      if (choice == 'surah' || choice == 'ayah') {
        await _runOfflineDownloadWithProgress(
          title: choice == 'surah' ? 'تحميل السورة' : 'تحميل الآية',
          completionMessage: choice == 'surah'
              ? 'تم تحميل سورة ${_surahNames[surah - 1]} بنجاح للاستماع بدون إنترنت'
              : 'تم تحميل تلاوة الآية $ayah من سورة ${_surahNames[surah - 1]} للاستماع بدون إنترنت',
          task: (report) => _downloadSurahAudio(
            surah,
            onProgress: report,
          ),
        );
        return;
      }

      final page = _page;
      if (page == null) return;
      final surahs = <int>{};
      for (final key in page.ayahKeys()) {
        surahs.add(key.$1);
      }
      final orderedSurahs = surahs.toList()..sort();

      if (orderedSurahs.isEmpty) return;

      await _runOfflineDownloadWithProgress(
        title: 'تحميل الصفحة $_pageNumber',
        completionMessage: 'تم تحميل تلاوات الصفحة $_pageNumber بنجاح للاستماع بدون إنترنت',
        task: (report) async {
          for (var i = 0; i < orderedSurahs.length; i++) {
            final current = orderedSurahs[i];
            final base = i / orderedSurahs.length;
            final share = 1.0 / orderedSurahs.length;
            await _downloadSurahAudio(
              current,
              showMessage: false,
              onProgress: (fileProgress) {
                report(base + (fileProgress * share));
              },
            );
            report((i + 1) / orderedSurahs.length);
          }
        },
      );
    } catch (e) {
      if (mounted) _showAudioError(e);
    }
  }

  Future<void> _runOfflineDownloadWithProgress({
    required String title,
    required String completionMessage,
    required Future<void> Function(ValueChanged<double> report) task,
  }) async {
    if (!mounted) return;

    setState(() {
      _downloadBusy = true;
      _downloadProgress = 0.0;
      _downloadStatus = title;
    });

    Object? taskError;
    try {
      await task((value) {
        final safe = value.clamp(0.0, 1.0).toDouble();
        if (!mounted) return;
        setState(() {
          _downloadProgress = safe;
          _downloadStatus = '$title — ${(safe * 100).round()}%';
        });
      });

      if (mounted) {
        setState(() {
          _downloadProgress = 1.0;
          _downloadStatus = 'اكتمل التحميل';
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 650));
    } catch (e) {
      taskError = e;
      if (mounted) {
        setState(() {
          _downloadStatus = 'فشل التحميل';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadBusy = false;
          _downloadProgress = 0.0;
          _downloadStatus = '';
        });
      }
    }

    if (!mounted) return;

    if (taskError == null) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(completionMessage)),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      _showAudioError(taskError!);
    }
  }

  Widget _buildReaderPlaybackBar(BuildContext context) {
    return ValueListenableBuilder<_QuranPlaybackInfo?>(
      valueListenable: _quranPlaybackInfo,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: SafeArea(
            top: false,
            child: Material(
              elevation: 12,
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: StreamBuilder<ja.PlayerState>(
                  stream: _quranPlayer.playerStateStream,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final playing = state?.playing ?? _quranPlayer.playing;
                    final loading = state?.processingState == ja.ProcessingState.loading ||
                        state?.processingState == ja.ProcessingState.buffering;
                    return Row(
                      children: [
                        Icon(Icons.menu_book_rounded, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${info.surahName} • ${info.reciterName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                        IconButton(
                          tooltip: playing ? 'إيقاف مؤقت' : 'تشغيل',
                          onPressed: loading
                              ? null
                              : () async {
                                  if (_quranPlayer.playing) {
                                    await _quranPlayer.pause();
                                  } else {
                                    await _quranPlayer.play();
                                  }
                                },
                          icon: Icon(
                            playing
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                          ),
                          iconSize: 32,
                        ),
                        IconButton(
                          tooltip: 'إيقاف نهائي',
                          onPressed: () => _stopQuranPlayback(),
                          icon: const Icon(Icons.stop_circle_rounded),
                          iconSize: 29,
                        ),
                        IconButton(
                          tooltip: 'إغلاق وإيقاف نهائي',
                          onPressed: () => _stopQuranPlayback(),
                          icon: const Icon(Icons.close_rounded),
                          iconSize: 23,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadProgressOverlay(BuildContext context) {
    if (!_downloadBusy) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final progress = _downloadProgress.clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    return Positioned(
      left: 14,
      right: 14,
      bottom: 10,
      child: IgnorePointer(
        child: Material(
          elevation: 10,
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress > 0 ? progress : null,
                            strokeWidth: 4,
                            color: scheme.primary,
                            backgroundColor: scheme.primary.withValues(alpha: 0.10),
                          ),
                          Icon(
                            progress >= 1.0
                                ? Icons.check_rounded
                                : Icons.download_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _downloadStatus.isEmpty ? 'جاري التحميل…' : _downloadStatus,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            progress > 0
                                ? 'يتم الحفظ على الجهاز للاستماع بدون إنترنت'
                                : 'جاري بدء التحميل…',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 7,
                    color: scheme.primary,
                    backgroundColor: scheme.primary.withValues(alpha: 0.10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRepeatPicker(BuildContext context) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('عدد مرات التكرار', style: TextStyle(fontWeight: FontWeight.w900))),
              for (final n in const [1, 2, 3, 5, 10, 20])
                ListTile(
                  title: Text(n == 1 ? 'مرة واحدة' : '$n مرات'),
                  trailing: _repeatCount == n ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(sheetContext, n),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null && mounted) setState(() => _repeatCount = value);
  }

  Future<void> _showSpeedPicker(BuildContext context) async {
    final value = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('سرعة التلاوة', style: TextStyle(fontWeight: FontWeight.w900))),
              for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5])
                ListTile(
                  title: Text('${speed.toStringAsFixed(2)}×'),
                  trailing: _playbackSpeed == speed ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(sheetContext, speed),
                ),
            ],
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      setState(() => _playbackSpeed = value);
      if (_audioBusy) {
        try {
          await _quranPlayer.setSpeed(value);
        } catch (_) {}
      }
    }
  }

  Future<void> _showReciterPicker(BuildContext context) async {
    await _loadRecitersIfNeeded();
    if (!mounted) return;
    final value = await showModalBottomSheet<_QuranReciter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .70,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
              itemCount: _reciters.isEmpty ? 1 : _reciters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 5),
              itemBuilder: (context, index) {
                if (_reciters.isEmpty) {
                  return const ListTile(
                    title: Text('تعذر تحميل قائمة القراء حالياً'),
                    subtitle: Text('سيبقى القارئ الافتراضي متاحاً.'),
                  );
                }
                final reciter = _reciters[index];
                final selected = reciter.id == _selectedReciter.id;
                return ListTile(
                  selected: selected,
                  selectedTileColor: const Color(0xFF176B52).withValues(alpha: .08),
                  leading: CircleAvatar(
                    backgroundColor: selected
                        ? const Color(0xFF176B52)
                        : const Color(0xFFE8F0EB),
                    foregroundColor: selected ? Colors.white : const Color(0xFF176B52),
                    child: const Icon(Icons.person_rounded, size: 20),
                  ),
                  title: Text(reciter.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reciter.moshafName),
                      const SizedBox(height: 3),
                      Text(
                        _timingReadIds.contains(reciter.id)
                            ? '✓ يدعم تشغيل الآيات والصفحات أوفلاين'
                            : '✓ يدعم السورة كاملة أوفلاين • بدون توقيت منفصل للآيات',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: _timingReadIds.contains(reciter.id)
                              ? const Color(0xFF176B52)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
                  onTap: () => Navigator.pop(sheetContext, reciter),
                );
              },
            ),
          ),
        ),
      ),
    );
    if (value != null && mounted) setState(() => _selectedReciter = value);
  }

  Future<List<_QuranTiming>> _getTimings(int surah) async {
    final key = '${_selectedReciter.id}:$surah';
    final cached = _timingsCache[key];
    if (cached != null) return cached;

    // Do not repeatedly call the timing endpoint for readers that are not
    // published in MP3Quran's timing catalogue. Full-surah playback remains
    // available offline for those readers.
    if (!_timingReadsLoaded) {
      await _loadTimingReadIds();
    }
    if (_timingReadsLoaded && !_selectedReciterHasAyahTiming) {
      _timingsCache[key] = <_QuranTiming>[];
      return const <_QuranTiming>[];
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('quran_timing_$key');
      if (saved != null && saved.isNotEmpty) {
        final decoded = jsonDecode(saved);
        if (decoded is List) {
          final list = decoded
              .whereType<Map>()
              .map((e) => _QuranTiming(
                    ayah: int.tryParse('${e['ayah'] ?? 0}') ?? 0,
                    startMs: int.tryParse('${e['start'] ?? 0}') ?? 0,
                    endMs: int.tryParse('${e['end'] ?? 0}') ?? 0,
                  ))
              .where((e) => e.ayah > 0 && e.endMs > e.startMs)
              .toList();
          if (list.isNotEmpty) {
            _timingsCache[key] = list;
            return list;
          }
        }
      }
    } catch (_) {}

    final response = await _quranDio.get(
      'https://mp3quran.net/api/v3/ayat_timing',
      queryParameters: {
        'surah': surah,
        'read': _selectedReciter.id,
      },
      options: Options(responseType: ResponseType.json),
    );

    final raw = response.data;
    final list = <_QuranTiming>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final ayah = int.tryParse('${item['ayah'] ?? 0}') ?? 0;
        final start = int.tryParse('${item['start_time'] ?? 0}') ?? 0;
        final end = int.tryParse('${item['end_time'] ?? 0}') ?? 0;
        if (ayah > 0 && end > start) {
          list.add(_QuranTiming(ayah: ayah, startMs: start, endMs: end));
        }
      }
    }

    _timingsCache[key] = list;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'quran_timing_$key',
        jsonEncode(list.map((e) => {
              'ayah': e.ayah,
              'start': e.startMs,
              'end': e.endMs,
            }).toList()),
      );
    } catch (_) {}

    return list;
  }

  Future<String> _surahAudioUrl(int surah) async {
    if (_selectedReciter.server.isEmpty) {
      throw Exception('لا يوجد رابط صوتي لهذا القارئ.');
    }
    final padded = surah.toString().padLeft(3, '0');
    return '${_selectedReciter.server}$padded.mp3';
  }

  Future<String> _localAudioPathForReciter(int reciterId, int surah) async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/quran_audio/$reciterId');
    if (!audioDir.existsSync()) {
      await audioDir.create(recursive: true);
    }
    return '${audioDir.path}/${surah.toString().padLeft(3, '0')}.mp3';
  }

  Future<String> _localAudioPath(int surah) =>
      _localAudioPathForReciter(_selectedReciter.id, surah);

  Future<String?> _downloadedPathIfExists(int surah) async {
    final cached = _downloadedAudioPaths['${_selectedReciter.id}:$surah'];
    if (cached != null && File(cached).existsSync()) {
      final length = await File(cached).length();
      if (length > 1024) return cached;
    }

    final path = await _localAudioPath(surah);
    final file = File(path);
    if (file.existsSync() && await file.length() > 1024) {
      _downloadedAudioPaths['${_selectedReciter.id}:$surah'] = path;
      return path;
    }
    return null;
  }

  // Finds a previously downloaded copy even when the user changed the
  // selected reciter after downloading it. This is important for true
  // offline playback: a saved MP3 must never be ignored just because the
  // current online reciter selection is different.
  Future<_LocalQuranAudio?> _findAnyDownloadedAudio(int surah) async {
    final selected = await _downloadedPathIfExists(surah);
    if (selected != null) {
      return _LocalQuranAudio(
        path: selected,
        reciterId: _selectedReciter.id,
      );
    }

    try {
      final root = await getApplicationDocumentsDirectory();
      final rootDir = Directory('${root.path}/quran_audio');
      if (!rootDir.existsSync()) return null;

      final filename = '${surah.toString().padLeft(3, '0')}.mp3';
      for (final entity in rootDir.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        final reciterId = int.tryParse(name);
        if (reciterId == null) continue;

        final file = File('${entity.path}/$filename');
        if (file.existsSync() && await file.length() > 1024) {
          final path = file.path;
          _downloadedAudioPaths['$reciterId:$surah'] = path;
          return _LocalQuranAudio(
            path: path,
            reciterId: reciterId,
          );
        }
      }
    } catch (e) {
      debugPrint('Offline Quran file scan error: $e');
    }

    return null;
  }

  Future<bool> _hasCachedTimings(int surah) async {
    final key = '${_selectedReciter.id}:$surah';
    if (_timingsCache[key]?.isNotEmpty == true) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('quran_timing_$key');
      return saved != null && saved.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String> _downloadSurahAudio(
    int surah, {
    bool showMessage = true,
    ValueChanged<double>? onProgress,
  }) async {
    final path = await _localAudioPath(surah);
    final file = File(path);

    // A Quran download is considered complete only when the audio file is
    // stored locally. Timing data is cached separately so ayah/page playback
    // can seek inside that local file while the device is completely offline.
    if (file.existsSync()) {
      _downloadedAudioPaths['${_selectedReciter.id}:$surah'] = path;
      onProgress?.call(1.0);

      // Older app versions saved only the MP3. If timing data is missing,
      // try to cache it now while internet is available. Never delete the
      // already-downloaded audio if the timing request happens to fail.
      if (!await _hasCachedTimings(surah)) {
        try {
          await _getTimings(surah);
        } catch (e) {
          debugPrint('Offline timing cache repair error: $e');
        }
      }

      if (showMessage && mounted) {
        final ready = await _hasCachedTimings(surah);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ready
                  ? 'التلاوة محفوظة بالكامل للاستماع بدون إنترنت'
                  : 'التلاوة محفوظة، ولتشغيل الآيات منفردة يجب تحميلها مرة واحدة مع توفر الإنترنت',
            ),
          ),
        );
      }
      return path;
    }

    if (showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري تحميل التلاوة وبيانات الآيات للاستماع بدون إنترنت…')),
      );
    }

    final url = await _surahAudioUrl(surah);
    final tempPath = '$path.part';
    final tempFile = File(tempPath);

    try {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }

      // Download to a temporary file first. This prevents a failed/partial
      // network transfer from being mistaken for a valid offline recording.
      await _quranDio.download(
        url,
        tempPath,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total).clamp(0.0, 1.0);
            onProgress?.call(progress);
          }
        },
      );

      if (!tempFile.existsSync() || await tempFile.length() == 0) {
        throw Exception('لم يكتمل تحميل ملف التلاوة.');
      }

      if (file.existsSync()) {
        await file.delete();
      }
      await tempFile.rename(path);
      _downloadedAudioPaths['${_selectedReciter.id}:$surah'] = path;

      // Cache ayah timing data when this reader supports it. Readers that
      // are not in the timing catalogue are still fully usable offline for
      // whole-surah playback; only exact ayah/page seeking needs timings.
      if (_selectedReciterHasAyahTiming) {
        try {
          final timings = await _getTimings(surah);
          if (timings.isEmpty) {
            debugPrint('No timing data cached for surah $surah');
          }
        } catch (e) {
          debugPrint('Quran timing cache error after audio download: $e');
        }
      }

      if (showMessage && mounted) {
        final ready = await _hasCachedTimings(surah);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ready || !_selectedReciterHasAyahTiming
                  ? 'تم حفظ سورة ${_surahNames[surah - 1]} بالكامل للاستماع بدون إنترنت'
                  : 'تم حفظ سورة ${_surahNames[surah - 1]}، لكن توقيت الآيات غير متاح لهذا القارئ.',
            ),
          ),
        );
      }

      return path;
    } catch (e) {
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _playAyah(int surah, int ayah) async {
    try {
      final local = await _findAnyDownloadedAudio(surah);
      final timings = await _getTimings(surah);
      if (local != null && timings.isEmpty) {
        throw Exception('هذا القارئ لا يوفّر توقيتًا منفصلًا للآيات. يمكنك تشغيل السورة كاملة بدون إنترنت.');
      }
      _QuranTiming? timing;
      for (final item in timings) {
        if (item.ayah == ayah) {
          timing = item;
          break;
        }
      }
      if (timing == null) throw Exception('لم يتوفر توقيت هذه الآية للقارئ المختار.');
      await _playSegments([
        _QuranAudioSegment(
          surah: surah,
          ayah: ayah,
          startMs: timing.startMs,
          endMs: timing.endMs,
        ),
      ]);
    } catch (e) {
      if (mounted) _showAudioError(e);
    }
  }

  Future<void> _playCurrentPage() async {
    try {
      final page = _page;
      if (page == null) return;
      final keys = page.ayahKeys();
      if (keys.isEmpty) throw Exception('تعذر تحديد آيات الصفحة.');

      final segments = <_QuranAudioSegment>[];
      for (final key in keys) {
        final timings = await _getTimings(key.$1);
        _QuranTiming? timing;
        for (final item in timings) {
          if (item.ayah == key.$2) {
            timing = item;
            break;
          }
        }
        if (timing != null) {
          segments.add(_QuranAudioSegment(
            surah: key.$1,
            ayah: key.$2,
            startMs: timing.startMs,
            endMs: timing.endMs,
          ));
        }
      }
      if (segments.isEmpty) {
        throw Exception('لا تتوفر توقيتات الآيات لهذا القارئ. اختر قارئًا يدعم توقيت الآيات لتشغيل الصفحة أوفلاين.');
      }
      await _playSegments(segments);
    } catch (e) {
      if (mounted) _showAudioError(e);
    }
  }

  Future<void> _playSurah(int surah) async {
    try {
      final local = await _findAnyDownloadedAudio(surah);

      // If the selected reciter has ayah-level timings, use the timings even
      // for a locally downloaded MP3. This is what allows the Mushaf highlight
      // and automatic page changes to stay synchronized with the reciter.
      if (_selectedReciterHasAyahTiming) {
        final timings = await _getTimings(surah);
        final segments = timings
            .map(
              (t) => _QuranAudioSegment(
                surah: surah,
                ayah: t.ayah,
                startMs: t.startMs,
                endMs: t.endMs,
              ),
            )
            .toList();

        if (segments.isNotEmpty) {
          await _playSegments(segments);
          return;
        }
      }

      // Reciters without ayah-level timing remain fully usable: play the
      // complete local surah when it exists. Exact ayah/page synchronization
      // is intentionally not guessed when the source does not provide timing.
      if (local != null) {
        final token = ++_playbackToken;
        _quranPlaybackInfo.value = _QuranPlaybackInfo(
          surahName: _surahNames[surah - 1],
          reciterName: _selectedReciter.name,
        );
        _audioBusy = true;
        if (mounted) setState(() {});

        try {
          await _quranPlayer.stop();
          for (var repeat = 0; repeat < _repeatCount; repeat++) {
            if (token != _playbackToken) return;

            await _quranPlayer.setFilePath(
              local.path,
              tag: MediaItem(
                id: 'quran-$surah-${local.reciterId}',
                album: 'صلاتي — القرآن الكريم',
                title: 'سورة ${_surahNames[surah - 1]}',
                artist: _selectedReciter.name,
              ),
            );
            await _quranPlayer.setSpeed(_playbackSpeed);
            await _quranPlayer.seek(Duration.zero);
            await _quranPlayer.play();
            await _waitUntilAudioComplete(token);
          }
        } finally {
          if (token == _playbackToken) {
            _audioBusy = false;
            _clearCurrentHighlight();
            _quranPlaybackInfo.value = null;
            if (mounted) setState(() {});
          }
        }
        return;
      }

      // No local copy exists. For a reader with timing data, the segmented
      // path above already handles network playback. For readers without
      // timing data, there is no safe way to invent ayah boundaries.
      throw Exception(
        'لا توجد نسخة محفوظة من هذه السورة على الجهاز، ولا تتوفر توقيتات الآيات للقارئ المختار. حمّل السورة أو اختر قارئًا يدعم توقيت الآيات.',
      );
    } catch (e) {
      if (mounted) _showAudioError(e);
    }
  }

  Future<void> _waitUntilAudioComplete(int token) async {
    await for (final state in _quranPlayer.processingStateStream) {
      if (token != _playbackToken) return;
      if (state == ja.ProcessingState.completed) return;
    }
  }

  Future<void> _playSegments(List<_QuranAudioSegment> segments) async {
    if (segments.isEmpty) return;
    final token = ++_playbackToken;
    _quranPlaybackInfo.value = _QuranPlaybackInfo(
      surahName: _surahNames[segments.first.surah - 1],
      reciterName: _selectedReciter.name,
    );
    _audioBusy = true;
    try {
      await _quranPlayer.stop();

      for (var repeat = 0; repeat < _repeatCount; repeat++) {
        for (final segment in segments) {
          if (token != _playbackToken) return;

          // Synchronize the Mushaf before each timed ayah starts. This both
          // highlights the current ayah and advances to the page containing it.
          final synced = await _prepareRecitationSegment(segment, token);
          if (!synced) return;

          final local = await _downloadedPathIfExists(segment.surah);
          if (local != null) {
            await _quranPlayer.setFilePath(
              local,
              tag: MediaItem(
                id: 'quran-${segment.surah}-${segment.ayah}',
                album: 'صلاتي — القرآن الكريم',
                title: 'سورة ${_surahNames[segment.surah - 1]} • الآية ${segment.ayah}',
                artist: _selectedReciter.name,
              ),
            );
          } else {
            await _quranPlayer.setUrl(
              await _surahAudioUrl(segment.surah),
              tag: MediaItem(
                id: 'quran-${segment.surah}',
                album: 'صلاتي — القرآن الكريم',
                title: 'سورة ${_surahNames[segment.surah - 1]}',
                artist: _selectedReciter.name,
              ),
            );
          }

          await _quranPlayer.setSpeed(_playbackSpeed);
          await _quranPlayer.seek(Duration(milliseconds: segment.startMs));
          await _quranPlayer.play();

          final target = Duration(milliseconds: segment.endMs);
          await _waitUntilAudioPosition(target, token);
          if (token != _playbackToken) return;
          await _quranPlayer.pause();
        }
      }
    } catch (e) {
      if (mounted) _showAudioError(e);
    } finally {
      if (token == _playbackToken) {
        _audioBusy = false;
        _clearCurrentHighlight();
        _quranPlaybackInfo.value = null;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _waitUntilAudioPosition(Duration target, int token) async {
    await for (final position in _quranPlayer.positionStream) {
      if (token != _playbackToken) return;
      if (position >= target) return;
    }
  }

  Future<void> _showTafsir(
    int surah,
    int ayah,
    String ayahText,
    String surahName,
  ) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تفسير سورة $surahName — الآية $ayah'),
            content: FutureBuilder<String>(
              future: _fetchTafsir(surah, ayah),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 150,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || snapshot.data == null || snapshot.data!.trim().isEmpty) {
                  return const Text('تعذر تحميل التفسير حالياً. تأكد من اتصال الإنترنت ثم حاول مرة أخرى.');
                }
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '﴿ $ayahText ﴾',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, height: 1.8),
                      ),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text('التفسير الميسر', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 7),
                      Text(snapshot.data!, style: const TextStyle(height: 1.8)),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _fetchTafsir(int surah, int ayah) async {
    final response = await _quranDio.get(
      'https://api.alquran.cloud/v1/ayah/$surah:$ayah/ar.muyassar',
      options: Options(responseType: ResponseType.json),
    );
    final data = response.data is Map ? response.data['data'] : null;
    final text = data is Map ? data['text'] : null;
    if (text is! String || text.trim().isEmpty) {
      throw Exception('لا يوجد تفسير متاح.');
    }
    return text.trim();
  }

  void _showAudioError(Object error) {
    debugPrint('Quran audio error: $error');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر تشغيل التلاوة: ${error.toString().replaceFirst('Exception: ', '')}')),
    );
  }

  void _toggleTheme() {
    // Recreate the QVP view after a theme switch so the new paper/ink colors
    // are applied to a fresh renderer instead of a cached dark surface.
    _recreateQvpViewport();
    widget.onThemeChanged(!widget.darkMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _page == null) return;
      _fitReaderForOrientation(
        MediaQuery.sizeOf(context).width >
            MediaQuery.sizeOf(context).height,
      );
    });
  }

  @override
  void dispose() {
    _quranStopSignal.removeListener(_onGlobalQuranStopSignal);
    WidgetsBinding.instance.removeObserver(this);
    _cancelLongPress();
    _longPressToken++;
    // Keep the process-level Quran player alive so recitation continues
    // when the reader screen is closed or the app goes to the background.
    _quranDio.close(force: true);
    _viewController?.dispose();

    final page = _page;
    if (page != null && !page.isDisposed) {
      page.dispose();
    }

    _engine?.dispose();

    // Always return system bars when leaving the Quran reader.
    if (_systemUiHidden) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final page = _page;

    return OrientationBuilder(
      builder: (context, orientation) {
        final landscape = orientation == Orientation.landscape;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncSystemUi(landscape);

          // Re-layout only when the orientation really changes.
          // Landscape becomes an accessibility reading mode: the printed
          // page is enlarged to the available width and can be panned
          // vertically, while portrait stays in full-page mode.
          if (landscape != _lastLandscape) {
            _lastLandscape = landscape;
            _refreshQvpAfterRotation(landscape);
          }
        });

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: landscape
                      ? (_isDark ? const Color(0xFF050807) : Colors.black)
                      : Theme.of(context).scaffoldBackgroundColor,
                  child: landscape
                      ? _buildLandscapeReader(
                          context,
                          scheme,
                          page,
                        )
                      : _buildPortraitReader(
                          context,
                          scheme,
                          page,
                        ),
                ),
              ),
              _buildReaderPlaybackBar(context),
              _buildDownloadProgressOverlay(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPortraitReader(
    BuildContext context,
    ColorScheme scheme,
    QvpPage? page,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF176B52),
                      Color(0xFF0D4939),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFFE2BD63),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'المصحف الشريف',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'سورة $_currentSurahName • صفحة $_pageNumber من $_lastPage',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'اختيار السورة',
                onPressed: _showSurahPicker,
                icon: const Icon(Icons.list_alt_rounded),
              ),
              IconButton(
                tooltip: 'الوضع الليلي',
                onPressed: _toggleTheme,
                icon: Icon(
                  _isDark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildQvpSurface(
            context,
            scheme,
            page,
            landscape: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _pageNumber > _firstPage ? _previousPage : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('السابقة'),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  '$_pageNumber / $_lastPage',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _pageNumber < _lastPage ? _nextPage : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('التالية'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(
            'المصحف QVP • رواية حفص عن عاصم',
            style: TextStyle(
              fontSize: 9.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeReader(
    BuildContext context,
    ColorScheme scheme,
    QvpPage? page,
  ) {
    // Landscape is a pure reading mode: no floating buttons, page counter,
    // or navigation controls over the Quran text. Page changes are done by
    // horizontal finger swipes, while vertical finger movement scrolls the
    // enlarged printed page.
    return _buildQvpSurface(
      context,
      scheme,
      page,
      landscape: true,
    );
  }

  Widget _buildQvpSurface(
    BuildContext context,
    ColorScheme scheme,
    QvpPage? page, {
    required bool landscape,
  }) {
    return Container(
      margin: landscape
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _isDark
            ? const Color(0xFF101713)
            : const Color(0xFFEFE8D8),
        borderRadius: landscape
            ? BorderRadius.circular(8)
            : BorderRadius.circular(22),
        border: Border.all(
          color: _isDark
              ? const Color(0xFF44534A)
              : const Color(0xFFD7CCB8),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _error != null
          ? _buildErrorState(scheme)
          : page == null
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : _rotationRefreshing
                  ? const SizedBox.expand()
                  : Stack(
                  children: [
                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _onQuranPointerDown,
                        onPointerMove: _onQuranPointerMove,
                        onPointerUp: _onQuranPointerUp,
                        onPointerCancel: _onQuranPointerUp,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity.abs() < 350) return;

                          // Requested Quran navigation direction:
                          // swipe left-to-right  -> next page
                          // swipe right-to-left -> previous page.
                          if (velocity > 0) {
                            _nextPage();
                          } else {
                            _previousPage();
                          }
                        },
                        onVerticalDragUpdate: landscape
                            ? (details) =>
                                _panLandscapeVertically(details.delta.dy)
                            : null,
                        child: QvpPageView(
                          key: _viewKey,
                          page: page,
                          controller: _viewController,
                          panZoomEnabled: false,
                        paper: _isDark
                            ? const Color(0xFF171D19)
                            : const Color(0xFFFFFDF7),
                        defaultInk: _isDark
                            ? '#F3E8C8'
                            : '#231F20',
                        onWordTap: (word, _) {
                          _highlightWord(word);
                          _openAyahActionsForWord(word);
                        },
                        onDecorationTap: (decoration) {
                          if (decoration.ayah > 0) {
                            final target = T.ayah(
                              decoration.surah,
                              decoration.ayah,
                            );
                            if (_highlightHandle != 0 &&
                                !page.isDisposed) {
                              page.removeHighlight(_highlightHandle);
                            }
                            _highlightHandle = page.highlight(
                              target,
                              const QvpHighlightStyle(
                                mode: 'both',
                                ink: '#176B52',
                                band: '#176B5233',
                                radius: 1.5,
                                ms: 220,
                              ),
                            );
                            setState(() {});
                          }
                        },
                          onEmptyTap: () {
                            if (_highlightHandle != 0 &&
                                !page.isDisposed) {
                              page.removeHighlight(_highlightHandle);
                              setState(() => _highlightHandle = 0);
                            }
                          },
                          selectionEnabled: false,
                        ),
                      ),
                    ),
                    ),
                    if (_loading)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Color(0x33000000),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: scheme.primary,
            ),
            const SizedBox(height: 14),
            const Text(
              'تعذر تحميل المصحف',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'خطأ غير معروف',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (_engine == null) {
                  _initializeQuran();
                } else {
                  _loadPage(_pageNumber);
                }
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
