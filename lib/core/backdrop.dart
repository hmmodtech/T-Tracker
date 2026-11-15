import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

/// خلفية التطبيق "المنحوتة".
///
/// الصورة المرفقة (الأرض ليلاً مع حدود متوهجة) تُرسم مع:
///  • تعتيم جهة اليمين والأسفل حتى تبقى أسماء الأيام والبطاقات مقروءة،
///  • تدرّج كحلي فوقها يجعلها تندمج مع هوية التطبيق,
///  • هالة ضوئية (bloom) في الأعلى تحاكي شروق الشمس في الصورة.
///
/// في الوضع الفاتح تُستخدم نفس الصورة لكن بشفافية أعلى وتعتيم أبيض خفيف،
/// حتى تحسّ بالهوية نفسها دون إجهاد العين.
class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final light = isLight;
    final showPhoto = appState.photoBackground;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1) القاعدة: لون داكن/فاتح صلب (يمنع أي وميض عند الإقلاع)
        ColoredBox(color: kBlack),

        // 2) الصورة نفسها — تُحمّل مرة واحدة وتبقى في الكاش
        if (showPhoto)
          const RepaintBoundary(
            child: Image(
              image: AssetImage('assets/images/night_earth.jpg'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
          ),

        // 3) تدرّجات التظليل — تجعل النص مقروءاً فوق أي تفصيل في الصورة
        if (showPhoto)
          const RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.35, 0.72, 1.0],
                  colors: [
                    Color(0x22000000),
                    Color(0x7704070F),
                    Color(0xDD04070F),
                    Color(0xF204070F),
                  ],
                ),
              ),
            ),
          ),

        // 4) الوضع الفاتح: حجاب لبني فاتح يرفع التباين ويخفف الإضاءة
        if (showPhoto && light)
          ColoredBox(color: const Color(0xFFEEF3F8).withValues(alpha: 0.82)),

        // 5) هالة علوية تحاكي شروق الشمس في الصورة
        if (showPhoto && !light)
          const RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.85, -1.0),
                  radius: 1.1,
                  colors: [Color(0x3325F4C8), Color(0x0004070F)],
                ),
              ),
            ),
          ),

        // 6) طبقة تهدئة بسيطة عند إخفاء الصورة
        if (!showPhoto)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.3,
                colors: light
                    ? const [Color(0xFFF7FAFD), Color(0xFFE9F0F7)]
                    : [Color(0xFF0A1830), kBlack],
              ),
            ),
          ),

        // 7) المحتوى
        child,
      ],
    );
  }
}

/// لوح زجاجي شفاف: ضبابية حقيقية + حد رقيق + لمعة علوية.
/// أخف من Blur على الأجهزة الضعيفة (blur اختياري).
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? border;
  final bool blur;
  final double radius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin,
    this.border,
    this.blur = false,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final light = isLight;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [
                  Colors.white.withValues(alpha: appState.cardOpacity),
                  const Color(0xFFF4F8FC).withValues(alpha: appState.cardOpacity),
                ]
              : [
                  const Color(0xFF0C182A).withValues(alpha: appState.cardOpacity),
                  const Color(0xFF060C18).withValues(alpha: appState.cardOpacity),
                ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? kPetrol.withValues(alpha: 0.9)),
        boxShadow: light
            ? [
                BoxShadow(
                  color: const Color(0xFF16283C).withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: kGreen.withValues(alpha: 0.07),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );

    final widget = blur
        ? ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: content,
            ),
          )
        : content;

    return margin == null ? widget : Padding(padding: margin!, child: widget);
  }
}
