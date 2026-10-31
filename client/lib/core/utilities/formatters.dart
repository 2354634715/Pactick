import 'package:intl/intl.dart';

import '../localization/app_localizations.dart';

String formatDuration(int seconds, {bool compact = false}) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (compact) {
    if (AppLocalizations.languageCode == 'en') {
      if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
      if (hours > 0) return '${hours}h';
      return '${minutes}m';
    }
    if (hours > 0 && minutes > 0) return '$hours小时$minutes分';
    if (hours > 0) return '$hours小时';
    return '$minutes分钟';
  }
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}

String formatClock(DateTime value) => DateFormat('HH:mm').format(value);

String formatMonthDay(DateTime value) => AppLocalizations.languageCode == 'en'
    ? DateFormat.MMMd('en').format(value)
    : DateFormat('M月d日', 'zh_CN').format(value);

String formatFullDate(DateTime value) => AppLocalizations.languageCode == 'en'
    ? DateFormat('EEEE, MMM d', 'en').format(value)
    : DateFormat('M月d日 EEEE', 'zh_CN').format(value);

String formatShortWeekday(DateTime value) => DateFormat(
  'E',
  AppLocalizations.languageCode == 'en' ? 'en' : 'zh_CN',
).format(value);

String formatRelativeDate(DateTime value, DateTime today) {
  final date = DateTime(value.year, value.month, value.day);
  final base = DateTime(today.year, today.month, today.day);
  final difference = date.difference(base).inDays;
  return switch (difference) {
    -1 => tr('昨天'),
    0 => tr('今天'),
    1 => tr('明天'),
    _ => formatMonthDay(value),
  };
}
