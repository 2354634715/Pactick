import 'package:flutter/material.dart';

enum AppDestination {
  today('今日', Icons.today_outlined, Icons.today),
  tasks('任务', Icons.checklist_outlined, Icons.checklist),
  calendar('日历', Icons.calendar_month_outlined, Icons.calendar_month),
  focus('专注', Icons.center_focus_strong_outlined, Icons.center_focus_strong),
  statistics('统计', Icons.insights_outlined, Icons.insights);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
