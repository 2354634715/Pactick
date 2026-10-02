import 'package:intl/intl.dart';

String formatDuration(int seconds, {bool compact = false}) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (compact) {
    if (hours > 0 && minutes > 0) return '$hours小时$minutes分';
    if (hours > 0) return '$hours小时';
    return '$minutes分钟';
  }
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}

String formatClock(DateTime value) => DateFormat('HH:mm').format(value);

String formatMonthDay(DateTime value) => DateFormat('M月d日').format(value);

String formatFullDate(DateTime value) =>
    DateFormat('M月d日 EEEE', 'zh_CN').format(value);

String formatShortWeekday(DateTime value) =>
    DateFormat('E', 'zh_CN').format(value);

String formatRelativeDate(DateTime value, DateTime today) {
  final date = DateTime(value.year, value.month, value.day);
  final base = DateTime(today.year, today.month, today.day);
  final difference = date.difference(base).inDays;
  return switch (difference) {
    -1 => '昨天',
    0 => '今天',
    1 => '明天',
    _ => formatMonthDay(value),
  };
}
