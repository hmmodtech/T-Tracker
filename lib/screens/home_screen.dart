

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/app_state.dart';
import '../core/backdrop.dart';
import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../services/notifications.dart';
import '../services/widget_bridge.dart';
import 'notes_screen.dart';
import 'note_editor_screen.dart';
import 'search_screen.dart';
import 'stats_screen.dart';
import '../widgets/month_calendar.dart';
import 'settings_screen.dart';
import 'task_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  DateTime _focused = DateTime.now();
  DateTime _selected = dateOnly(DateTime.now());
  List<Task> _tasks = [];
  Set<String> _done = {};
  List<Note> _notes = [];

  /// yyyy-MM-dd → نصوص الميمو، لعرض نقطة الميمو في التقويم.
  Map<String, List<String>> _memosByDay = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // A widget tap can arrive before the app finished starting; pick it up
    // once the first frame is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainPending());
    // Widget taps: the + button opens the new-task form, and memo taps pull
    // whatever was typed on the home screen into the database.
    WidgetBridge.listen(
      onNewTask: () async {
        _load();
        if (mounted) await _openForm();
      },
      onMemos: () async {
        await WidgetBridge.applyPending();
        if (mounted) await _load();
      },
      // Tapping a task row opens that task's page.
      onOpenTask: (taskId, day) async {
        await openTaskFromWidget(taskId, day);
      },
      // Tapping a calendar day opens that day's page with its memo.
      onOpenDay: (day) async {
        await openDayFromWidget(day);
      },
      // Long-pressing a widget opens the widget settings.
      onSettings: () async {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        if (mounted) _load();
      },
    );
  }

  /// ينفّذ أي أمر ودجت معلّق (فتح مهمة / فتح يوم / مهمة جديدة).
  Future<void> _drainPending() async {
    final raw = await WidgetBridge.consumePending();
    if (raw == null || !mounted) return;
    await WidgetBridge.runAction(
      raw,
      onNewTask: () async {
        await _load();
        if (mounted) await _openForm();
      },
      onOpenTask: openTaskFromWidget,
      onOpenDay: openDayFromWidget,
      onSettings: () async {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      },
    );
  }

  // The launcher can queue taps while we are in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetBridge.applyPending().then((_) {
        if (mounted) _load();
      });
      _drainPending();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final db = Db.instance;
    final tasks = await db.tasks();
    final done = await db.completionKeys();
    final notes = await db.notesOn(_selected);
    final allNotes = await db.allNotes();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _done = done;
      _notes = notes;
      _memosByDay = <String, List<String>>{};
      for (final n in allNotes) {
        (_memosByDay[dayKey(n.day)] ??= <String>[]).add(n.text);
      }
    });
    // Keep the home-screen widgets in step with every change made here.
    WidgetBridge.sync();
  }

  List<Task> _tasksOn(DateTime d) =>
      _tasks.where((t) => t.occursOn(d)).toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));

  bool _isDone(Task t, DateTime d) => _done.contains(doneKey(t.id!, d));

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _focused = now;
      _selected = dateOnly(now);
    });
    _load();
  }

  Future<void> _toggle(Task t) async {
    final nowDone = !_isDone(t, _selected);
    HapticFeedback.mediumImpact();
    await Db.instance.setDone(t.id!, _selected, nowDone);
    await Bell.schedule(t, t.id!,
        enabled: appState.notificationsOn, done: nowDone);
    await _load();
  }

  Future<void> _toggleCheck(Task t, int i) async {
    HapticFeedback.selectionClick();
    await Db.instance.setChecklistDone(t.id!, i, !t.checklist[i].done);
    await _load();
  }

  Future<void> _delete(Task t) async {
    await Db.instance.deleteTask(t.id!);
    await Bell.cancel(t.id!);
    await _load();
  }

  Future<bool> _confirm(String msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appState.t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(appState.t('Delete', 'حذف'),
                style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _openForm([Task? t]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskFormScreen(task: t, initialDate: _selected),
      ),
    );
    _load();
  }

  Future<void> _search() async {
    final day = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
    if (day != null) {
      setState(() {
        _selected = dateOnly(day);
        _focused = day;
      });
    }
    _load();
  }

  Future<void> _pickYearMonth() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _focused,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _focused = d;
        _selected = dateOnly(d);
      });
      _load();
    }
  }

  /// يفتح محرّر الملاحظات الغني (عنوان، تنسيق، ألوان، نصوص طويلة).
  Future<void> _openNote(Note? note) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: note, day: _selected),
      ),
    );
    if (changed == true) _load();
  }

  /// يستقبل طلب فتح يوم أو مهمة قادماً من الودجت.
  Future<void> openDayFromWidget(String dayKeyValue) async {
    final parts = dayKeyValue.split('-');
    if (parts.length != 3) return;
    final d = DateTime(
      int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts[1]) ?? DateTime.now().month,
      int.tryParse(parts[2]) ?? DateTime.now().day,
    );
    setState(() {
      _selected = dateOnly(d);
      _focused = d;
    });
    await _load();
  }

  Future<void> openTaskFromWidget(int taskId, String day) async {
    if (day.isNotEmpty) await openDayFromWidget(day);
    final all = await Db.instance.tasks();
    final match = all.where((t) => t.id == taskId).toList();
    if (match.isEmpty) return;
    if (!mounted) return;
    await _openForm(match.first);
    await _load();
  }

  // ---------- UI helpers ----------
  Widget _section(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(
          children: [
            Container(width: 3, height: 12, color: kGreen),
            const SizedBox(width: 7),
            SectionLabel(s),
          ],
        ),
      );

  /// '#RRGGBB' → Color
  Color _hex(String hex) {
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16) ?? 0x25F4C8;
    return Color(0xFF000000 | v);
  }

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withAlpha(35),
          border: Border.all(color: c.withAlpha(140)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
      );

  Widget _taskCard(Task t) {
    final ar = appState.isArabic;
    final done = _isDone(t, _selected);
    final color = catColor(t.category);

    final card = AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: done ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
        decoration: glass(border: color.withAlpha(120)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Checkbox(
                value: done,
                activeColor: kGreen,
                checkColor: isLight ? Colors.white : Colors.black,
                onChanged: (_) => _toggle(t),
              ),
              Expanded(
                // Each title flows in its own direction so an English word
                // inside an Arabic sentence is not scrambled.
                child: BidiText(
                  t.title(ar),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (t.isPrivate)
                Icon(Icons.lock_outline, size: 16, color: kAmber),
              if (t.remindAt != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: Row(children: [
                    Icon(Icons.notifications_active, size: 16, color: kGreen),
                    const SizedBox(width: 3),
                    Text(DateFormat.Hm().format(t.remindAt!),
                        style: TextStyle(color: kGreen, fontSize: 12)),
                  ]),
                ),
            ]),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                _chip(catLabel(t.category), color),
                if (t.recurrence != 'none')
                  _chip('↻ ${repeatLabel(t.recurrence)}', kDimGreen),
                if (t.priority == 2)
                  _chip(appState.t('HIGH', 'عالية'), kRed),
              ]),
            ),
            if (t.details(ar).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
                child: BidiText(t.details(ar),
                    style: TextStyle(
                        color: kMuted, fontSize: 12, height: 1.35)),
              ),
            for (var i = 0; i < t.checklist.length; i++)
              InkWell(
                onTap: () => _toggleCheck(t, i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
                  child: Row(children: [
                    Icon(
                      t.checklist[i].done
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: kGreen,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: BidiText(
                        t.checklist[i].text,
                        style: TextStyle(
                          fontSize: 12,
                          decoration: t.checklist[i].done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('t${t.id}-${dayKey(_selected)}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: kRed.withAlpha(90),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) => _confirm(appState.t(
          'Delete this task permanently?', 'حذف هذه المهمة نهائياً؟')),
      onDismissed: (_) => _delete(t),
      child: InkWell(
        onTap: () => _openForm(t),
        borderRadius: BorderRadius.circular(10),
        child: card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final s = appState;
        final ar = s.isArabic;
        final dayTasks = _tasksOn(_selected);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('T-TRACKER'),
            // Kept to three controls so the bar stays calm and light.
            actions: [
              IconButton(
                tooltip: s.t('Light / dark mode', 'الوضع الفاتح / الداكن'),
                icon: Icon(
                  s.lightMode
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  color: kGreen,
                ),
                onPressed: () {
                  s.setLightMode(!s.lightMode);
                  // Widgets are drawn by native code, so tell them to recolour.
                  WidgetBridge.pushSettings();
                },
              ),
              IconButton(icon: const Icon(Icons.search), onPressed: _search),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                color: kSurface,
                onSelected: (v) {
                  if (v == 'result') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StatsScreen()),
                    );
                  } else if (v == 'panic') {
                    s.setPanic(true);
                  } else if (v == 'lang') {
                    s.setArabic(!ar);
                  } else if (v == 'settings') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'result',
                    child: Text(s.t('Results', 'النتائج')),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Text(s.t('Settings', 'الإعدادات')),
                  ),
                  PopupMenuItem(
                    value: 'lang',
                    child: Text(ar ? 'English' : 'العربية'),
                  ),
                  PopupMenuItem(
                    value: 'panic',
                    child: Text(
                      s.t('Panic screen', 'شاشة الطوارئ'),
                      style: TextStyle(color: kRed),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Small round + button instead of the wide extended one.
          floatingActionButton: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: isLight
                  ? [
                      BoxShadow(
                        color: kGreen.withValues(alpha: 0.35),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [
                      BoxShadow(color: Color(0x8825F4C8), blurRadius: 18),
                      BoxShadow(color: Color(0x4438BDF8), blurRadius: 30),
                    ],
            ),
            child: FloatingActionButton(
              mini: true,
              tooltip: s.t('New task', 'مهمة جديدة'),
              backgroundColor: kGreen,
              foregroundColor: isLight ? Colors.white : kBlack,
              elevation: 0,
              onPressed: () => _openForm(),
              child: const Icon(Icons.add, size: 22),
            ),
          ),
          // A CustomScrollView with a builder delegate: header widgets are
          // fixed, and tasks/memos are built lazily as they scroll into view.
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    GlassPanel(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                      child: MonthCalendar(
                        focusedDay: _focused,
                        selectedDay: _selected,
                        tasks: _tasks,
                        doneKeys: _done,
                        memosByDay: _memosByDay,
                        onSelect: (sel) {
                          setState(() {
                            _selected = dateOnly(sel);
                            _focused = sel;
                          });
                          _load();
                        },
                        onMonthChanged: (m) => setState(() => _focused = m),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: Text(
                          DateFormat.yMMMMEEEEd(ar ? 'ar' : 'en_US')
                              .format(_selected)
                              .toUpperCase(),
                          style: TextStyle(
                              color: kGreen,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1),
                        ),
                      ),
                      TextButton(
                        onPressed: _goToday,
                        child: Text(s.t('TODAY', 'اليوم')),
                      ),
                    ]),
                    _section(s.t('TASKS', 'المهام')),
                  ]),
                ),
              ),

              // ---- Tasks (lazy) ----
              if (dayTasks.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      s.t('No tasks for this day', 'لا توجد مهام لهذا اليوم'),
                      style: TextStyle(color: kMuted),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _taskCard(dayTasks[i]),
                      childCount: dayTasks.length,
                    ),
                  ),
                ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    _section(s.t('MEMOS', 'المذكرات')),
                  ]),
                ),
              ),

              // ---- Notes (rich, lazy) ----
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final n = _notes[i];
                      return GestureDetector(
                        onTap: () => _openNote(n),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: glass(
                            border: n.colorHex == null
                                ? kDimGreen.withAlpha(90)
                                : _hex(n.colorHex!).withAlpha(130),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: n.pinned
                                ? Icon(Icons.push_pin, size: 15, color: kAmber)
                                : null,
                            title: BidiText(
                              n.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: n.text.trim().isEmpty
                                ? null
                                : BidiText(
                                    n.text.replaceAll('\n', ' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: kMuted, fontSize: 11),
                                  ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                await Db.instance.deleteNote(n.id);
                                WidgetBridge.sync();
                                _load();
                              },
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _notes.length,
                  ),
                ),
              ),

              // ---- Add a note (rich editor) ----
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 100),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kGreen,
                            side: BorderSide(color: kPetrol),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.note_add_outlined, size: 18),
                          label: Text(
                            s.t('New note', 'ملاحظة جديدة'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: () => _openNote(null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: s.t('All notes', 'كل الملاحظات'),
                        icon: const Icon(Icons.list_alt),
                        color: kGreen,
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotesScreen(day: _selected),
                            ),
                          );
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

