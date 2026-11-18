import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import '../core/theme.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_state.dart';
import '../data/database.dart';
import '../data/models.dart';

/// يكتب لقطة صغيرة عن مهام اليوم والميمو والنتيجة، ويطلب من أندرويد تحديث
/// ودجت الشاشة الرئيسية.
///
/// الودجت يقرأ الملف فورًا (بدون مفتاح تشفير)، ويستطيع أيضًا قراءة قاعدة
/// البيانات المشفّرة مباشرة عند الحاجة — انظر WidgetData.kt.
class WidgetBridge {
  WidgetBridge._();

  static const _channel = MethodChannel('com.ajami.sos/widgets');
  static const _fileName = 'sos_widget.json';

  static bool _busy = false;
  static bool _again = false;

  /// يُستدعى بعد أي تغيير في المهام أو الميمو. لا يرمي استثناء أبدًا.
  static Future<void> sync() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _write();
      } while (_again);
      await _refresh();
    } catch (e) {
      logWidget('sync: $e');
    } finally {
      _busy = false;
    }
  }

  /// يطبّق ما فعله المستخدم على الودجت: تعليم مهام + ميمو جديدة.
  /// يُستدعى عند فتح التطبيق وبعد كل أمر من الودجت.
  static Future<int> applyPending() async {
    var applied = 0;
    try {
      final rawToggles = await _channel.invokeMethod<String>('pullToggles');
      if (rawToggles != null && rawToggles.isNotEmpty) {
        final list = jsonDecode(rawToggles);
        if (list is List) {
          for (final item in list) {
            if (item is! Map) continue;
            final id = item['id'];
            final day = item['day'];
            final done = item['done'];
            if (id is! int || day is! String || done is! bool) continue;
            final when = DateTime.tryParse(day);
            if (when == null) continue;
            await Db.instance.setDone(id, when, done);
            applied++;
          }
          await _channel.invokeMethod<void>('clearToggles');
        }
      }
    } catch (e) {
      logWidget('apply: $e');
    }
    if (applied > 0) await sync();
    return applied;
  }

  /// عنوان المهمة للودجت: المعرفّة مسبقاً بلغتين، ومهمة المستخدم كما كُتبت.
  static String _titleFor(Task t, bool ar) => t.seeded ? t.title(ar) : t.singleTitle;

  /// لون رقمي بصيغة #AARRGGBB ليقرأه الودجت مباشرة.
  static String _hexOf(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';

  static Future<void> _write() async {
    try {
      await _writeInner();
    } catch (e) {
      logWidget('write: $e');
    }
  }

  static Future<void> _writeInner() async {
    final dir = await _snapshotDir();
    if (dir == null) return;
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }

    final tasks = await Db.instance.tasks();
    final done = await Db.instance.completionKeys();
    final today = dateOnly(DateTime.now());
    final ar = appState.isArabic;

    final todayList = tasks.where((t) => t.occursOn(today)).toList()
      ..sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        final at = a.remindAt, bt = b.remindAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });

    Map<String, Object?> asJson(Task t, DateTime day) {
      final id = t.id ?? -1;
      final items = t.checklist;
      var complete = 0;
      for (final c in items) {
        if (c.done) complete++;
      }
      // المهام المعرفّة مسبقاً تأتي بلغتين فتُعرض كما هي.
      // مهمة المستخدم مكتوبة بلغة واحدة فتُعرض كما كتبها، مع اتجاه النص.
      final title = t.seeded
          ? (ar
              ? (t.titleAr.isNotEmpty ? t.titleAr : t.titleEn)
              : (t.titleEn.isNotEmpty ? t.titleEn : t.titleAr))
          : t.singleTitle;
      return {
        'id': id,
        'title': title,
        'subtitle': items.isEmpty ? '' : '$complete/${items.length}',
        'done': done.contains(doneKey(id, day)),
        'priority': t.priority,
        'private': t.isPrivate,
        'time': t.remindAt == null
            ? ''
            : '${t.remindAt!.hour.toString().padLeft(2, '0')}:'
                '${t.remindAt!.minute.toString().padLeft(2, '0')}',
        'day': dayKey(day),
      };
    }

    // مهام الأيام السابقة (غير المتكررة) التي لم تُنجز.
    final overdue = <Task>[];
    for (final t in tasks) {
      if (t.recurrence != 'none') continue;
      final d = dateOnly(t.date);
      if (!d.isBefore(today)) continue;
      final id = t.id;
      if (id == null) continue;
      if (done.contains(doneKey(id, d))) continue;
      overdue.add(t);
    }
    overdue.sort((a, b) => b.priority.compareTo(a.priority));

    int scheduledOn(DateTime day) =>
        tasks.where((t) => t.occursOn(day)).length;
    int doneOn(DateTime day) {
      var n = 0;
      for (final t in tasks) {
        final id = t.id;
        if (id == null || !t.occursOn(day)) continue;
        if (done.contains(doneKey(id, day))) n++;
      }
      return n;
    }

    final yesterday = DateTime(today.year, today.month, today.day - 1);
    var scheduled7 = 0;
    var done7 = 0;
    for (var i = 0; i < 7; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      scheduled7 += scheduledOn(d);
      done7 += doneOn(d);
    }

    // كل الميمو (وليس ميمو اليوم فقط) حتى تظهر في ودجت الميمو دائماً.
    final notes = await Db.instance.allNotes();

    // المهام القادمة (خطة D1–D20 وغيرها) حتى تظهر قبل يومها.
    final upcoming = <Task>[];
    for (var i = 1; i <= 21; i++) {
      final d = DateTime(today.year, today.month, today.day + i);
      for (final t in tasks) {
        if (t.occursOn(d) && !todayList.contains(t)) upcoming.add(t);
      }
    }

    // تقويم الودجت: تفاصيل كل يوم لخمسة أشهر (شهر سابق ← ٣ أشهر قادمة)
    final noteDays = <String>{for (final n in notes) dayKey(n.day)};
    final days = <String, Object?>{};
    final firstOfMonth = DateTime(today.year, today.month, 1);
    for (var i = -31; i < 130; i++) {
      final d = DateTime(firstOfMonth.year, firstOfMonth.month, firstOfMonth.day + i);
      final key = dayKey(d);
      final dayTasks = <Task>[];
      for (final t in tasks) {
        if (t.occursOn(d)) dayTasks.add(t);
      }
      final hasNote = noteDays.contains(key);
      if (dayTasks.isEmpty && !hasNote) continue;
      var dDone = 0;
      for (final t in dayTasks) {
        final id = t.id;
        if (id != null && done.contains(doneKey(id, d))) dDone++;
      }
      days[key] = {
        'n': dayTasks.length,
        'd': dDone,
        'm': hasNote ? 1 : 0,
        't': [
          for (final t in dayTasks.take(3)) _titleFor(t, ar),
        ],
        'done': [
          for (final t in dayTasks.take(3))
            t.id != null && done.contains(doneKey(t.id!, d)),
        ],
        // لون نقطة كل مهمة = لون فئتها في التطبيق.
        'c': [
          for (final t in dayTasks.take(3)) _hexOf(catColor(t.category)),
        ],
      };
    }

    final data = <String, Object?>{
      'generatedAt': DateTime.now().millisecondsSinceEpoch,
      'today': [for (final t in todayList) asJson(t, today)],
      'overdue': [
        for (final t in overdue.take(5))
          if (t.id != null) asJson(t, dateOnly(t.date)),
      ],
      'scheduledToday': scheduledOn(today),
      'doneToday': doneOn(today),
      'scheduledYesterday': scheduledOn(yesterday),
      'doneYesterday': doneOn(yesterday),
      'scheduled7': scheduled7,
      'done7': done7,
      // ملاحظات غنية (عنوان + مقتطف) لودجت الملاحظات
      'notes': [
        for (final n in notes.take(60))
          {
            'id': n.id,
            'title': n.displayTitle,
            'preview': n.text.replaceAll('\n', ' '),
            'day': dayKey(n.day),
            'group': n.group,
            'color': n.colorHex,
            'pinned': n.pinned,
            'spans': n.spans.length,
            // التاريخ معلومة على السطر، والملاحظات كلها مجموعة معاً.
            'remind': n.remindAt?.toIso8601String(),
          },
      ],
      // المهام المجدولة القادمة (تُعرض في ودجت المهام تحت مهام اليوم)
      'upcoming': [
        for (final t in upcoming.take(6))
          if (t.id != null)
            {
              ...asJson(t, dateOnly(t.date)),
              'isMission': t.isMission,
            },
      ],
      // بيانات تقويم الودجت
      'days': days,
      'month': '${today.year}-${today.month.toString().padLeft(2, '0')}',
      // إعدادات الودجت القادمة من التطبيق
      'settings': {
        'textScale': appState.widgetTextScale,
        'opacity': appState.widgetOpacity,
        'arabic': appState.isArabic,
        'lightMode': appState.lightMode,
      },
    };

    // نكتب إلى ملف مؤقت ثم نستبدل — كتابة نصفية كانت تترك JSON تالفاً،
    // وحينها يفشل parseSnapshot وترجع لقطة فارغة، فتظهر الودجت فارغة.
    final file = File('${dir.path}/$_fileName');
    final tmp = File('${dir.path}/$_fileName.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    try {
      await tmp.rename(file.path);
    } catch (_) {
      // بعض الأنظمة لا تسمح بالاستبدال الذرّي؛ نكتب مباشرة كخطة بديلة.
      await file.writeAsString(jsonEncode(data), flush: true);
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  /// نفس المجلد الذي يقرأه WidgetData.kt:
  /// getExternalFilesDir(null) أولًا ثم مجلد التطبيق الداخلي.
  static Future<Directory?> _snapshotDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    } catch (_) {}
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  /// يرسل إعدادات الودجت (حجم الخط/الشفافية) فوراً دون انتظار إعادة الكتابة.
  static Future<void> pushSettings() async {
    try {
      await _channel.invokeMethod<void>('applySettings', {
        'textScale': appState.widgetTextScale,
        'opacity': appState.widgetOpacity,
        'arabic': appState.isArabic,
        'lightMode': appState.lightMode,
      });
    } catch (e) {
      logWidget('settings: $e');
    }
    await sync();
  }

  static Future<void> _refresh() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // ليس أندرويد، أو الودجت غير مثبّت: لا مشكلة.
    } catch (e) {
      logWidget('refresh: $e');
    }
  }

  /// يسحب أمراً كان بانتظار فتح التطبيق (نقرة على ودجت قبل الإقلاع).
  /// يرجع null إذا لا يوجد أمر معلّق.
  static Future<String?> consumePending() async {
    try {
      final raw = await _channel.invokeMethod<String>('consumeAction');
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } catch (e) {
      logWidget('consume: $e');
      return null;
    }
  }

  /// آخر أخطاء الودجت كما سجّلتها الطبقة الأصلية.
  static Future<String> errors() async {
    try {
      return await _channel.invokeMethod<String>('widgetErrors') ?? '';
    } catch (e) {
      logWidget('errors: $e');
      return '';
    }
  }

  static Future<void> clearErrors() async {
    try {
      await _channel.invokeMethod<void>('clearWidgetErrors');
    } catch (e) {
      logWidget('clearErrors: $e');
    }
  }

  /// ينفّذ أمراً بصيغة "action|taskId|day" — يُستخدم عند الإقلاع والاستئناف.
  static Future<void> runAction(
    String raw, {
    required Future<void> Function() onNewTask,
    required Future<void> Function(int taskId, String day) onOpenTask,
    required Future<void> Function(String day) onOpenDay,
    Future<void> Function()? onSettings,
    Future<void> Function(int noteId, String day)? onOpenNote,
    Future<void> Function()? onOpenNotes,
  }) async {
    final parts = raw.split('|');
    final action = parts.isNotEmpty ? parts[0] : raw;
    final taskId = parts.length > 1 ? (int.tryParse(parts[1]) ?? -1) : -1;
    final day = parts.length > 2 ? parts[2] : '';
    switch (action) {
      case 'new_task':
        await onNewTask();
      case 'open_task':
        if (taskId >= 0) await onOpenTask(taskId, day);
      case 'open_day':
        if (day.isNotEmpty) await onOpenDay(day);
      case 'open_note':
        if (onOpenNote != null && taskId >= 0) await onOpenNote(taskId, day);
        else if (onOpenNotes != null) await onOpenNotes();
      case 'open_notes':
        if (onOpenNotes != null) await onOpenNotes();
      case 'widget_settings':
        if (onSettings != null) await onSettings();
    }
  }

  /// يستمع لأوامر الودجت: فتح نموذج مهمة جديدة، أو فتح يوم/مهمة/ملاحظة.
  static void listen({
    required Future<void> Function() onNewTask,
    Future<void> Function()? onSettings,
    Future<void> Function(int taskId, String day)? onOpenTask,
    Future<void> Function(String day)? onOpenDay,
    Future<void> Function(int noteId, String day)? onOpenNote,
    Future<void> Function()? onOpenNotes,
  }) {
    _channel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'openAction') {
          final raw = call.arguments as String? ?? '';
          // Payload shape: "action|taskId|day" (taskId/day may be empty).
          final parts = raw.split('|');
          final action = parts.isNotEmpty ? parts[0] : raw;
          final taskId = parts.length > 1 ? (int.tryParse(parts[1]) ?? -1) : -1;
          final day = parts.length > 2 ? parts[2] : '';

          if (action == 'new_task') await onNewTask();
          if (action == 'widget_settings' && onSettings != null) {
            await onSettings();
          }
          if (action == 'open_task' && onOpenTask != null && taskId >= 0) {
            await onOpenTask(taskId, day);
          }
          if (action == 'open_day' && onOpenDay != null && day.isNotEmpty) {
            await onOpenDay(day);
          }
          if (action == 'open_note' && onOpenNote != null && taskId >= 0) {
            await onOpenNote(taskId, day);
          } else if (action == 'open_note' && onOpenNotes != null) {
            await onOpenNotes();
          }
          if (action == 'open_notes' && onOpenNotes != null) {
            await onOpenNotes();
          }
        }
      } catch (e) {
        logWidget('action: $e');
      }
    });
  }
}

/// أخطاء الودجت تُسجّل ولا تُعطّل التطبيق أبدًا.
void logWidget(String message) {
  if (kDebugMode) debugPrint('widgets: $message');
}
