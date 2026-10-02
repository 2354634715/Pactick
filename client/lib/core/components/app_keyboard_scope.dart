import 'package:flutter/widgets.dart';

/// The outer Scaffold consumes viewInsets before laying out feature pages.
class AppKeyboardScope extends InheritedWidget {
  const AppKeyboardScope({
    required this.visible,
    required super.child,
    super.key,
  });
  final bool visible;
  static bool visibleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppKeyboardScope>()?.visible ??
      MediaQuery.viewInsetsOf(context).bottom > 0;
  @override
  bool updateShouldNotify(AppKeyboardScope oldWidget) =>
      visible != oldWidget.visible;
}
