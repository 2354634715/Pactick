import 'package:flutter/material.dart';

import 'app_tokens.dart';

abstract final class AppTheme {
  static const seedColor = Color(0xFFC1272D);

  static ThemeData light([ColorScheme? dynamicScheme]) => _build(
    dynamicScheme ??
        _withBrandColors(
          ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.light,
          ),
        ),
  );

  static ThemeData dark([ColorScheme? dynamicScheme]) => _build(
    dynamicScheme ??
        _withBrandColors(
          ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.dark,
          ),
        ),
  );

  static ColorScheme _withBrandColors(ColorScheme scheme) {
    if (scheme.brightness == Brightness.dark) {
      return scheme.copyWith(
        primary: const Color(0xFFF06266),
        onPrimary: const Color(0xFF35090D),
        primaryContainer: const Color(0xFF5C2228),
        onPrimaryContainer: const Color(0xFFFFDAD9),
        secondary: const Color(0xFFD4CABB),
        onSecondary: const Color(0xFF363027),
        secondaryContainer: const Color(0xFF393329),
        onSecondaryContainer: const Color(0xFFF6F1E7),
        tertiary: const Color(0xFFD8C6B7),
        onTertiary: const Color(0xFF3D2D23),
        tertiaryContainer: const Color(0xFF504135),
        onTertiaryContainer: const Color(0xFFF6E6D7),
        surface: const Color(0xFF161512),
        onSurface: const Color(0xFFF6F1E7),
        onSurfaceVariant: const Color(0xFFC8C0B4),
        surfaceContainerLowest: const Color(0xFF100F0D),
        surfaceContainerLow: const Color(0xFF1E1B17),
        surfaceContainer: const Color(0xFF24211C),
        surfaceContainerHigh: const Color(0xFF28231D),
        surfaceContainerHighest: const Color(0xFF2C261F),
        outline: const Color(0xFF9B9285),
        outlineVariant: const Color(0xFF494238),
        inverseSurface: const Color(0xFFF6F1E7),
        onInverseSurface: const Color(0xFF1C1B18),
        inversePrimary: seedColor,
        surfaceTint: const Color(0xFFF06266),
      );
    }
    return scheme.copyWith(
      primary: seedColor,
      onPrimary: const Color(0xFFFFFCF7),
      primaryContainer: const Color(0xFFFFDAD9),
      onPrimaryContainer: const Color(0xFF5C2228),
      secondary: const Color(0xFF61594E),
      onSecondary: const Color(0xFFFFFCF7),
      secondaryContainer: const Color(0xFFEEE7DC),
      onSecondaryContainer: const Color(0xFF1C1B18),
      tertiary: const Color(0xFF6B5748),
      onTertiary: const Color(0xFFFFFCF7),
      tertiaryContainer: const Color(0xFFF2E3D4),
      onTertiaryContainer: const Color(0xFF3D2D23),
      surface: const Color(0xFFF6F1E7),
      onSurface: const Color(0xFF1C1B18),
      onSurfaceVariant: const Color(0xFF59554E),
      surfaceContainerLowest: const Color(0xFFFFFCF7),
      surfaceContainerLow: const Color(0xFFF3EDE3),
      surfaceContainer: const Color(0xFFEEE7DC),
      surfaceContainerHigh: const Color(0xFFEDE5D9),
      surfaceContainerHighest: const Color(0xFFECE2D4),
      outline: const Color(0xFF82796D),
      outlineVariant: const Color(0xFFDDD5C8),
      inverseSurface: const Color(0xFF24211C),
      onInverseSurface: const Color(0xFFF6F1E7),
      inversePrimary: const Color(0xFFF06266),
      surfaceTint: seedColor,
    );
  }

  static ThemeData _build(ColorScheme scheme) {
    final roundedCard = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
    );
    final roundedOverlay = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.overlay),
    );
    final baseTextTheme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
    ).textTheme;

    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: 64,
        height: 76 / 64,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: 48,
        height: 56 / 48,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: 36,
        height: 44 / 36,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 26 / 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.brightness == Brightness.dark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: roundedCard,
        clipBehavior: Clip.antiAlias,
        shadowColor: scheme.shadow.withValues(alpha: 0.08),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: roundedOverlay,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.overlay),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            fontSize: 14,
            height: 20 / 14,
            letterSpacing: 0,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        useIndicator: true,
        minWidth: 80,
        minExtendedWidth: 220,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSizes.minTouchTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: BorderSide(color: scheme.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.overlay),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        focusElevation: 2,
        hoverElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppSpacing.xs),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: AppSizes.minTouchTarget,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, AppSizes.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
    );
  }
}
