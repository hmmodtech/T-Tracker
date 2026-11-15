import 'stats_screen.dart';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/boot_log.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../services/calendar_sync.dart';
import '../services/export.dart';
import '../services/notifications.dart';
import '../services/widget_bridge.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  String s(String en, String ar) => appState.t(en, ar);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Private tasks are never sent to calendars or exported.
  Future<List<Task>> _shareable() async {
    final all = await Db.instance.tasks();
    return all.where((t) => !t.isPrivate).toList();
  }

  // Runs a long action with a progress bar and shows the result.
  // Errors are shown generically; details are never printed or logged.
  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await action();
      _snack(msg);
    } catch (_) {
      _snack(s(
        'Action failed. Check your connection and try again.',
        'فشلت العملية. تحقّق من الاتصال وجرّب مرة ثانية.',
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNotifs(bool v) async {
    setState(() {
      appState.setNotifs(v);
    });
    await Bell.resyncAll();
  }

  Future<void> _setBriefing(bool v) async {
    setState(() {
      appState.setBriefing(v);
    });
    await Bell.resyncAll();
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          text,
          style: TextStyle(
            color: kGreen,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _card(Widget child) => Card(color: Colors.transparent, child: child);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s('Settings', 'الإعدادات')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) LinearProgressIndicator(color: kGreen),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---------- Appearance ----------
                  _header(s('APPEARANCE', 'المظهر')),
                  _card(Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s('Card and day transparency', 'شفافية البطاقات والأيام')}: '
                          '${(appState.cardOpacity * 100).round()}%',
                        ),
                        Slider(
                          value: appState.cardOpacity,
                          min: 0.3,
                          max: 1.0,
                          divisions: 14,
                          onChanged: (v) {
                            setState(() {
                              appState.setOpacity(v);
                            });
                          },
                        ),
                      ],
                    ),
                  )),
                  _card(Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s('Text size', 'حجم الخط')}: '
                          '${(appState.textScale * 100).round()}%',
                        ),
                        Slider(
                          value: appState.textScale,
                          min: 0.8,
                          max: 1.4,
                          divisions: 6,
                          onChanged: (v) {
                            setState(() {
                              appState.setTextScale(v);
                            });
                          },
                        ),
                      ],
                    ),
                  )),
                  _card(SwitchListTile(
                    secondary: Icon(Icons.grain, color: kGreen),
                    title: Text(s('Matrix rain background', 'خلفية المطر الرقمي')),
                    value: appState.matrixRain,
                    onChanged: (v) {
                      setState(() {
                        appState.setRain(v);
                      });
                    },
                  )),
                  _card(SwitchListTile(
                    secondary: Icon(Icons.translate, color: kGreen),
                    title: Text(s('Arabic language', 'اللغة العربية')),
                    subtitle: Text(s('Off = English', 'مغلق = إنجليزي')),
                    value: appState.isArabic,
                    onChanged: (v) {
                      setState(() {
                        appState.setArabic(v);
                      });
                      WidgetBridge.sync();
                    },
                  )),

                  // ---------- Light mode ----------
                  _card(SwitchListTile(
                    secondary: Icon(
                      appState.lightMode
                          ? Icons.light_mode
                          : Icons.dark_mode_outlined,
                      color: kGreen,
                    ),
                    title: Text(s('Light mode', 'الوضع الفاتح')),
                    subtitle: Text(s(
                      'Soft daylight colours, easy on the eyes',
                      'ألوان نهارية هادئة ومريحة للعين',
                    )),
                    value: appState.lightMode,
                    onChanged: (v) {
                      setState(() {
                        appState.setLightMode(v);
                      });
                    },
                  )),
                  _card(SwitchListTile(
                    secondary: Icon(Icons.image_outlined, color: kGreen),
                    title: Text(s('Night-earth background', 'خلفية الأرض ليلاً')),
                    subtitle: Text(s(
                      'The photo, blended into the theme',
                      'الصورة مدمجة مع ألوان التطبيق',
                    )),
                    value: appState.photoBackground,
                    onChanged: (v) {
                      setState(() {
                        appState.setPhotoBg(v);
                      });
                    },
                  )),

                  // ---------- Widgets ----------
                  _header(s('HOME-SCREEN WIDGETS', 'ودجت الشاشة الرئيسية')),
                  _card(Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${s('Widget font size', 'حجم خط الودجت')}: '
                          '${(appState.widgetTextScale * 100).round()}%',
                        ),
                        Slider(
                          value: appState.widgetTextScale,
                          min: 0.9,
                          max: 1.5,
                          divisions: 6,
                          onChanged: (v) {
                            setState(() {
                              appState.setWidgetTextScale(v);
                            });
                          },
                          onChangeEnd: (_) => WidgetBridge.pushSettings(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${s('Widget panel opacity', 'شفافية لوحة الودجت')}: '
                          '${(appState.widgetOpacity * 100).round()}%',
                        ),
                        Slider(
                          value: appState.widgetOpacity,
                          min: 0.5,
                          max: 1.0,
                          divisions: 5,
                          onChanged: (v) {
                            setState(() {
                              appState.setWidgetOpacity(v);
                            });
                          },
                          onChangeEnd: (_) => WidgetBridge.pushSettings(),
                        ),
                        Text(
                          s(
                            'Applies to the tasks, memo, result and calendar widgets.',
                            'تُطبّق على ودجت المهام والميمو والنتيجة والتقويم.',
                          ),
                          style: TextStyle(fontSize: 12, color: kMuted),
                        ),
                      ],
                    ),
                  )),

                  // ---------- Notifications ----------
                  _header(s('NOTIFICATIONS', 'الإشعارات')),
                  _card(SwitchListTile(
                    secondary: Icon(Icons.notifications, color: kGreen),
                    title: Text(s('Task bell reminders', 'تذكيرات الجرس للمهام')),
                    value: appState.notificationsOn,
                    onChanged: (v) => _setNotifs(v),
                  )),
                  _card(SwitchListTile(
                    secondary: Icon(Icons.wb_sunny_outlined, color: kGreen),
                    title: Text(s('Morning briefing (07:30)', 'الملخص الصباحي (07:30)')),
                    value: appState.morningBriefing,
                    onChanged: (v) => _setBriefing(v),
                  )),
                  _card(ListTile(
                    leading: Icon(Icons.send, color: kGreen),
                    title: Text(s('Send test notification', 'إرسال إشعار تجريبي')),
                    onTap: () => _run(() async {
                      await Bell.test();
                      return s('Test notification sent', 'تم إرسال إشعار تجريبي');
                    }),
                  )),

                  // ---------- Security ----------
                  _header(s('SECURITY', 'الأمان')),
                  _card(SwitchListTile(
                    secondary: Icon(Icons.fingerprint, color: kGreen),
                    title: Text(s('Lock app with fingerprint or PIN', 'قفل التطبيق ببصمة أو رمز')),
                    subtitle: Text(s(
                      'Locks when you leave the app',
                      'يقفل لما تخرج من التطبيق',
                    )),
                    value: appState.appLock,
                    onChanged: (v) {
                      setState(() {
                        appState.setLock(v);
                      });
                    },
                  )),
                  _card(ListTile(
                    secondary: Icon(Icons.shield_outlined, color: kRed),
                    title: Text(s('Panic screen now', 'شاشة الطوارئ الآن')),
                    subtitle: Text(s(
                      'Hides the app instantly — use it only when needed',
                      'تخفي التطبيق فوراً — استخدمها عند الحاجة فقط',
                    )),
                    onTap: () => appState.setPanic(true),
                  )),

                  // ---------- Calendars ----------
                  _header(s('CALENDARS (PUSH ONLY)', 'التقويمات (إرسال فقط)')),
                  _card(ListTile(
                    leading: Icon(Icons.calendar_month, color: kGreen),
                    title: Text(s('Sync to Google Calendar', 'مزامنة مع تقويم Google')),
                    subtitle: Text(s(
                      'Private tasks are never sent',
                      'المهام الخاصة ما بتنرسل أبداً',
                    )),
                    onTap: () => _run(() async {
                      final n = await GoogleCal.sync(await _shareable());
                      return s(
                        'Synced $n tasks to Google Calendar',
                        'تمت مزامنة $n مهمة مع تقويم Google',
                      );
                    }),
                  )),
                  _card(ListTile(
                    leading: Icon(Icons.event_note, color: kGreen),
                    title: Text(s('Sync to Microsoft 365', 'مزامنة مع Microsoft 365')),
                    subtitle: Text(s(
                      'Private tasks are never sent',
                      'المهام الخاصة ما بتنرسل أبداً',
                    )),
                    onTap: () => _run(() async {
                      final n = await MsCal.sync(await _shareable());
                      return s(
                        'Synced $n tasks to Microsoft 365',
                        'تمت مزامنة $n مهمة مع Microsoft 365',
                      );
                    }),
                  )),
                  _header(s('REPORTS', 'التقارير')),
                  _card(ListTile(
                  leading: Icon(Icons.bar_chart, color: kGreen),
                  title: Text(s('Completion reports', 'تقارير الإنجاز')),
                  trailing: Icon(Icons.chevron_right, color: kDimGreen),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StatsScreen()),
                  ),
                )),

                  // ---------- Data ----------
                  _header(s('DATA', 'البيانات')),
                  _card(ListTile(
                    leading: Icon(Icons.event_available, color: kGreen),
                    title: Text(s('Export calendar (.ics)', 'تصدير التقويم (.ics)')),
                    subtitle: Text(s(
                      'Opens in Google Calendar or Outlook',
                      'بيفتح في Google Calendar أو Outlook',
                    )),
                    onTap: () => _run(() async {
                      final tasks = await _shareable();
                      await shareFile('sos_calendar.ics', toIcs(tasks), 'text/calendar');
                      return s('Calendar file ready', 'ملف التقويم جاهز');
                    }),
                  )),
                  _card(ListTile(
                    leading: Icon(Icons.table_chart_outlined, color: kGreen),
                    title: Text(s('Export tasks (.csv)', 'تصدير المهام (.csv)')),
                    onTap: () => _run(() async {
                      final tasks = await _shareable();
                      await shareFile('sos_tasks.csv', toCsv(tasks), 'text/csv');
                      return s('CSV file ready', 'ملف CSV جاهز');
                    }),
                  )),
                  _card(ListTile(
                    leading: Icon(Icons.backup, color: kGreen),
                    title: Text(s('Create backup (.json)', 'إنشاء نسخة احتياطية (.json)')),
                    onTap: () => _run(() async {
                      await exportBackup();
                      return s('Backup created', 'تم إنشاء النسخة الاحتياطية');
                    }),
                  )),
                  _card(ListTile(
                    leading: Icon(Icons.restore, color: kGreen),
                    title: Text(s('Restore from backup', 'استعادة من نسخة احتياطية')),
                    onTap: () => _run(() async {
                      final ok = await importBackup();
                      if (!ok) {
                        return s('No file was imported', 'ما تم استيراد أي ملف');
                      }
                      await Bell.resyncAll();
                      return s('Backup restored', 'تمت استعادة النسخة الاحتياطية');
                    }),
                  )),
                  _header(s('Diagnostics', 'التشخيص')),
                  _card(ListTile(
                    leading: Icon(Icons.bug_report_outlined, color: kGreen),
                    title: Text(s('Startup log', 'سجل بدء التشغيل')),
                    subtitle: Text(
                      bootLog.isEmpty
                          ? s('No problems recorded', 'لا توجد مشاكل مسجّلة')
                          : s('${bootLog.length} entry(s)', '${bootLog.length} سجل'),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () => _showLog(),
                  )),
                  _card(ListTile(
                    leading: Icon(Icons.restart_alt, color: kGreen),
                    title: Text(s('Re-apply reminders', 'إعادة ضبط الإشعارات')),
                    subtitle: Text(
                      s('Run if bells stop arriving', 'شغّلها إذا توقفت الإشعارات'),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () => _run(() async {
                      await Bell.resyncAll();
                      return s('Reminders re-applied', 'تمت إعادة ضبط الإشعارات');
                    }),
                  )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows the startup/plugin errors on the device, so a failure can be
  /// reported without needing a computer attached.
  void _showLog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(s('Startup log', 'سجل بدء التشغيل'),
            style: TextStyle(color: kGreen, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              bootLog.isEmpty
                  ? s('Everything started cleanly.', 'كل شيء بدأ بدون أخطاء.')
                  : bootLog.join('\n\n'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ),
        actions: [
          if (bootLog.isNotEmpty)
            TextButton(
              onPressed: () {
                bootLog.clear();
                Navigator.of(ctx).pop();
                setState(() {});
              },
              child: Text(s('Clear', 'مسح')),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s('Close', 'إغلاق')),
          ),
        ],
      ),
    );
  }
}
