import 'package:flutter/material.dart';

/// اتجاه النص الذكي (Bidi).
///
/// المشكلة: لو كانت لغة التطبيق إنجليزي وكتبت «اجتماع مع UNRWA الساعة 10»
/// فالإطار يربط الكلمات الإنجليزية من اليسار لليمين ويعكس ترتيب المقاطع.
///
/// الحل: نحسب اتجاه أول حرف «قوي» في النص (حرف عربي/عبري = RTL، حرف لاتيني
/// = LTR) ونطبّق الاتجاه الناتج على النص نفسه — تماماً كما يفعل Word.
/// وإذا كان النص يحتوي على سطر عربي واحد على الأقل نُرجّح العربي.
///
/// النتيجة: الكلمات الإنجليزية تبقى مقروءة داخل جملة عربية، والعكس صحيح.
enum TextDir { rtl, ltr, neutral }

/// نطاقات الحروف العربية/العبرية والفارسية والأردية.
bool _isRtlRune(int c) =>
    (c >= 0x0590 && c <= 0x05FF) || // Hebrew
    (c >= 0x0600 && c <= 0x06FF) || // Arabic
    (c >= 0x0750 && c <= 0x077F) || // Arabic Supplement
    (c >= 0x08A0 && c <= 0x08FF) || // Arabic Extended-A
    (c >= 0xFB50 && c <= 0xFDFF) || // Arabic Presentation A
    (c >= 0xFE70 && c <= 0xFEFF) || // Arabic Presentation B
    (c >= 0x1EE00 && c <= 0x1EEFF); // Arabic Mathematical

bool _isLtrRune(int c) =>
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    (c >= 0x00C0 && c <= 0x024F) || // Latin-1/Extended
    (c >= 0x0370 && c <= 0x03FF) || // Greek
    (c >= 0x0400 && c <= 0x04FF) || // Cyrillic
    (c >= 0x0900 && c <= 0x0DFF); // Indic

/// يحدّد اتجاه النص حسب أول حرف ذي اتجاه، مع ترجيح العربي عند التعادل.
TextDir detectDir(String? text) {
  if (text == null || text.isEmpty) return TextDir.neutral;
  var firstRtl = -1;
  var firstLtr = -1;
  for (final rune in text.runes) {
    if (_isRtlRune(rune)) {
      if (firstRtl < 0) firstRtl = rune;
      if (firstLtr < 0) continue;
      break;
    }
    if (_isLtrRune(rune)) {
      if (firstLtr < 0) firstLtr = rune;
      if (firstRtl < 0) continue;
      break;
    }
  }
  if (firstRtl >= 0 && firstLtr < 0) return TextDir.rtl;
  if (firstLtr >= 0 && firstRtl < 0) return TextDir.ltr;
  if (firstRtl >= 0 && firstLtr >= 0) {
    // الاثنان موجودان: الأول في النص هو الحاكم.
    final rtlIndex = _firstIndexOf(text, _isRtlRune);
    final ltrIndex = _firstIndexOf(text, _isLtrRune);
    return rtlIndex <= ltrIndex ? TextDir.rtl : TextDir.ltr;
  }
  return TextDir.neutral;
}

int _firstIndexOf(String s, bool Function(int) test) {
  var i = 0;
  for (final rune in s.runes) {
    if (test(rune)) return i;
    i++;
  }
  return 1 << 30;
}

bool containsArabic(String? text) {
  if (text == null) return false;
  for (final rune in text.runes) {
    if (_isRtlRune(rune)) return true;
  }
  return false;
}

bool containsLatin(String? text) {
  if (text == null) return false;
  for (final rune in text.runes) {
    if (_isLtrRune(rune)) return true;
  }
  return false;
}

/// نص مختلط: عربي + إنجليزي في نفس السلسلة.
bool isMixed(String? text) => containsArabic(text) && containsLatin(text);

/// هل النص عربي صافٍ (لا لاتيني فيه)؟
bool isArabicOnly(String? text) => containsArabic(text) && !containsLatin(text);

/// نص بدون أي اتجاه (أرقام/رموز فقط).
bool isNeutral(String? text) => detectDir(text) == TextDir.neutral;

TextDirection directionFor(String? text) {
  final d = detectDir(text);
  if (d == TextDir.neutral) {
    final ctx = _fallbackContext;
    if (ctx != null && ctx.mounted) {
      return Directionality.maybeOf(ctx) ?? TextDirection.ltr;
    }
    return TextDirection.ltr;
  }
  return d == TextDir.rtl ? TextDirection.rtl : TextDirection.ltr;
}

/// سياق احتياطي يُحدَّث من أعلى الشجرة (انظر [BidiScope]).
BuildContext? _fallbackContext;

/// يخزّن سياق الجذر حتى نستخدم اتجاه التطبيق للنصوص المحايدة.
class BidiScope extends StatelessWidget {
  final Widget child;
  const BidiScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    _fallbackContext = context;
    return child;
  }
}

/// يعرض [text] باتجاهه الصحيح تلقائياً، بغض النظر عن لغة التطبيق.
///
/// [force] لتجاوز الكشف (مثلاً عنوان ثابت بالعربية).
class BidiText extends StatelessWidget {
  final String? text;
  final TextStyle? style;
  final TextAlign? align;
  final int? maxLines;
  final bool? softWrap;
  final TextOverflow? overflow;
  final bool selectable;
  final TextDir? force;

  const BidiText(
    this.text, {
    super.key,
    this.style,
    this.align,
    this.maxLines,
    this.softWrap,
    this.overflow,
    this.selectable = false,
    this.force,
  });

  @override
  Widget build(BuildContext context) {
    final t = text ?? '';
    final dir = force ?? detectDir(t);
    final textDirection = switch (dir) {
      TextDir.rtl => TextDirection.rtl,
      TextDir.ltr => TextDirection.ltr,
      TextDir.neutral => Directionality.of(context),
    };

    // النص المحايد يتبع التطبيق؛ غير ذلك يتبع محتواه.
    final effectiveAlign = align ??
        (dir == TextDir.neutral
            ? TextAlign.start
            : (dir == TextDir.rtl ? TextAlign.right : TextAlign.left));

    final base = style ?? DefaultTextStyle.of(context).style;

    if (selectable) {
      return SelectableText(
        t,
        style: base,
        textAlign: effectiveAlign,
        textDirection: textDirection,
        maxLines: maxLines,
      );
    }
    return Text(
      t,
      style: base,
      textAlign: effectiveAlign,
      textDirection: textDirection,
      maxLines: maxLines,
      softWrap: softWrap,
      overflow: overflow,
    );
  }
}

/// حقل إدخال يضبط اتجاه المؤشر والنص أثناء الكتابة.
///
/// إن كتبت عربي → المؤشر والمحاذاة من اليمين.
/// إن كتبت إنجليزي → من اليسار.
/// إن خلطت → يتبع أول حرف، تماماً كـ Word.
class BidiField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final TextStyle? style;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool dense;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? labelText;
  final bool enabled;

  const BidiField({
    super.key,
    required this.controller,
    this.hintText,
    this.style,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.dense = true,
    this.prefixIcon,
    this.suffixIcon,
    this.labelText,
    this.enabled = true,
  });

  @override
  State<BidiField> createState() => _BidiFieldState();
}

class _BidiFieldState extends State<BidiField> {
  TextDir _dir = TextDir.neutral;

  @override
  void initState() {
    super.initState();
    _dir = detectDir(widget.controller.text);
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final next = detectDir(widget.controller.text);
    if (next != _dir && next != TextDir.neutral) {
      setState(() => _dir = next);
    }
    widget.onChanged?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final direction = _dir == TextDir.neutral
        ? Directionality.of(context)
        : (_dir == TextDir.rtl ? TextDirection.rtl : TextDirection.ltr);

    return Directionality(
      textDirection: direction,
      child: TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        style: widget.style,
        maxLines: widget.expands ? null : widget.maxLines,
        minLines: widget.minLines,
        expands: widget.expands,
        keyboardType: widget.keyboardType ??
            (widget.maxLines == 1
                ? TextInputType.text
                : TextInputType.multiline),
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        textAlign: direction == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
        decoration: InputDecoration(
          hintText: widget.hintText,
          labelText: widget.labelText,
          isDense: widget.dense,
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
        ),
      ),
    );
  }
}
