import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/app_state.dart';
import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../services/notifications.dart';

/// نموذج مهمة واحد، بأسلوب Microsoft To-Do:
///
///  • حقل نص واحد فقط — عربي أو إنجليزي أو مختلط، ولا حقول لغة منفصلة.
///  • قائمة تحقّق داخل نفس النموذج: بند جديد يُكتب ويُضاف بـ Enter،
///    ويُعلَّم «تم» بلمسة، ويُحذف بالسحب.
///  • التاريخ كمعلومة، والمنبّه اختياري.
///  • مجلد (Group) حرّ: يُختار من الموجود أو يُكتب اسم جديد في نفس اللحظة.
class TaskFormScreen extends StatefulWidget {
  final Task? task;
  final DateTime initialDate;

  /// المجلد المقترح عند الإنشاء من داخل مجلد معيّن.
  final String? group;

  const TaskFormScreen({
    super.key,
    this.task,
    required this.initialDate,
    this.group,
  });

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _details;
  final TextEditingController _newItem = TextEditingController();
  final FocusNode _itemFocus = FocusNode();

  late List<CheckItem> _items;
  late DateTime _date;
  DateTime? _remindAt;
  late String _category;
  late int _priority;
  late bool _isPrivate;
  late String _recurrence;
  late String _group;

  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;
  bool _listening = false;

  String s(String en, String ar) => appState.t(en, ar);

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    // حقل واحد: نقرأ من أي عمود كان حتى لا يضيع نص قديم.
    _title = TextEditingController(text: t?.singleTitle ?? '');
    _details = TextEditingController(text: t?.details(appState.isArabic) ?? '');
    _items = List<CheckItem>.from(t?.checklist ?? const []);
    _date = dateOnly(t?.date ?? widget.initialDate);
    _remindAt = t?.remindAt;
    _category = t?.category ?? 'general';
    _priority = t?.priority ?? 1;
    _isPrivate = t?.isPrivate ?? false;
    _recurrence = t?.recurrence ?? 'none';
    _group = t?.group ?? widget.group ?? '';
    _stt.initialize().then((ok) {
      if (mounted) setState(() => _sttReady = ok);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _newItem.dispose();
    _itemFocus.dispose();
    _stt.stop();
    super.dispose();
  }

  // ── checklist ──────────────────────────────────────────────────────────────

  void _addItem([String? raw]) {
    final text = (raw ?? _newItem.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(CheckItem(text));
      _newItem.clear();
    });
    // نُبقي لوحة المفاتيح مفتوحة للبند التالي.
    _itemFocus.requestFocus();
  }

  void _toggleItem(int i) => setState(() {
        _items[i] = CheckItem(_items[i].text, done: !_items[i].done);
      });

  void _removeItem(int i) => setState(() => _items.removeAt(i));

  Future<void> _toggleVoice() async {
    if (!_sttReady) return;
    if (_stt.isListening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      localeId: appState.isArabic ? 'ar_SA' : 'en_US',
      onResult: (r) {
        _title.text = r.recognizedWords;
        _title.selection = TextSelection.collapsed(offset: _title.text.length);
      },
    );
  }

  // ── pickers ────────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = dateOnly(d));
  }

  Future<void> _pickBellTime() async {
    final base = _remindAt ?? DateTime(_date.year, _date.month, _date.day, 9);
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (tm == null) return;
    var when = DateTime(_date.year, _date.month, _date.day, tm.hour, tm.minute);
    // منبّه في الماضي بلا فائدة — ننقله للغد ونحرّك التاريخ معه.
    if (when.isBefore(DateTime.now())) {
      when = when.add(const Duration(days: 1));
    }
    setState(() {
      _remindAt = when;
      _date = dateOnly(when);
    });
  }

  Future<void> _pickGroup() async {
    final groups = await Db.instance.taskGroups();
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: _group);
        return AlertDialog(
          backgroundColor: kSurface,
          title: Text(s('List (group)', 'المجلد')),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BidiField(
                  controller: controller,
                  labelText: s('New list name', 'اسم مجلد جديد'),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.inbox_outlined, color: kGreen),
                        title: Text(s('No list', 'بدون مجلد')),
                        onTap: () => Navigator.pop(ctx, ''),
                      ),
                      for (final g in groups)
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.folder_outlined, color: kAqua),
                          title: Text(g),
                          onTap: () => Navigator.pop(ctx, g),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(s('Use', 'استخدام')),
            ),
          ],
        );
      },
    );
    if (picked == null) return;
    setState(() => _group = picked);
  }

  // ── save / delete ──────────────────────────────────────────────────────────

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty && _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s('Write a task or add a step', 'اكتب مهمة أو أضف بنداً')),
        ),
      );
      return;
    }
    final old = widget.task;

    // المهمة الجديدة تُخزَّن في عمود واحد فقط، كما كتبها المستخدم.
    // المهام المعرفّة مسبقاً (الخطة) تبقى باللغتين لأنها ليست إدخال المستخدم.
    final seeded = old?.seeded ?? false;
    final titleEn = seeded ? old!.titleEn : title;
    final titleAr = seeded ? old!.titleAr : '';
    final details = _details.text.trim();

    final task = Task(
      id: old?.id,
      titleEn: titleEn,
      titleAr: titleAr,
      detailsEn: seeded ? old!.detailsEn : details,
      detailsAr: seeded ? old!.detailsAr : '',
      date: _date,
      remindAt: _remindAt,
      category: _category,
      priority: _priority,
      isPrivate: _isPrivate,
      recurrence: _recurrence,
      checklist: _items,
      isMission: seeded,
      group: _group,
      googleId: old?.googleId,
      msId: old?.msId,
      updatedAt: DateTime.now(),
    );
    final id = await Db.instance.saveTask(task);
    await Bell.schedule(task, id, enabled: appState.notificationsOn);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final old = widget.task;
    if (old?.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(s('Delete task?', 'تحذف المهمة؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Bell.cancel(old!.id!);
    await Db.instance.deleteTask(old.id!);
    if (mounted) Navigator.pop(context, true);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNew = widget.task == null;
    final done = _items.where((i) => i.done).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(isNew ? s('New task', 'مهمة جديدة') : s('Task', 'المهمة')),
        actions: [
          if (!isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: s('Delete', 'حذف'),
              onPressed: _delete,
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: s('Save', 'حفظ'),
            onPressed: _save,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            // ── الحقل الوحيد ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: BidiField(
                    controller: _title,
                    labelText: s('What needs doing?', 'شو المطلوب؟'),
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _itemFocus.requestFocus(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    color: _listening ? kRed : kGreen,
                  ),
                  tooltip: s('Voice input', 'إدخال صوتي'),
                  onPressed: _sttReady ? _toggleVoice : null,
                ),
              ],
            ),
            const SizedBox(height: 6),
            BidiField(
              controller: _details,
              labelText: s('Notes (optional)', 'ملاحظات (اختياري)'),
              maxLines: 2,
            ),

            // ── البنود ──
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.checklist, size: 18, color: kGreen),
                const SizedBox(width: 6),
                Text(
                  s('Steps', 'البنود'),
                  style: TextStyle(
                    color: kMutedGreen,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                if (_items.isNotEmpty)
                  Text('$done/${_items.length}',
                      style: TextStyle(color: kMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _items.length; i++)
              Dismissible(
                key: ValueKey('item-$i-${_items[i].text}'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => _removeItem(i),
                background: Container(
                  alignment: AlignmentDirectional.centerEnd,
                  padding: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: kRed.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.delete_outline, color: kRed, size: 18),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _toggleItem(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          _items[i].done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: _items[i].done ? kGreen : kMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BidiText(
                            _items[i].text,
                            style: TextStyle(
                              fontSize: 14,
                              color: _items[i].done ? kMuted : kText,
                              decoration: _items[i].done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // بند جديد: سطر واحد، و Enter يضيف ويجهّز التالي
            Row(
              children: [
                Icon(Icons.add, size: 20, color: kGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _newItem,
                    focusNode: _itemFocus,
                    style: TextStyle(color: kText, fontSize: 14),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _addItem,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: s('Add a step…', 'أضف بنداً…'),
                      hintStyle: TextStyle(color: kMuted),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.keyboard_return, size: 18, color: kAqua),
                  tooltip: s('Add', 'إضافة'),
                  onPressed: _addItem,
                ),
              ],
            ),

            // ── الجدولة ──
            const SizedBox(height: 14),
            _tile(
              icon: Icons.folder_outlined,
              title: s('List', 'المجلد'),
              value: _group.isEmpty ? s('No list', 'بدون مجلد') : _group,
              onTap: _pickGroup,
            ),
            _tile(
              icon: Icons.event,
              title: s('Date', 'التاريخ'),
              value: dayKey(_date),
              onTap: _pickDate,
            ),
            _tile(
              icon: Icons.notifications_active,
              title: s('Reminder', 'المنبّه'),
              value: _remindAt == null
                  ? s('Off', 'مغلق')
                  : '${dayKey(_remindAt!)}  '
                      '${_remindAt!.hour.toString().padLeft(2, '0')}:'
                      '${_remindAt!.minute.toString().padLeft(2, '0')}',
              onTap: _pickBellTime,
              trailing: _remindAt == null
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 18, color: kRed),
                      tooltip: s('Remove reminder', 'إزالة المنبّه'),
                      onPressed: () => setState(() => _remindAt = null),
                    ),
            ),

            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [0, 1, 2])
                  ChoiceChip(
                    label: Text(
                      p == 0
                          ? s('Low', 'منخفضة')
                          : p == 2
                              ? s('High', 'عالية')
                              : s('Normal', 'عادية'),
                    ),
                    selected: _priority == p,
                    onSelected: (_) => setState(() => _priority = p),
                  ),
                ChoiceChip(
                  avatar: Icon(
                    _isPrivate ? Icons.lock : Icons.lock_open,
                    size: 16,
                    color: kGreen,
                  ),
                  label: Text(s('Private', 'خاصة')),
                  selected: _isPrivate,
                  onSelected: (v) => setState(() => _isPrivate = v),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(labelText: s('Category', 'الفئة')),
              items: kCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(catLabel(c))))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'general'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recurrence,
              decoration: InputDecoration(labelText: s('Repeat', 'التكرار')),
              items: kRepeats
                  .map((r) => DropdownMenuItem(value: r, child: Text(repeatLabel(r))))
                  .toList(),
              onChanged: (v) => setState(() => _recurrence = v ?? 'none'),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(s('Save', 'حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    Widget? trailing,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: Row(
              children: [
                Icon(icon, size: 18, color: kGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: kMutedGreen,
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      BidiText(
                        value,
                        style: TextStyle(color: kText, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                trailing ?? Icon(Icons.chevron_right, size: 18, color: kMuted),
              ],
            ),
          ),
        ),
      );
}
