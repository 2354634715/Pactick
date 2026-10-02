import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadii {
  static const double small = 10;
  static const double medium = 14;
  static const double card = 18;
  static const double large = 24;
  static const double overlay = 28;
  static const double pill = 999;
}

abstract final class AppSizes {
  static const double minTouchTarget = 48;
  static const double compactContentMax = 720;
  static const double expandedContentMax = 1200;
  static const double readingContentMax = 680;
  static const double formMax = 560;
  static const double editorMax = 640;
  static const double twoPaneMinWidth = 960;
  static const double detailPanelWidth = 320;
  static const double lowHeight = 480;
  static const double fabScrollClearance = 96;
  static const double navigationRailWidth = 80;
  static const double navigationDrawerWidth = 260;
  static const double sidePanel = 280;
  static const double calendarHourExtent = 72;
  static const double pageHeaderHeight = 136;

  static double pageInset(double width) => width < 600
      ? AppSpacing.md
      : width < 840
      ? AppSpacing.lg
      : AppSpacing.xl;
}

abstract final class AppDurations {
  static const Duration feedback = Duration(milliseconds: 120);
  static const Duration overlay = Duration(milliseconds: 240);
  static const Duration page = Duration(milliseconds: 300);

  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

abstract final class AppCurves {
  static const Curve standard = Curves.fastOutSlowIn;
}

extension ColorSchemeContainers on ColorScheme {
  Color get successContainer => brightness == Brightness.light
      ? const Color(0xFFD7F4E4)
      : const Color(0xFF173A2B);

  Color get onSuccessContainer => brightness == Brightness.light
      ? const Color(0xFF0C3222)
      : const Color(0xFFBCE9D1);

  Color get warningContainer => brightness == Brightness.light
      ? const Color(0xFFFFEBC2)
      : const Color(0xFF4A3510);

  Color get onWarningContainer => brightness == Brightness.light
      ? const Color(0xFF3E2D00)
      : const Color(0xFFFFDEA1);
}
