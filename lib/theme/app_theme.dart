import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Builds the full ThemeData for AI VaultIO.
///
/// Design goals:
///  - Inter font throughout for a modern, readable feel
///  - Desktop-appropriate density (smaller touch targets, tighter spacing)
///  - Borders over heavy shadows for a clean, professional look
///  - Restrained color usage — blue accent on a neutral base
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark()  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark ? _darkScheme : _lightScheme;
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
    final textTheme = GoogleFonts.interTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    return base.copyWith(
      brightness: brightness,
      textTheme: textTheme,
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      scaffoldBackgroundColor:
          isDark ? AppColors.darkScaffold : AppColors.lightScaffold,

      // ── AppBar ────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        foregroundColor:
            isDark ? AppColors.sidebarTextActive : AppColors.slate900,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.px16,
        toolbarHeight: AppSpacing.appBarHeight,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.sidebarTextActive : AppColors.slate900,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(
          size: AppSpacing.iconLg,
          color: isDark ? AppColors.slate400 : AppColors.slate500,
        ),
        actionsIconTheme: IconThemeData(
          size: AppSpacing.iconLg,
          color: isDark ? AppColors.slate400 : AppColors.slate500,
        ),
        shape: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),

      // ── Card ──────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // ── Buttons ───────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.brand600,
          foregroundColor: Colors.white,
          minimumSize:
              const Size(0, AppSpacing.buttonHeightMd),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.px16, vertical: AppSpacing.px8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          textStyle: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.buttonHeightMd),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.px16, vertical: AppSpacing.px8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          textStyle: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.buttonHeightMd),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.px16, vertical: AppSpacing.px8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          side: BorderSide(
              color:
                  isDark ? AppColors.darkBorderSub : AppColors.lightBorder),
          textStyle: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.buttonHeightMd),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.px12, vertical: AppSpacing.px8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          textStyle: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Input ─────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.px12, vertical: AppSpacing.px10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(
              color:
                  isDark ? AppColors.darkBorderSub : AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(
              color:
                  isDark ? AppColors.darkBorderSub : AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.brand500, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide:
              const BorderSide(color: AppColors.error, width: 1.5),
        ),
        hintStyle: TextStyle(
            color: isDark ? AppColors.slate500 : AppColors.slate400,
            fontSize: 13),
        labelStyle: TextStyle(
            color: isDark ? AppColors.slate400 : AppColors.slate500,
            fontSize: 13),
      ),

      // ── ListTile ──────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        dense: true,
        minLeadingWidth: 20,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        visualDensity: VisualDensity(horizontal: 0, vertical: -1),
      ),

      // ── Divider ───────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(
              color:
                  isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.sidebarTextActive : AppColors.slate900,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 13,
          color: isDark ? AppColors.slate400 : AppColors.slate500,
          height: 1.5,
        ),
      ),

      // ── Chip ──────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? AppColors.darkBorderSub : AppColors.slate100,
        labelStyle: GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.px8, vertical: AppSpacing.px4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
        side: BorderSide.none,
      ),

      // ── Tooltip ───────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.slate800,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 11,
          color: AppColors.sidebarTextActive,
          fontWeight: FontWeight.w400,
        ),
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.px8, vertical: AppSpacing.px6),
      ),

      // ── SnackBar ──────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.slate800,
        contentTextStyle: GoogleFonts.inter(
            fontSize: 13, color: AppColors.sidebarTextActive),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        behavior: SnackBarBehavior.floating,
        width: 400,
      ),

      // ── Popup menu ────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        elevation: 4,
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(
              color:
                  isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 13,
          color: isDark ? AppColors.sidebarTextActive : AppColors.slate900,
        ),
      ),

      // ── Switch ────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? AppColors.slate600 : AppColors.slate300;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brand600;
          return isDark ? AppColors.darkBorderSub : AppColors.slate200;
        }),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),

      // ── Segmented button ──────────────────────────────────────────
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w500),
          ),
          minimumSize:
              const WidgetStatePropertyAll(Size(0, 32)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
                horizontal: AppSpacing.px12, vertical: AppSpacing.px4),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusMd)),
          ),
        ),
      ),

      // ── Tab bar ───────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelStyle: GoogleFonts.inter(
            fontSize: 13, fontWeight: FontWeight.w500),
        unselectedLabelStyle:
            GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400),
        labelColor:
            isDark ? AppColors.brand400 : AppColors.brand600,
        unselectedLabelColor:
            isDark ? AppColors.slate400 : AppColors.slate500,
        indicatorColor:
            isDark ? AppColors.brand400 : AppColors.brand600,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor:
            isDark ? AppColors.darkBorder : AppColors.lightBorder,
      ),

      // ── Progress indicator ────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand500,
        linearTrackColor: AppColors.brand100,
      ),
    );
  }

  // ── Color schemes ─────────────────────────────────────────────────

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.brand600,
    onPrimary: Colors.white,
    primaryContainer: AppColors.brand100,
    onPrimaryContainer: AppColors.brand700,
    secondary: AppColors.slate600,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.slate100,
    onSecondaryContainer: AppColors.slate900,
    tertiary: Color(0xFF0F766E),   // teal-700
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFCCFBF1),
    onTertiaryContainer: Color(0xFF134E4A),
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: AppColors.errorSurface,
    onErrorContainer: Color(0xFF7F1D1D),
    surface: AppColors.lightSurface,
    onSurface: AppColors.slate900,
    surfaceContainerLowest: AppColors.white,
    surfaceContainerLow: AppColors.slate50,
    surfaceContainer: AppColors.slate100,
    surfaceContainerHigh: AppColors.slate200,
    surfaceContainerHighest: AppColors.slate300,
    onSurfaceVariant: AppColors.slate500,
    outline: AppColors.lightBorder,
    outlineVariant: AppColors.lightBorderSub,
    shadow: AppColors.slate900,
    scrim: AppColors.slate900,
    inverseSurface: AppColors.slate800,
    onInverseSurface: AppColors.slate100,
    inversePrimary: AppColors.brand400,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.brand400,
    onPrimary: AppColors.brand900,
    primaryContainer: AppColors.brand800,
    onPrimaryContainer: AppColors.brand200,
    secondary: AppColors.slate400,
    onSecondary: AppColors.slate900,
    secondaryContainer: AppColors.slate800,
    onSecondaryContainer: AppColors.slate100,
    tertiary: Color(0xFF2DD4BF),   // teal-400
    onTertiary: Color(0xFF134E4A),
    tertiaryContainer: Color(0xFF0F766E),
    onTertiaryContainer: Color(0xFFCCFBF1),
    error: Color(0xFFF87171),      // red-400
    onError: Color(0xFF7F1D1D),
    errorContainer: Color(0xFF991B1B),
    onErrorContainer: Color(0xFFFECACA),
    surface: AppColors.darkSurface,
    onSurface: AppColors.sidebarTextActive,
    surfaceContainerLowest: AppColors.darkScaffold,
    surfaceContainerLow: Color(0xFF13181F),
    surfaceContainer: AppColors.darkSurface,
    surfaceContainerHigh: AppColors.darkBorder,
    surfaceContainerHighest: AppColors.darkBorderSub,
    onSurfaceVariant: AppColors.slate400,
    outline: AppColors.darkBorder,
    outlineVariant: AppColors.darkScaffold,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppColors.slate100,
    onInverseSurface: AppColors.slate800,
    inversePrimary: AppColors.brand700,
  );
}
