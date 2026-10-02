import 'package:flutter/widgets.dart';

enum WindowSizeClass { compact, medium, expanded, large }

extension WindowSizeClassQuery on BuildContext {
  WindowSizeClass get windowSizeClass {
    final width = MediaQuery.sizeOf(this).width;
    if (width < 600) return WindowSizeClass.compact;
    if (width < 840) return WindowSizeClass.medium;
    if (width < 1200) return WindowSizeClass.expanded;
    return WindowSizeClass.large;
  }

  bool get isCompact => windowSizeClass == WindowSizeClass.compact;

  bool get isLargeLayout => switch (windowSizeClass) {
    WindowSizeClass.expanded || WindowSizeClass.large => true,
    _ => false,
  };
}
