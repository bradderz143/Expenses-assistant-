import 'package:flutter/material.dart';

import '../../domain/entities/enums.dart';

/// Visual identity: the receipt itself. Ink-navy text on cool paper, the
/// icon's tick green for "ready", and IBM Plex Sans throughout: sober, with
/// crisp tabular figures for reading amounts.
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'PlexSans';

  // Palette (light).
  static const Color ink = Color(0xFF14273D);
  static const Color inkSoft = Color(0xFF4A5B70);
  static const Color paper = Color(0xFFEEF2F5);
  static const Color sheet = Color(0xFFFFFFFF);
  static const Color rule = Color(0xFFD5DDE5);
  static const Color stampGreen = Color(0xFF17734A);
  static const Color amber = Color(0xFF8F5B0A);
  static const Color correction = Color(0xFFB42318);

  // Palette (dark): night shift at the airport.
  static const Color nightPaper = Color(0xFF0E1A29);
  static const Color nightSheet = Color(0xFF16263A);
  static const Color nightRule = Color(0xFF2A3D55);
  static const Color nightInk = Color(0xFFE6EDF5);
  static const Color nightInkSoft = Color(0xFFA3B3C6);

  /// Amounts: bold, tabular so columns of figures line up.
  static TextStyle amount(BuildContext context, {double size = 17}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurface,
      );

  static ThemeData light() => _build(
        ColorScheme(
          brightness: Brightness.light,
          primary: ink,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFD9E3EE),
          onPrimaryContainer: ink,
          secondary: stampGreen,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFD5EEDF),
          onSecondaryContainer: const Color(0xFF0E4A2C),
          tertiary: amber,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFF7E7C8),
          onTertiaryContainer: const Color(0xFF5A3A06),
          error: correction,
          onError: Colors.white,
          errorContainer: const Color(0xFFFBE0DC),
          onErrorContainer: const Color(0xFF5F120B),
          surface: sheet,
          onSurface: ink,
          onSurfaceVariant: inkSoft,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF6F8FA),
          surfaceContainer: paper,
          surfaceContainerHigh: const Color(0xFFE5EAEF),
          surfaceContainerHighest: const Color(0xFFDCE3EA),
          outline: const Color(0xFF8394A8),
          outlineVariant: rule,
          inverseSurface: ink,
          onInverseSurface: const Color(0xFFEFF3F7),
          inversePrimary: const Color(0xFFAFC6E0),
        ),
        background: paper,
        statuses: const StatusColors(
          needsDetails: correction,
          needsTranslation: amber,
          ready: stampGreen,
          submitted: Color(0xFF5E6E82),
        ),
      );

  static ThemeData dark() => _build(
        ColorScheme(
          brightness: Brightness.dark,
          primary: const Color(0xFFBFD3EA),
          onPrimary: nightPaper,
          primaryContainer: const Color(0xFF243A55),
          onPrimaryContainer: nightInk,
          secondary: const Color(0xFF5CC48C),
          onSecondary: const Color(0xFF052615),
          secondaryContainer: const Color(0xFF1B4631),
          onSecondaryContainer: const Color(0xFFCDEEDB),
          tertiary: const Color(0xFFE7B45A),
          onTertiary: const Color(0xFF3A2503),
          tertiaryContainer: const Color(0xFF4D3610),
          onTertiaryContainer: const Color(0xFFF7E2BC),
          error: const Color(0xFFF28B7D),
          onError: const Color(0xFF450B05),
          errorContainer: const Color(0xFF5C1A12),
          onErrorContainer: const Color(0xFFFBDAD5),
          surface: nightSheet,
          onSurface: nightInk,
          onSurfaceVariant: nightInkSoft,
          surfaceContainerLowest: const Color(0xFF0A1420),
          surfaceContainerLow: const Color(0xFF132233),
          surfaceContainer: nightPaper,
          surfaceContainerHigh: const Color(0xFF1D2F46),
          surfaceContainerHighest: const Color(0xFF253A54),
          outline: const Color(0xFF6E829A),
          outlineVariant: nightRule,
          inverseSurface: nightInk,
          onInverseSurface: nightPaper,
          inversePrimary: ink,
        ),
        background: nightPaper,
        statuses: const StatusColors(
          needsDetails: Color(0xFFF28B7D),
          needsTranslation: Color(0xFFE7B45A),
          ready: Color(0xFF5CC48C),
          submitted: Color(0xFF8DA0B6),
        ),
      );

  static ThemeData _build(
    ColorScheme scheme, {
    required Color background,
    required StatusColors statuses,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
    );
    // Component themes read these styles directly, so they need real sizes
    // (ThemeData only adds sizes later, when Theme.of localises it).
    final text = Typography.material2021(platform: TargetPlatform.android)
        .englishLike
        .merge(base.textTheme);
    final textTheme = text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.35),
      bodySmall: text.bodySmall?.copyWith(
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      extensions: [statuses],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.titleSmall?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: textTheme.bodySmall,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: rounded,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: rounded,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: rounded,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: rounded,
      ),
    );
  }
}

/// One colour per step of the workflow, used for status dots and counts.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.needsDetails,
    required this.needsTranslation,
    required this.ready,
    required this.submitted,
  });

  final Color needsDetails;
  final Color needsTranslation;
  final Color ready;
  final Color submitted;

  Color of(ReceiptStatus status) => switch (status) {
        ReceiptStatus.needsClassification => needsDetails,
        ReceiptStatus.needsTranslation => needsTranslation,
        ReceiptStatus.ready => ready,
        ReceiptStatus.submitted => submitted,
      };

  static StatusColors read(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? AppTheme.dark().extension<StatusColors>()!
          : AppTheme.light().extension<StatusColors>()!);

  @override
  StatusColors copyWith({
    Color? needsDetails,
    Color? needsTranslation,
    Color? ready,
    Color? submitted,
  }) =>
      StatusColors(
        needsDetails: needsDetails ?? this.needsDetails,
        needsTranslation: needsTranslation ?? this.needsTranslation,
        ready: ready ?? this.ready,
        submitted: submitted ?? this.submitted,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      needsDetails: Color.lerp(needsDetails, other.needsDetails, t)!,
      needsTranslation: Color.lerp(needsTranslation, other.needsTranslation, t)!,
      ready: Color.lerp(ready, other.ready, t)!,
      submitted: Color.lerp(submitted, other.submitted, t)!,
    );
  }
}

/// The torn edge of thermal receipt paper, used once: under the capture
/// panel on the dashboard.
class TornEdgeClipper extends CustomClipper<Path> {
  const TornEdgeClipper({this.tooth = 9});

  final double tooth;

  @override
  Path getClip(Size size) {
    final path = Path()..lineTo(size.width, 0);
    final bottom = size.height;
    path.lineTo(size.width, bottom - tooth);
    final teeth = (size.width / (tooth * 2)).ceil();
    final step = size.width / teeth;
    for (var i = 0; i < teeth; i++) {
      final x = size.width - i * step;
      path
        ..lineTo(x - step / 2, bottom)
        ..lineTo(x - step, bottom - tooth);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(TornEdgeClipper oldClipper) => oldClipper.tooth != tooth;
}
