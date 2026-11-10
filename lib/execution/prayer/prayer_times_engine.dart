import 'package:adhan/adhan.dart';

/// Calculates the canonical prayer times without depending on presentation state.
class PrayerTimesEngine {
  CalculationParameters parameters({
    required int method,
    required int asrSchool,
  }) {
    final CalculationParameters params;

    switch (method) {
      case 1:
        params = CalculationMethod.umm_al_qura.getParameters();
        break;
      case 2:
        params = CalculationMethod.egyptian.getParameters();
        break;
      case 3:
        params = CalculationMethod.karachi.getParameters();
        break;
      case 4:
        params = CalculationMethod.north_america.getParameters();
        break;
      case 5:
        params = CalculationMethod.kuwait.getParameters();
        break;
      case 6:
        params = CalculationMethod.qatar.getParameters();
        break;
      default:
        params = CalculationMethod.muslim_world_league.getParameters();
    }

    params.madhab = asrSchool == 1 ? Madhab.hanafi : Madhab.shafi;
    return params;
  }

  Map<String, DateTime> calculate({
    required double latitude,
    required double longitude,
    required DateTime date,
    required int method,
    required int asrSchool,
    required Map<String, int> adjustments,
  }) {
    final times = PrayerTimes(
      Coordinates(latitude, longitude),
      DateComponents.from(date),
      parameters(method: method, asrSchool: asrSchool),
    );

    final raw = <String, DateTime>{
      'fajr': times.fajr,
      'sunrise': times.sunrise,
      'dhuhr': times.dhuhr,
      'asr': times.asr,
      'maghrib': times.maghrib,
      'isha': times.isha,
    };

    return raw.map((key, value) => MapEntry(
          key,
          value.add(Duration(minutes: adjustments[key] ?? 0)),
        ));
  }
}
