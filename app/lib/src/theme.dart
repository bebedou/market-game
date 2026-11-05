import 'package:engine/engine.dart';
import 'package:flutter/material.dart';

/// Titles and names: a serif with some ink in it.
const titleFont = 'Fraunces';

/// Mastheads and big titles: the same serif cut for display sizes.
const displayFont = 'Fraunces Display';

/// Running text.
const textFont = 'IBM Plex Sans';

/// Every figure, so that amounts line up and read the same everywhere.
const figuresFont = 'IBM Plex Mono';

/// The ledger's inks and paper. In the dark, the night edition: pale ink
/// on dark paper.
@immutable
class Ledger extends ThemeExtension<Ledger> {
  const Ledger({
    required this.paper,
    required this.shade,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.gain,
    required this.loss,
    required this.night,
  });

  static const day = Ledger(
    paper: Color(0xFFF3EEE3),
    shade: Color(0xFFE9E2D2),
    ink: Color(0xFF1F1B15),
    muted: Color(0xFF6B6252),
    rule: Color(0xFFBFB49E),
    gain: Color(0xFF2E6B3A),
    loss: Color(0xFFA8322A),
    night: false,
  );

  static const nightEdition = Ledger(
    paper: Color(0xFF1A1713),
    shade: Color(0xFF25211B),
    ink: Color(0xFFEDE6D6),
    muted: Color(0xFFA39A88),
    rule: Color(0xFF4A443A),
    gain: Color(0xFF86C493),
    loss: Color(0xFFE37D6E),
    night: true,
  );

  /// The page.
  final Color paper;

  /// A slightly darker paper, for what is picked or set apart.
  final Color shade;
  final Color ink;

  /// Ink for what is said in passing.
  final Color muted;

  /// Hairlines between entries.
  final Color rule;

  /// Green ink for gains and red ink for losses and trouble.
  final Color gain;
  final Color loss;
  final bool night;

  static Ledger of(BuildContext context) =>
      Theme.of(context).extension<Ledger>() ?? day;

  /// Each kind of business has its colour, marking its stores wherever they
  /// show.
  Color trade(FormatDef format) {
    final (light, dark) = switch (format.key) {
      'supermarket' => (const Color(0xFF2F7D4F), const Color(0xFF6DB88A)),
      'fastfood' => (const Color(0xFFC98A12), const Color(0xFFE3AE45)),
      'steakhouse' => (const Color(0xFF7A2E2A), const Color(0xFFC8716A)),
      'finedining' => (const Color(0xFF1F3A5F), const Color(0xFF94ADD8)),
      'electronics' => (const Color(0xFF2B6CB0), const Color(0xFF74A7E2)),
      _ => (const Color(0xFFC2412D), const Color(0xFFE36E58)),
    };
    return night ? dark : light;
  }

  @override
  Ledger copyWith() => this;

  @override
  Ledger lerp(Ledger? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// The game's look: an account book. Paper and ink, a serif for titles,
/// a plain sans for text, a monospace for figures, rules instead of cards.
ThemeData gameTheme(Brightness brightness) {
  final ledger = brightness == Brightness.dark
      ? Ledger.nightEdition
      : Ledger.day;
  final Ledger(:paper, :shade, :ink, :muted, :rule) = ledger;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: ink,
    onPrimary: paper,
    primaryContainer: shade,
    onPrimaryContainer: ink,
    secondary: muted,
    onSecondary: paper,
    secondaryContainer: shade,
    onSecondaryContainer: ink,
    tertiary: ledger.gain,
    onTertiary: paper,
    tertiaryContainer: shade,
    onTertiaryContainer: ink,
    error: ledger.loss,
    onError: paper,
    errorContainer: shade,
    onErrorContainer: ledger.loss,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceContainerLowest: paper,
    surfaceContainerLow: paper,
    surfaceContainer: shade,
    surfaceContainerHigh: shade,
    surfaceContainerHighest: shade,
    outline: rule,
    outlineVariant: rule,
    shadow: Colors.transparent,
    scrim: Colors.black54,
    inverseSurface: ink,
    onInverseSurface: paper,
    inversePrimary: paper,
    surfaceTint: Colors.transparent,
  );
  TextStyle text(double size, FontWeight weight, {String family = textFont}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: ink,
        height: family == textFont ? 1.35 : 1.2,
      );
  final textTheme = TextTheme(
    displaySmall: text(34, FontWeight.w700, family: displayFont),
    headlineMedium: text(28, FontWeight.w700, family: displayFont),
    headlineSmall: text(24, FontWeight.w600, family: displayFont),
    titleLarge: text(21, FontWeight.w600, family: displayFont),
    titleMedium: text(17, FontWeight.w600, family: titleFont),
    titleSmall: text(15, FontWeight.w600, family: titleFont),
    bodyLarge: text(16, FontWeight.w400),
    bodyMedium: text(14, FontWeight.w400),
    bodySmall: text(12.5, FontWeight.w400).copyWith(color: muted),
    labelLarge: text(14, FontWeight.w500),
    labelMedium: text(12.5, FontWeight.w500),
    labelSmall: text(11.5, FontWeight.w500),
  );
  final square = RoundedRectangleBorder(borderRadius: BorderRadius.circular(3));
  final selected = WidgetState.selected;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: textFont,
    textTheme: textTheme,
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    splashFactory: InkRipple.splashFactory,
    extensions: [ledger],
    dividerTheme: DividerThemeData(color: rule, thickness: 0.8, space: 16),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(color: rule, width: 0.8),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: ink, width: 2)),
      titleTextStyle: textTheme.titleLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 58,
      elevation: 0,
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: shade,
      indicatorShape: square,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelSmall?.copyWith(
          color: states.contains(selected) ? ink : muted,
          fontWeight: states.contains(selected)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(selected) ? ink : muted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: paper,
        disabledBackgroundColor: shade,
        disabledForegroundColor: muted,
        shape: square,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink),
        shape: square,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        shape: square,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: square,
      side: BorderSide(color: ink, width: 0.8),
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(selected) ? ink : Colors.transparent,
      ),
      // Unpicked and picked: the label in ink, then in paper on ink.
      labelStyle: textTheme.labelMedium,
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: paper),
      selectedColor: ink,
      secondarySelectedColor: ink,
      checkmarkColor: paper,
      iconTheme: IconThemeData(color: ink, size: 16),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: ink,
        selectedForegroundColor: paper,
        foregroundColor: ink,
        side: BorderSide(color: ink, width: 0.8),
        shape: square,
        textStyle: textTheme.labelMedium,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(selected) ? paper : muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(selected) ? ink : shade,
      ),
      trackOutlineColor: WidgetStateProperty.all(rule),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: ink,
      inactiveTrackColor: rule,
      thumbColor: ink,
      overlayColor: ink.withValues(alpha: 0.08),
      trackHeight: 2,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: rule,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      titleTextStyle: textTheme.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: rule,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: rule),
      ),
      textStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: paper),
      actionTextColor: paper,
      shape: square,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: UnderlineInputBorder(borderSide: BorderSide(color: ink)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: ink)),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: ink, width: 2),
      ),
      labelStyle: TextStyle(color: muted),
      floatingLabelStyle: TextStyle(color: ink),
    ),
    listTileTheme: ListTileThemeData(iconColor: ink, textColor: ink),
    badgeTheme: BadgeThemeData(backgroundColor: ledger.loss),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(3),
      ),
      textStyle: textTheme.labelSmall?.copyWith(color: paper),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ink,
      selectionColor: rule,
      selectionHandleColor: ink,
    ),
  );
}

/// [base] set in the figures' face, columns lined up.
TextStyle figures(TextStyle? base) => (base ?? const TextStyle()).copyWith(
  fontFamily: figuresFont,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Green ink for gains and red ink for losses; plain muted ink for nothing.
Color gainTone(BuildContext context, int sign) {
  final ledger = Ledger.of(context);
  if (sign == 0) return ledger.muted;
  return sign > 0 ? ledger.gain : ledger.loss;
}

/// An ink for each turn of the business cycle.
Color regimeColor(RegimeDef regime) => switch (regime.key) {
  'expansion' => const Color(0xFF3B7A47),
  'slowdown' => const Color(0xFFB07A1A),
  'recession' => const Color(0xFFB3423A),
  'recovery' => const Color(0xFF3A6A9E),
  _ =>
    regime.demand >= Fx.one ? const Color(0xFF3B7A47) : const Color(0xFFB07A1A),
};

IconData regimeIcon(RegimeDef regime) => switch (regime.key) {
  'expansion' => Icons.trending_up,
  'slowdown' => Icons.trending_flat,
  'recession' => Icons.trending_down,
  'recovery' => Icons.moving,
  _ => Icons.show_chart,
};

IconData categoryIcon(CategoryDef category) => switch (category.key) {
  'milk' => Icons.local_drink_outlined,
  'bread' => Icons.bakery_dining_outlined,
  'snacks' => Icons.cookie_outlined,
  'drinks' => Icons.sports_bar_outlined,
  'produce' => Icons.eco_outlined,
  'household' => Icons.cleaning_services_outlined,
  _ => Icons.shopping_basket_outlined,
};

IconData formatIcon(FormatDef format) => switch (format.key) {
  'fastfood' => Icons.lunch_dining_outlined,
  'steakhouse' => Icons.outdoor_grill_outlined,
  'finedining' => Icons.restaurant_outlined,
  'supermarket' => Icons.local_grocery_store_outlined,
  'electronics' => Icons.devices_outlined,
  _ => Icons.storefront_outlined,
};

IconData slotIcon(DaySlot slot) => switch (slot) {
  DaySlot.morning => Icons.wb_twilight,
  DaySlot.midday => Icons.wb_sunny_outlined,
  DaySlot.evening => Icons.nights_stay_outlined,
  DaySlot.night => Icons.bedtime_outlined,
};
