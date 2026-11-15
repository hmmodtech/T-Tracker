import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/models.dart';

/// تقويم شهري خفيف شبيه بتقويم Google / Microsoft:
/// شبكة ٧ أعمدة، نقاط ملوّنة لكل مهمة، ونقطة صغيرة للميمو.
///
/// لا يستخدم أي حزمة خارجية ولا أي رسّام مخصّص ثقيل — يُبنى من Row/Column
/// فقط، لذا يبقى سريعاً على الأجهزة الضعيفة.
class MonthCalendar extends StatefulWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final List<Task> tasks; // كل المهام (يُفلتر منها لكل يوم)
  final Set<String> doneKeys; // مفاتيح الإنجاز taskId|yyyy-MM-dd
  final Map<String, List<String>> memosByDay; // yyyy-MM-dd → نصوص الميمو
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChanged;

  const MonthCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.tasks,
    required this.doneKeys,
    this.memosByDay = const {},
    required this.onSelect,
    required this.onMonthChanged,
  });

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.focusedDay.year, widget.focusedDay.month);
  }

  @override
  void didUpdateWidget(covariant MonthCalendar old) {
    super.didUpdateWidget(old);
    if (widget.focusedDay.year != old.focusedDay.year ||
        widget.focusedDay.month != old.focusedDay.month) {
      _month = DateTime(widget.focusedDay.year, widget.focusedDay.month);
    }
  }

  void _shift(int months) {
    final m = DateTime(_month.year, _month.month + months);
    setState(() => _month = m);
    widget.onMonthChanged(m);
  }

  /// خريطة يوم → مهامه، تُبنى مرة واحدة لكل بناء بدل مسح كل المهام
  /// ٤٢ مرة (مرة لكل خلية في الشبكة).
  Map<String, List<Task>>? _byDayCache;
  int? _byDayTasksLen;
  int? _byDayMemoLen;
  DateTime? _byDayMonth;
  Set<String> _memoDays = const {};

  Map<String, List<Task>> _byDay() {
    if (_byDayCache != null &&
        _byDayTasksLen == widget.tasks.length &&
        _byDayMemoLen == widget.memosByDay.length &&
        _byDayMonth == _month) {
      return _byDayCache!;
    }
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final map = <String, List<Task>>{};
    for (var i = 1; i <= daysInMonth; i++) {
      final d = DateTime(_month.year, _month.month, i);
      final key = dayKey(d);
      for (final t in widget.tasks) {
        if (t.occursOn(d)) (map[key] ??= <Task>[]).add(t);
      }
    }
    _byDayCache = map;
    _byDayTasksLen = widget.tasks.length;
    _byDayMemoLen = widget.memosByDay.length;
    _byDayMonth = _month;
    // Also refresh the per-day "memo exists" check while we are here.
    _memoDays = widget.memosByDay.keys.toSet();
    return map;
  }

  @override
  Widget build(BuildContext context) {
    // Warms the day→tasks cache and the memo set before the grid paints.
    _byDay();
    final ar = appState.isArabic;
    final locale = ar ? 'ar' : 'en_US';

    // الأسبوع يبدأ الأحد (المعتاد في المنطقة).
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday % 7; // Sunday = 0
    final cells = ((leading + daysInMonth) / 7).ceil() * 7;

    // أسماء أيام الأسبوع
    final weekdayFmt = DateFormat.E(locale);
    final weekNames = [
      for (var i = 0; i < 7; i++) weekdayFmt.format(DateTime(2024, 1, 7 + i)),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(locale),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final w in weekNames)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    maxLines: 1,
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < cells ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _cell(row * 7 + col - leading, daysInMonth)),
            ],
          ),
      ],
    );
  }

  Widget _header(String locale) {
    final monthName = DateFormat.yMMMM(locale).format(_month);
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: appState.t('Previous month', 'الشهر السابق'),
          icon: Icon(Icons.chevron_left, color: kGreen, size: 20),
          onPressed: () => _shift(-1),
        ),
        Expanded(
          child: Text(
            monthName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kGreen,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.6,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: appState.t('Next month', 'الشهر التالي'),
          icon: Icon(Icons.chevron_right, color: kGreen, size: 20),
          onPressed: () => _shift(1),
        ),
      ],
    );
  }

  Widget _cell(int index, int daysInMonth) {
    // خلايا خارج الشهر
    if (index < 0 || index >= daysInMonth) {
      return const SizedBox(height: 44);
    }
    final day = DateTime(_month.year, _month.month, index + 1);
    final selected = sameDay(day, widget.selectedDay);
    final isToday = sameDay(day, DateTime.now());
    final key = dayKey(day);
    final tasks = _byDay()[key] ?? const <Task>[];
    final hasMemo = _memoDays.contains(key);

    // حتى ٤ نقاط: ملوّنة بحسب الفئة، ومملوءة إذا أُنجزت.
    final dots = tasks.take(4).toList();

    Color? ring;
    if (selected) {
      ring = kGreen;
    } else if (isToday) {
      ring = kAqua;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: '$key — ${tasks.length}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onSelect(day),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              width: 34,
              height: 38,
              decoration: BoxDecoration(
                color: selected ? kGreen.withAlpha(isLight ? 45 : 38) : null,
                borderRadius: BorderRadius.circular(10),
                border: ring == null ? null : Border.all(color: ring, width: 1.2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected || isToday ? FontWeight.w800 : FontWeight.w500,
                      color: selected
                          ? kGreen
                          : isToday
                              ? kAqua
                              : kText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 5,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final t in dots)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 0.7),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              // filled = done, hollow ring = open
                              color: widget.doneKeys
                                      .contains(doneKey(t.id ?? -1, day))
                                  ? catColor(t.category)
                                  : catColor(t.category).withAlpha(90),
                              border: widget.doneKeys
                                      .contains(doneKey(t.id ?? -1, day))
                                  ? null
                                  : Border.all(
                                      color: catColor(t.category),
                                      width: 0.8,
                                    ),
                            ),
                          ),
                        // نقطة الميمو: رمادية صغيرة
                        if (hasMemo)
                          Container(
                            width: 3,
                            height: 3,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
