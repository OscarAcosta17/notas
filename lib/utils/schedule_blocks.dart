/// Canonical USM schedule block definitions shared across Horario,
/// notifications, ICS export, and schedule PNG export.
class ScheduleBlocks {
  static const List<int> validBlocks = [1, 3, 5, 7, 9, 11, 13, 15];

  static const Map<int, (int hour, int minute)> blockStartTimes = {
    1: (8, 15),
    3: (9, 40),
    5: (11, 5),
    7: (12, 30),
    9: (14, 40),
    11: (16, 5),
    13: (17, 30),
    15: (18, 55),
  };

  static const Map<int, String> blockRanges = {
    1: '08:15 - 09:25',
    3: '09:40 - 10:50',
    5: '11:05 - 12:15',
    7: '12:30 - 13:40',
    9: '14:40 - 15:50',
    11: '16:05 - 17:15',
    13: '17:30 - 18:40',
    15: '18:55 - 20:05',
  };

  static const List<String> blockAxisLabels = [
    '1-2 (8:15-9:25)',
    '3-4 (9:40-10:50)',
    '5-6 (11:05-12:15)',
    '7-8 (12:30-13:40)',
    '9-10 (14:40-15:50)',
    '11-12 (16:05-17:15)',
    '13-14 (17:30-18:40)',
    '15-16 (18:55-20:05)',
  ];

  static String formatBlockRange(int bloque) =>
      blockRanges[bloque] ?? 'Desconocido';

  static int? rowIndexForBlock(int bloque) {
    final idx = validBlocks.indexOf(bloque);
    return idx == -1 ? null : idx;
  }

  static bool isValidWeekday(int day) => day >= 1 && day <= 7;
}
