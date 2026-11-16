
import 'dart:convert';

const kCategories = ['general', 'security', 'logistics', 'child', 'admin'];
const kRepeats = ['none', 'daily', 'weekly', 'monthly'];

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// قراءة نص محفوظ في قاعدة البيانات بلا انفجار عند القيمة الفارغة.
/// (كل الحقول النصية في الجداول قابلة لأن تكون NULL.)
String _text(Object? v) => (v as String?) ?? '';

/// أرقام SQLite قد تُعاد كـ int أو num حسب المنصّة.
int _int(Object? v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : fallback);

DateTime _date(Object? v) => DateTime.parse(_text(v));

/// مفتاح إنجاز مهمة في يوم محدد (كل يوم في المهمة المتكررة له حالة مستقلة)
String doneKey(int taskId, DateTime day) => '$taskId|${dayKey(day)}';

class CheckItem {
  final String text;
  final bool done;
  const CheckItem(this.text, {this.done = false});

  Map<String, dynamic> toJson() => {'t': text, 'd': done};
}

List<CheckItem> _parseChecklist(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => CheckItem(
              (e['t'] as String?) ?? '',
              done: e['d'] == true,
            ))
        .toList();
  } catch (_) {
    // Corrupt JSON must not crash the list screen.
    return const [];
  }
}

class Task {
  final int? id;
  final String titleEn;
  final String titleAr;
  final String detailsEn;
  final String detailsAr;
  final DateTime date;      // اليوم فقط
  final DateTime? remindAt; // الساعة والدقيقة تُستخدم للجرس
  final String category;    // general | security | logistics | child | admin
  final int priority;       // 0 منخفضة، 1 عادية، 2 عالية
  final bool isPrivate;     // لا تُرسل للتقاويم السحابية
  final String recurrence;  // none | daily | weekly | monthly
  final DateTime? until;    // آخر يوم للتكرار (شامل) — null = بلا نهاية
  final List<CheckItem> checklist;
  final bool isMission;     // جزء من خطة D1–D20
  final String? googleId;
  final String? msId;
  final DateTime updatedAt;

  const Task({
    this.id,
    required this.titleEn,
    this.titleAr = '',
    this.detailsEn = '',
    this.detailsAr = '',
    required this.date,
    this.remindAt,
    this.category = 'general',
    this.priority = 1,
    this.isPrivate = false,
    this.recurrence = 'none',
    this.until,
    this.checklist = const [],
    this.isMission = false,
    this.googleId,
    this.msId,
    required this.updatedAt,
  });

  String title(bool ar) => ar && titleAr.isNotEmpty ? titleAr : titleEn;
  String details(bool ar) => ar && detailsAr.isNotEmpty ? detailsAr : detailsEn;

  /// وقت الجرس في يوم معين
  DateTime? bellOn(DateTime day) => remindAt == null
      ? null
      : DateTime(day.year, day.month, day.day, remindAt!.hour, remindAt!.minute);

  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    final s = dateOnly(date);
    if (d.isBefore(s)) return false;
    // نافذة التكرار: الخطة تنتهي في [until] ولا تتجاوزها.
    if (until != null && d.isAfter(dateOnly(until!))) return false;
    return switch (recurrence) {
      'daily' => true,
      'weekly' => d.weekday == s.weekday,
      'monthly' => d.day == s.day,
      _ => sameDay(d, s),
    };
  }

  Map<String, Object?> toMap() => {
        'title_en': titleEn,
        'title_ar': titleAr,
        'details_en': detailsEn,
        'details_ar': detailsAr,
        'date': dayKey(date),
        'remind_at': remindAt?.toIso8601String(),
        'category': category,
        'priority': priority,
        'is_private': isPrivate ? 1 : 0,
        'recurrence': recurrence,
        'until': until == null ? null : dayKey(until!),
        'checklist': jsonEncode(checklist.map((c) => c.toJson()).toList()),
        'is_mission': isMission ? 1 : 0,
        'google_id': googleId,
        'ms_id': msId,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Task.fromMap(Map<String, Object?> m) => Task(
        id: _int(m['id']),
        titleEn: _text(m['title_en']),
        titleAr: _text(m['title_ar']),
        detailsEn: _text(m['details_en']),
        detailsAr: _text(m['details_ar']),
        date: _date(m['date']),
        remindAt: m['remind_at'] == null ? null : _date(m['remind_at']),
        category: m['category'] == null ? 'general' : _text(m['category']),
        priority: _int(m['priority'], 1),
        isPrivate: _int(m['is_private']) == 1,
        recurrence: m['recurrence'] == null ? 'none' : _text(m['recurrence']),
        until: m['until'] == null ? null : _date(m['until']),
        checklist: _parseChecklist(m['checklist'] as String?),
        isMission: _int(m['is_mission']) == 1,
        googleId: m['google_id'] as String?,
        msId: m['ms_id'] as String?,
        updatedAt: m['updated_at'] == null
            ? DateTime.now()
            : _date(m['updated_at']),
      );
}

/// تنسيق نصي محفوظ (غامق / مائل / تسطير / عنوان / قائمة) على مقطع معيّن.
class NoteSpan {
  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// 0 = نص عادي، 1 = عنوان، 2 = عنوان فرعي، 3 = اقتباس
  final int heading;
  final bool bullet;

  /// حجم إضافي بالبكسل (0 = افتراضي)
  final double sizeDelta;

  const NoteSpan({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.heading = 0,
    this.bullet = false,
    this.sizeDelta = 0,
  });

  bool get isDefault =>
      !bold &&
      !italic &&
      !underline &&
      !strike &&
      heading == 0 &&
      !bullet &&
      sizeDelta == 0;

  Map<String, Object?> toJson() => {
        's': start,
        'e': end,
        if (bold) 'b': 1,
        if (italic) 'i': 1,
        if (underline) 'u': 1,
        if (strike) 'k': 1,
        if (heading != 0) 'h': heading,
        if (bullet) 'l': 1,
        if (sizeDelta != 0) 'z': sizeDelta,
      };

  factory NoteSpan.fromJson(Map<String, Object?> m) => NoteSpan(
        start: _int(m['s']),
        end: _int(m['e']),
        bold: _int(m['b']) == 1,
        italic: _int(m['i']) == 1,
        underline: _int(m['u']) == 1,
        strike: _int(m['k']) == 1,
        heading: _int(m['h']),
        bullet: _int(m['l']) == 1,
        sizeDelta: (m['z'] as num?)?.toDouble() ?? 0,
      );
}

/// ملاحظة نصية حرّة (مثل ملف Word مصغّر): عنوان + نص + تنسيقات + لون.
class Note {
  final int id;
  final DateTime day;
  final String text;
  final String title;
  final String? colorHex;
  final List<NoteSpan> spans;
  final bool pinned;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.day,
    required this.text,
    this.title = '',
    this.colorHex,
    this.spans = const [],
    this.pinned = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// أول سطر كعنوان مقترح.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final first = text.split('\n').first.trim();
    return first.isEmpty ? text.trim() : first;
  }

  int get wordCount => text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;

  factory Note.fromMap(Map<String, Object?> m) => Note(
        id: _int(m['id']),
        day: _date(m['day']),
        text: _text(m['text']),
        title: _text(m['title']),
        colorHex: m['color'] as String?,
        spans: _parseSpans(m['spans'] as String?),
        pinned: _int(m['pinned']) == 1,
        updatedAt: m['updated_at'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : _date(m['updated_at']),
      );

  Map<String, Object?> toMap() => {
        'day': dayKey(day),
        'text': text,
        'title': title,
        'color': colorHex,
        'spans': jsonEncode(spans.map((s) => s.toJson()).toList()),
        'pinned': pinned ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
      };

  Note copyWith({
    String? text,
    String? title,
    String? colorHex,
    List<NoteSpan>? spans,
    bool? pinned,
    DateTime? day,
  }) =>
      Note(
        id: id,
        day: day ?? this.day,
        text: text ?? this.text,
        title: title ?? this.title,
        colorHex: colorHex ?? this.colorHex,
        spans: spans ?? this.spans,
        pinned: pinned ?? this.pinned,
        updatedAt: DateTime.now(),
      );
}

List<NoteSpan> _parseSpans(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => NoteSpan.fromJson(m.cast<String, Object?>()))
        .toList();
  } catch (_) {
    return const [];
  }
}

