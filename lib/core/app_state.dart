import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// بداية خطة المهام الافتراضية (15 تشرين الثاني).
const _defaultStart = '2026-11-15';

final appState = AppState();

/// الإعدادات واللغة والقفل. كل تغيير ينحفظ ويحدّث الواجهة فوراً.
class AppState extends ChangeNotifier {
  bool isArabic = false;
  double cardOpacity = 0.85; // 0.3 – 1.0
  double textScale = 1.0; // 0.8 – 1.4
  bool notificationsOn = true;
  bool morningBriefing = true;
  bool matrixRain = true;

  /// خلفية الأرض الليلية (الصورة المرفقة). تُرسم بشفافية فوقها البطاقات.
  bool photoBackground = true;

  /// الوضع الفاتح المريح للعين.
  bool lightMode = false;

  bool appLock = false;
  bool panicOnBackground = false;
  bool seeded = false;
  String missionStart = _defaultStart;

  /// نسخة خطة المهام. رفعها يعيد بناء الخطة على الأجهزة القديمة.
  /// v1 = بداية 16-11 بلا نهاية، v2 = 15-11 → 13-12.
  int planVersion = 0;

  /// حجم خط الودجت (sp) — 10..18
  double widgetTextScale = 1.0;

  /// شفافية لوحة الودجت — 0.35..0.95
  double widgetOpacity = 0.85;

  bool panicActive = false; // شاشة سوداء فورية
  bool locked = false; // مطلوب بصمة / PIN

  late SharedPreferences _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    isArabic = _p.getBool('ar') ?? false;
    cardOpacity = _p.getDouble('opacity') ?? 0.85;
    textScale = _p.getDouble('textScale') ?? 1.0;
    notificationsOn = _p.getBool('notifs') ?? true;
    morningBriefing = _p.getBool('briefing') ?? true;
    matrixRain = _p.getBool('rain') ?? false;
    photoBackground = _p.getBool('photoBg') ?? true;
    lightMode = _p.getBool('lightMode') ?? false;
    appLock = _p.getBool('lock') ?? false;
    // الخروج من التطبيق لم يعد يخفي الشاشة.
    panicOnBackground = false;
    seeded = _p.getBool('seeded') ?? false;
    missionStart = _p.getString('missionStart') ?? _defaultStart;
    planVersion = _p.getInt('planVersion') ?? 0;
    widgetTextScale = _p.getDouble('widgetTextScale') ?? 1.0;
    widgetOpacity = _p.getDouble('widgetOpacity') ?? 0.85;
    locked = appLock;
  }

  /// t('Save', 'حفظ') ترجع النص حسب اللغة الحالية
  String t(String en, String ar) => isArabic ? ar : en;

  void _put(String key, Object value, void Function() assign,
      {bool persist = true}) {
    assign();
    if (persist && value is bool) {
      _p.setBool(key, value);
    } else if (persist && value is double) {
      _p.setDouble(key, value);
    } else if (persist && value is String) {
      _p.setString(key, value);
    } else if (persist && value is int) {
      _p.setInt(key, value);
    }
    notifyListeners();
  }

  void setArabic(bool v) => _put('ar', v, () => isArabic = v);
  void setOpacity(double v) => _put('opacity', v, () => cardOpacity = v);
  void setTextScale(double v) => _put('textScale', v, () => textScale = v);
  void setNotifs(bool v) => _put('notifs', v, () => notificationsOn = v);
  void setBriefing(bool v) => _put('briefing', v, () => morningBriefing = v);
  void setRain(bool v) => _put('rain', v, () => matrixRain = v);
  void setPhotoBg(bool v) => _put('photoBg', v, () => photoBackground = v);
  void setLightMode(bool v) => _put('lightMode', v, () => lightMode = v);
  // Intentional no-op: leaving the app must not hide/lock the screen any more.
  void setPanicBg(bool v) {}
  void setWidgetTextScale(double v) =>
      _put('widgetTextScale', v, () => widgetTextScale = v);
  void setWidgetOpacity(double v) =>
      _put('widgetOpacity', v, () => widgetOpacity = v);
  void setLock(bool v) => _put('lock', v, () {
        appLock = v;
        locked = false;
      }, persist: false);
  /// تغيير بداية الخطة يعيد بناءها في الإقلاع التالي.
  void setMissionStart(String v) => _put('missionStart', v, () {
        missionStart = v;
        planVersion = 0;
      }, persist: false);
  void markSeeded() => _put('seeded', true, () => seeded = true);

  /// يعلّم الخطة كنسخة [v] بعد إعادة بنائها.
  void markPlanVersion(int v) => _put('planVersion', v, () => planVersion = v);

  void setPanic(bool v) {
    panicActive = v;
    notifyListeners();
  }

  void setLocked(bool v) {
    locked = v;
    notifyListeners();
  }
}
