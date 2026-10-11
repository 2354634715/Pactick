import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/components/active_focus_dock.dart';
import '../../core/components/app_keyboard_scope.dart';
import '../../core/components/app_mark.dart';
import '../../core/state/app_scope.dart';
import '../../features/calendar/pages/calendar_page.dart';
import '../../features/focus/pages/focus_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/statistics/pages/statistics_page.dart';
import '../../features/tasks/pages/tasks_page.dart';
import '../../features/today/pages/today_page.dart';
import '../theme/app_tokens.dart';
import 'app_destination.dart';

class AdaptiveAppShell extends StatefulWidget {
  const AdaptiveAppShell({super.key});
  @override
  State<AdaptiveAppShell> createState() => _AdaptiveAppShellState();
}

class _AdaptiveAppShellState extends State<AdaptiveAppShell> {
  int _selectedIndex = 0;
  bool _settingsOpen = false;
  int _taskReminderOpenSequence = 0;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.watchData(context);
    if (_taskReminderOpenSequence != controller.taskReminderOpenSequence) {
      _taskReminderOpenSequence = controller.taskReminderOpenSequence;
      _selectedIndex = AppDestination.tasks.index;
    }
    return CallbackShortcuts(
      bindings: {
        for (var index = 0; index < AppDestination.values.length; index++)
          SingleActivator(
            LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + index),
            control: true,
          ): () =>
              _select(index),
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            _openSettings,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final drawer = constraints.maxWidth >= 1200;
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            return Scaffold(
              bottomNavigationBar: compact && !keyboardOpen
                  ? NavigationBar(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _select,
                      destinations: [
                        for (final destination in AppDestination.values)
                          NavigationDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: destination.label,
                            tooltip: destination.label,
                          ),
                      ],
                    )
                  : null,
              body: AppKeyboardScope(
                visible: keyboardOpen,
                child: Row(
                  children: [
                    SizedBox(
                      width: compact
                          ? 0
                          : drawer
                          ? AppSizes.navigationDrawerWidth
                          : AppSizes.navigationRailWidth,
                      child: compact
                          ? null
                          : SafeArea(
                              child: drawer
                                  ? NavigationDrawer(
                                      selectedIndex: _selectedIndex,
                                      onDestinationSelected: (index) =>
                                          index == AppDestination.values.length
                                          ? _openSettings()
                                          : _select(index),
                                      children: [
                                        const _BrandHeader(),
                                        for (final destination
                                            in AppDestination.values)
                                          NavigationDrawerDestination(
                                            icon: Icon(destination.icon),
                                            selectedIcon: Icon(
                                              destination.selectedIcon,
                                            ),
                                            label: Text(destination.label),
                                          ),
                                        const Divider(),
                                        const NavigationDrawerDestination(
                                          icon: Icon(Icons.settings_outlined),
                                          label: Text('设置'),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.all(
                                            AppSpacing.lg,
                                          ),
                                          child: Text('本机自动保存'),
                                        ),
                                      ],
                                    )
                                  : NavigationRail(
                                      selectedIndex: _selectedIndex,
                                      onDestinationSelected: _select,
                                      labelType: NavigationRailLabelType.all,
                                      scrollable: true,
                                      leading:
                                          constraints.maxHeight <
                                              AppSizes.lowHeight
                                          ? null
                                          : const AppMark(size: 40),
                                      trailing: IconButton(
                                        tooltip: '设置',
                                        onPressed: _openSettings,
                                        icon: const Icon(
                                          Icons.settings_outlined,
                                        ),
                                      ),
                                      destinations: [
                                        for (final destination
                                            in AppDestination.values)
                                          NavigationRailDestination(
                                            icon: Icon(destination.icon),
                                            selectedIcon: Icon(
                                              destination.selectedIcon,
                                            ),
                                            label: Text(destination.label),
                                          ),
                                      ],
                                    ),
                            ),
                    ),
                    SizedBox(
                      width: compact ? 0 : 1,
                      child: const VerticalDivider(),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: IndexedStack(
                              index: _selectedIndex,
                              children: [
                                TodayPage(
                                  onOpenSettings: _openSettings,
                                  onOpenCalendar: _openCalendar,
                                  onOpenFocus: _openFocus,
                                ),
                                TasksPage(
                                  onOpenSettings: _openSettings,
                                  onOpenFocus: _openFocus,
                                ),
                                CalendarPage(onOpenSettings: _openSettings),
                                FocusPage(
                                  onOpenSettings: _openSettings,
                                  onFocusEnded: _openToday,
                                ),
                                StatisticsPage(onOpenSettings: _openSettings),
                              ],
                            ),
                          ),
                          if (!keyboardOpen &&
                              controller.activeFocusSession != null &&
                              _selectedIndex != AppDestination.focus.index)
                            ActiveFocusDock(
                              controller: controller,
                              onOpen: _openFocus,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedIndex = index);
  }

  void _openFocus() => _select(AppDestination.focus.index);
  void _openCalendar() => _select(AppDestination.calendar.index);
  void _openToday() => _select(AppDestination.today.index);

  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;
    final controller = AppScope.read(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => AppDataBoundary(
          controller: controller,
          child: Builder(
            builder: (context) {
              final app = AppScope.watchData(context);
              return Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: SettingsPage(
                        onClose: () => Navigator.of(routeContext).pop(),
                      ),
                    ),
                    if (app.activeFocusSession != null)
                      ActiveFocusDock(
                        controller: app,
                        onOpen: () {
                          Navigator.of(routeContext).pop();
                          _openFocus();
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    _settingsOpen = false;
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          const AppMark(size: 48),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pactick', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '任务、日历与专注',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
