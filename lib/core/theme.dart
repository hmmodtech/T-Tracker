import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// T-Tracker — dual palettes
//
// DARK  : midnight navy HUD with neon cyan-green bloom (as before).
// LIGHT : soft daylight variant of the same identity — pale blue paper,
//         petrol text, teal accents. Easy on the eyes, never pure white.
//
// Historical names (kGreen, kDimGreen, kBlack …) are kept because they are used
// everywhere; they resolve to the active palette at paint time.
// ─────────────────────────────────────────────────────────────────────────────

// ── Dark palette (default) ───────────────────────────────────────────────────
const _dGreen = Color(0xFF25F4C8);
const _dDim = Color(0xFF14B8CE);
const _dAqua = Color(0xFF38BDF8);
const _dBlack = Color(0xFF04070F);
const _dSurface = Color(0xFF0A1424);
const _dPetrol = Color(0xFF1B3A55);
const _dMuted = Color(0xFF7C8FAB);
const _dMutedGreen = Color(0xFF6E9E8F);
const _dText = Color(0xFFD7E6F5);

// ── Light palette ────────────────────────────────────────────────────────────
const _lGreen = Color(0xFF0E9E86); // teal that still reads on white
const _lDim = Color(0xFF127C96);
const _lAqua = Color(0xFF2E86C8);
const _lPaper = Color(0xFFEEF3F8); // soft blue-grey paper, not white
const _lSurface = Color(0xFFFAFCFE);
const _lPetrol = Color(0xFFC3D3E2);
const _lMuted = Color(0xFF61758C);
const _lMutedGreen = Color(0xFF4C7D71);
const _lText = Color(0xFF16283C);

bool get isLight => appState.lightMode;

/// Primary accent — neon cyan-green (dark) / deep teal (light).
Color get kGreen => isLight ? _lGreen : _dGreen;

/// Secondary accent.
Color get kDimGreen => isLight ? _lDim : _dDim;

/// Cold end of the glow gradient.
Color get kAqua => isLight ? _lAqua : _dAqua;

/// App background.
Color get kBlack => isLight ? _lPaper : _dBlack;

/// Panel surface.
Color get kSurface => isLight ? _lSurface : _dSurface;

/// Borders / dividers.
Color get kPetrol => isLight ? _lPetrol : _dPetrol;

/// Long-form secondary text.
Color get kMuted => isLight ? _lMuted : _dMuted;

/// Sub-headings.
Color get kMutedGreen => isLight ? _lMutedGreen : _dMutedGreen;

/// Primary body text.
Color get kText => isLight ? _lText : _dText;

Color get kRed => isLight ? const Color(0xFFD6374F) : const Color(0xFFFF5470);
Color get kAmber => isLight ? const Color(0xFFB57614) : const Color(0xFFFFC15E);

/// Neon bloom gradient: aqua → cyan-green → pale mint.
LinearGradient get kGlowGradient => LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [kAqua, kGreen, isLight ? const Color(0xFF7FE3CE) : const Color(0xFFB6FFE9)],
    );

/// Radial halo behind big numbers.
RadialGradient get kHaloGradient => RadialGradient(
      colors: [kGreen.withAlpha(isLight ? 45 : 85), kBlack.withAlpha(0)],
    );

/// Soft neon bloom for glowing text (disabled in light mode — it smudges).
List<Shadow> get kTextBloom => isLight
    ? const []
    : const [
        Shadow(color: Color(0x9925F4C8), blurRadius: 12),
        Shadow(color: Color(0x6625F4C8), blurRadius: 26),
      ];

/// Stronger bloom for hero numbers.
List<Shadow> get kTextBloomStrong => isLight
    ? const []
    : const [
        Shadow(color: Color(0xCC25F4C8), blurRadius: 18),
        Shadow(color: Color(0x8825F4C8), blurRadius: 40),
        Shadow(color: Color(0x4438BDF8), blurRadius: 60),
      ];

ThemeData appTheme() {
  final light = isLight;
  final barIcon = light ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: light ? Brightness.light : Brightness.dark,
    scaffoldBackgroundColor: kBlack,
    canvasColor: kBlack,
    colorScheme: ColorScheme(
      brightness: light ? Brightness.light : Brightness.dark,
      primary: kGreen,
      onPrimary: light ? Colors.white : kBlack,
      secondary: kAqua,
      onSecondary: light ? Colors.white : kBlack,
      surface: kSurface,
      onSurface: kText,
      error: kRed,
      onError: Colors.white,
      outline: kPetrol,
    ),
    dividerColor: kPetrol,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: kGreen,
      elevation: 0,
      systemOverlayStyle: light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      iconTheme: IconThemeData(color: kGreen),
      titleTextStyle: TextStyle(
        color: kGreen,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        shadows: kTextBloom,
      ),
    ),
    iconTheme: IconThemeData(color: kGreen),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: kText),
      bodySmall: TextStyle(color: kMuted),
      titleMedium: TextStyle(
        color: kGreen,
        fontWeight: FontWeight.w700,
        shadows: kTextBloom,
      ),
      labelSmall: TextStyle(color: kMutedGreen, letterSpacing: 1.1),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : const Color(0x99101E33),
      isDense: true,
      hintStyle: TextStyle(color: kMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPetrol),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kPetrol),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kGreen, width: 1.4),
      ),
    ),
    cardTheme: CardThemeData(
      color: light ? Colors.white : kSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kPetrol),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: kGreen,
      linearTrackColor: light ? const Color(0xFFD9E3EC) : const Color(0xFF12283D),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? kGreen : kMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? kGreen.withAlpha(90)
            : kPetrol,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? kGreen : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(light ? Colors.white : kBlack),
      side: BorderSide(color: kPetrol, width: 1.6),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: kGreen,
      inactiveTrackColor: kPetrol,
      thumbColor: kGreen,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kSurface,
      contentTextStyle: TextStyle(color: kText),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      titleTextStyle: TextStyle(color: kGreen, fontWeight: FontWeight.w700),
      contentTextStyle: TextStyle(color: kText),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kGreen,
      foregroundColor: light ? Colors.white : kBlack,
    ),
    listTileTheme: ListTileThemeData(iconColor: kGreen, textColor: kText),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: kSurface),
    dividerTheme: DividerThemeData(color: kPetrol, space: 1),
    // Light mode keeps the day tiles readable instead of washed out.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: kGreen.withAlpha(50),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(color: kText, fontSize: 11)),
    ),
  );
}

/// Alias kept so older call sites keep working.
ThemeData matrixTheme() => appTheme();

/// بطاقة زجاجية شفافة. الشفافية تتحكم فيها من الإعدادات.
BoxDecoration glass({Color? border, bool glow = true}) {
  final l = isLight;
  // في الوضع الفاتح لا نسمح للكارت بأن يشفّ أكثر من اللازم: النص الداكن
  // فوق الصورة الشفافة يصبح غير مقروء. حد أدنى 0.82 يبقي النص واضحاً
  // بينما يحافظ على إحساس الزجاج.
  final opacity = l
      ? appState.cardOpacity.clamp(0.82, 1.0)
      : appState.cardOpacity;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: l
          ? [
              Colors.white.withValues(alpha: opacity),
              const Color(0xFFF2F7FB).withValues(alpha: opacity),
            ]
          : [
              const Color(0xFF0C182A).withValues(alpha: opacity),
              const Color(0xFF060C18).withValues(alpha: opacity),
            ],
    ),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: border ?? kPetrol),
    boxShadow: glow
        ? l
            ? [
                BoxShadow(
                  color: const Color(0xFF16283C).withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: kGreen.withValues(alpha: 0.08),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: kAqua.withValues(alpha: 0.05),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ]
        : null,
  );
}

/// شريط تقدّم متوهّج (تدرّج + هالة).
class GlowBar extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color? color;

  const GlowBar({super.key, required this.value, this.height = 6, this.color});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(
                color: isLight ? const Color(0xFFD9E3EC) : const Color(0xFF12283D),
                borderRadius: BorderRadius.circular(height),
              ),
            ),
            if (v > 0)
              Container(
                height: height,
                width: c.maxWidth * v,
                decoration: BoxDecoration(
                  gradient: color == null
                      ? kGlowGradient
                      : LinearGradient(colors: [color!.withAlpha(150), color!]),
                  borderRadius: BorderRadius.circular(height),
                  boxShadow: isLight
                      ? null
                      : [
                          BoxShadow(
                            color: (color ?? kGreen).withAlpha(140),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// رقم/عنوان متوهّج.
class GlowText extends StatelessWidget {
  final String text;
  final double size;
  final FontWeight weight;
  final bool strong;

  const GlowText(
    this.text, {
    super.key,
    this.size = 16,
    this.weight = FontWeight.w800,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: kGreen,
        shadows: strong ? kTextBloomStrong : kTextBloom,
      ),
    );
  }
}

/// عنوان قسم فرعي.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: kMutedGreen,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      );
}

Color catColor(String c) => switch (c) {
      'security' => kRed,
      'logistics' => kAmber,
      'child' => kAqua,
      'admin' => isLight ? const Color(0xFF7A5AF8) : const Color(0xFFA78BFA),
      _ => kGreen,
    };

String catLabel(String c) => switch (c) {
      'security' => appState.t('Security', 'الأمن'),
      'logistics' => appState.t('Logistics', 'اللوجستيات'),
      'child' => appState.t('Child Protection', 'حماية الطفل'),
      'admin' => appState.t('Admin', 'الإدارة'),
      _ => appState.t('General', 'عام'),
    };

String repeatLabel(String r) => switch (r) {
      'daily' => appState.t('Daily', 'يومياً'),
      'weekly' => appState.t('Weekly', 'أسبوعياً'),
      'monthly' => appState.t('Monthly', 'شهرياً'),
      _ => appState.t('Once', 'مرة واحدة'),
    };
