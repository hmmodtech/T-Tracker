import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/backdrop.dart';
import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../services/notifications.dart';
import '../data/models.dart';
import '../services/widget_bridge.dart';

/// محرّر ملاحظات غني يشبه Word المصغّر.
///
/// يدعم العنوان، الغامق، المائل، التسطير، الشطب، العناوين بثلاثة أحجام،
/// القوائم النقطية، ولون الملاحظة، مع عدّاد كلمات وحفظ تلقائي عند الخروج.
/// النص الطويل يُعرض داخل حقل قابل للتمرير بلا حدود.
class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final DateTime day;

  /// المجلد المقترح عند إنشاء ملاحظة من داخل مجلد.
  final String? group;

  const NoteEditorScreen({
    super.key,
    this.note,
    required this.day,
    this.group,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title;
  late final _RichController _body;
  final FocusNode _focus = FocusNode();

  late DateTime _day;
  String? _color;
  late String _group;
  DateTime? _remindAt;

  // التنسيق الحالي (يُطبّق على التحديد أو على ما يُكتب بعده)
  bool _bold = false;
  bool _italic = false;
  bool _underline = false;
  bool _strike = false;
  bool _bullet = false;
  int _heading = 0;
  double _sizeDelta = 0;

  /// المقاطع المنسّقة المحفوظة (start, end, attributes).
  late List<NoteSpan> _spans;

  bool _dirty = false;
  bool _saving = false;
  int _words = 0;

  static const _palette = <String>[
    '#25F4C8',
    '#38BDF8',
    '#B6FFE9',
    '#FFC15E',
    '#FF5470',
    '#A78BFA',
  ];

  String s(String en, String ar) => appState.t(en, ar);

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _title = TextEditingController(text: n?.title ?? '');
    _spans = List<NoteSpan>.from(n?.spans ?? const []);
    _body = _RichController(
      text: n?.text ?? '',
      spans: _spans,
      base: TextStyle(color: kText, fontSize: 15, height: 1.45),
    );
    _day = n?.day ?? widget.day;
    _color = n?.colorHex;
    _group = n?.group ?? widget.group ?? '';
    _remindAt = n?.remindAt;
    _recount();

    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final before = _words;
    _recount();
    if (!_dirty || before != _words) {
      setState(() => _dirty = true);
    }
  }

  void _recount() {
    final t = _body.text.trim();
    _words = t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  // ── formatting ────────────────────────────────────────────────────────────

  TextSelection get _sel =>
      _body.selection.isValid
          ? _body.selection
          : TextSelection.collapsed(offset: _body.text.length);

  bool get _hasSelection =>
      _body.selection.isValid && _body.selection.start != _body.selection.end;

  /// يطبّق التنسيق الحالي على التحديد، أو يفعّله للكتابة القادمة.
  void _applyToSelection() {
    if (!_hasSelection) return;
    final start = _body.selection.start;
    final end = _body.selection.end;
    setState(() {
      // أزل أي مقطع متقاطع مع التحديد (تبسيط مقصود: التنسيق يُعاد كتابته)
      _spans.removeWhere((sp) => sp.start < end && sp.end > start);
      final span = NoteSpan(
        start: start,
        end: end,
        bold: _bold,
        italic: _italic,
        underline: _underline,
        strike: _strike,
        heading: _heading,
        bullet: _bullet,
        sizeDelta: _sizeDelta,
      );
      if (!span.isDefault) _spans.add(span);
      _body.setSpans(_spans);
      _dirty = true;
    });
  }

  // ── saving ────────────────────────────────────────────────────────────────

  Future<void> _save({bool close = false}) async {
    if (_saving) return;
    final body = _body.text;
    if (body.trim().isEmpty && _title.text.trim().isEmpty) {
      if (close && mounted) Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final note = Note(
        id: widget.note?.id ?? 0,
        day: _day,
        text: body,
        title: _title.text.trim(),
        colorHex: _color,
        spans: _spans,
        pinned: widget.note?.pinned ?? false,
        group: _group,
        remindAt: _remindAt,
        updatedAt: DateTime.now(),
      );
      final id = await Db.instance.saveNote(note);
      // جدولة/إلغاء منبّه الملاحظة بنفس محرّك تذكيرات التطبيق.
      // نستخدم المعرّف الحقيقي حتى تُلغى التذكيرات القديمة بنفس الرقم.
      await Bell.scheduleNote(
        note.id == 0
            ? Note(
                id: id,
                day: note.day,
                text: note.text,
                title: note.title,
                colorHex: note.colorHex,
                spans: note.spans,
                pinned: note.pinned,
                group: note.group,
                remindAt: note.remindAt,
              )
            : note,
        enabled: appState.notificationsOn,
      );
      WidgetBridge.sync();
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      if (close) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s('Note saved', 'تم حفظ الملاحظة'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s('Could not save', 'تعذّر الحفظ'))),
      );
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _day = dateOnly(d));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Widget _toolButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    String? tooltip,
  }) =>
      Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 38,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: active ? kGreen.withAlpha(isLight ? 40 : 45) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? kGreen : Colors.transparent,
              ),
            ),
            child: Icon(icon, size: 18, color: active ? kGreen : kMuted),
          ),
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: kPetrol,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        if (_dirty) {
          await _save(close: true);
        } else {
          if (mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s('Note', 'ملاحظة')),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: s('Save', 'حفظ'),
                icon: const Icon(Icons.check),
                onPressed: _dirty ? () => _save() : null,
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _metaRow(),
              _toolbar(),
              Expanded(child: _editor()),
              _statusBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        // شريط أفقي: التاريخ + المجلد + المنبّه + ألوان الملاحظة.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
          children: [
            ActionChip(
              avatar: Icon(Icons.folder_outlined, size: 15, color: kAqua),
              label: Text(
                _group.isEmpty ? s('No list', 'بدون مجلد') : _group,
                style: TextStyle(fontSize: 12, color: kText),
              ),
              backgroundColor: kSurface.withAlpha(160),
              side: BorderSide(color: kPetrol),
              onPressed: _pickGroup,
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: Icon(
                _remindAt == null
                    ? Icons.notifications_none
                    : Icons.notifications_active,
                size: 15,
                color: _remindAt == null ? kGreen : kAmber,
              ),
              label: Text(
                _remindAt == null
                    ? s('Remind', 'منبّه')
                    : '${_remindAt!.hour.toString().padLeft(2, '0')}:'
                        '${_remindAt!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: kText),
              ),
              backgroundColor: kSurface.withAlpha(160),
              side: BorderSide(color: kPetrol),
              onPressed: _pickReminder,
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: Icon(Icons.calendar_today, size: 15, color: kGreen),
              label: Text(
                '${_day.year}-${_day.month.toString().padLeft(2, '0')}-'
                '${_day.day.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: kText),
              ),
              backgroundColor: kSurface.withAlpha(160),
              side: BorderSide(color: kPetrol),
              onPressed: _pickDate,
            ),
            const SizedBox(width: 8),
            // ألوان الملاحظة
            for (final c in _palette)
              GestureDetector(
                onTap: () => setState(() => _color = _color == c ? null : c),
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _hex(c).withAlpha(210),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c ? kText : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
          ),
        ),
      );

  /// اختيار المجلد (نفس مجلدات المهام).
  Future<void> _pickGroup() async {
    final groups = await Db.instance.taskGroups();
    if (!mounted) return;
    final c = TextEditingController(text: _group);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(s('List (group)', 'المجلد')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BidiField(
                controller: c,
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
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(s('Use', 'استخدام')),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _group = picked;
      _dirty = true;
    });
  }

  /// منبّه الملاحظة: يفتح التطبيق نفسه عند الوقت المحدّد.
  Future<void> _pickReminder() async {
    final base = _remindAt ??
        DateTime(_day.year, _day.month, _day.day, 9);
    final date = await showDatePicker(
      context: context,
      initialDate: base.isBefore(DateTime.now()) ? DateTime.now() : base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (tm == null) return;
    setState(() {
      _remindAt = DateTime(date.year, date.month, date.day, tm.hour, tm.minute);
      _dirty = true;
    });
  }

  Widget _toolbar() => Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: glass(border: kPetrol),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _toolButton(
                icon: Icons.format_bold,
                active: _bold,
                tooltip: s('Bold', 'غامق'),
                onTap: () {
                  setState(() => _bold = !_bold);
                  _applyToSelection();
                },
              ),
              _toolButton(
                icon: Icons.format_italic,
                active: _italic,
                tooltip: s('Italic', 'مائل'),
                onTap: () {
                  setState(() => _italic = !_italic);
                  _applyToSelection();
                },
              ),
              _toolButton(
                icon: Icons.format_underlined,
                active: _underline,
                tooltip: s('Underline', 'تسطير'),
                onTap: () {
                  setState(() => _underline = !_underline);
                  _applyToSelection();
                },
              ),
              _toolButton(
                icon: Icons.format_strikethrough,
                active: _strike,
                tooltip: s('Strikethrough', 'شطب'),
                onTap: () {
                  setState(() => _strike = !_strike);
                  _applyToSelection();
                },
              ),
              _divider(),
              _toolButton(
                icon: Icons.title,
                active: _heading == 1,
                tooltip: s('Heading', 'عنوان'),
                onTap: () {
                  setState(() => _heading = _heading == 1 ? 0 : 1);
                  _applyToSelection();
                },
              ),
              _toolButton(
                icon: Icons.text_fields,
                active: _heading == 2,
                tooltip: s('Sub-heading', 'عنوان فرعي'),
                onTap: () {
                  setState(() => _heading = _heading == 2 ? 0 : 2);
                  _applyToSelection();
                },
              ),
              _divider(),
              _toolButton(
                icon: Icons.format_list_bulleted,
                active: _bullet,
                tooltip: s('Bullet list', 'قائمة نقطية'),
                onTap: _insertBullet,
              ),
              _toolButton(
                icon: Icons.format_list_numbered,
                active: false,
                tooltip: s('Numbered list', 'قائمة مرقّمة'),
                onTap: _insertNumbered,
              ),
              _divider(),
              _toolButton(
                icon: Icons.text_increase,
                active: false,
                tooltip: s('Bigger text', 'تكبير الخط'),
                onTap: () {
                  setState(() => _sizeDelta =
                      (_sizeDelta + 0.15).clamp(0.0, 1.2));
                  _applyToSelection();
                },
              ),
              _toolButton(
                icon: Icons.text_decrease,
                active: false,
                tooltip: s('Smaller text', 'تصغير الخط'),
                onTap: () {
                  setState(() => _sizeDelta =
                      (_sizeDelta - 0.15).clamp(-0.3, 1.2));
                  _applyToSelection();
                },
              ),
              _divider(),
              _toolButton(
                icon: Icons.format_clear,
                active: false,
                tooltip: s('Clear formatting', 'إزالة التنسيق'),
                onTap: () {
                  setState(() {
                    _bold = false;
                    _italic = false;
                    _underline = false;
                    _strike = false;
                    _bullet = false;
                    _heading = 0;
                    _sizeDelta = 0;
                    if (_hasSelection) {
                      final start = _body.selection.start;
                      final end = _body.selection.end;
                      _spans.removeWhere((sp) => sp.start < end && sp.end > start);
                      _dirty = true;
                    }
                  });
                },
              ),
            ],
          ),
        ),
      );

  void _insertBullet() {
    final sel = _sel;
    final text = _body.text;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    if (sel.start >= 0 && (lineStart == 0 || text[lineStart - 1] == '\n')) {
      final insert = '• ';
      final newText = text.substring(0, lineStart) + insert + text.substring(lineStart);
      _body.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + insert.length),
      );
      setState(() => _dirty = true);
    }
  }

  void _insertNumbered() {
    final sel = _sel;
    final text = _body.text;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final before = text.substring(0, lineStart);
    final count = '1. '.length;
    final newText = '$before${text.length > lineStart && text.startsWith(RegExp(r'^\d+\. '), lineStart) ? '' : '1. '}${text.substring(lineStart)}';
    if (newText != text) {
      _body.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + count),
      );
      setState(() => _dirty = true);
    }
  }

  Widget _editor() {
    final base = TextStyle(
      color: kText,
      fontSize: 15,
      height: 1.45,
    );
    final dir = detectDir(_body.text);
    final textDirection = dir == TextDir.rtl
        ? TextDirection.rtl
        : dir == TextDir.ltr
            ? TextDirection.ltr
            : Directionality.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: glass(
        border: _color == null ? kPetrol : _hex(_color!).withAlpha(140),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          BidiField(
            controller: _title,
            hintText: s('Title', 'العنوان'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
            maxLines: 2,
          ),
          Divider(color: kPetrol, height: 18),
          // A single editable field whose controller renders the saved
          // formatting. This keeps caret, selection and scrolling exact even
          // for very long notes — no overlay to desync.
          Expanded(
            child: _rich(
              textDirection: textDirection,
              base: base,
            ),
          ),
        ],
      ),
    );
  }

  /// حقل النص الغني: المتحكّم يرسم التنسيقات داخل TextField نفسه.
  Widget _rich({required TextDirection textDirection, required TextStyle base}) {
    return Directionality(
      textDirection: textDirection,
      child: TextField(
        controller: _body,
        focusNode: _focus,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlign: textDirection == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
        style: base,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: s(
            'Start writing… supports long text',
            'ابدأ الكتابة… يدعم النصوص الطويلة',
          ),
          hintStyle: TextStyle(color: kMuted),
        ),
        onChanged: (_) {
          _onChanged();
          // Redraw so the formatting of a fresh selection shows up.
          setState(() {});
        },
      ),
    );
  }

  Widget _statusBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Text(
              s('$_words words', '$_words كلمة'),
              style: TextStyle(color: kMuted, fontSize: 11),
            ),
            const Spacer(),
            if (_dirty)
              Text(
                s('Unsaved changes', 'تغييرات غير محفوظة'),
                style: TextStyle(color: kAmber, fontSize: 11),
              )
            else
              Text(
                s('Saved automatically', 'يُحفظ تلقائياً'),
                style: TextStyle(color: kMutedGreen, fontSize: 11),
              ),
          ],
        ),
      );

  Color _hex(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}

/// متحكّم يعرض النص مع تنسيقاته داخل حقل تحرير واحد.
///
/// Flutter لا يملك محرّر نصوص غني جاهزاً، والحل القياسي هو بناء Span من
/// المقاطع المحفوظة وإعادة بنائه عند كل تغيير. هذا يحافظ على المؤشر
/// والتحديد والتمرير صحيحاً حتى مع النصوص الطويلة.
class _RichController extends TextEditingController {
  /// الخاصية الفعلية — استخدم [_setSpans] لتحديثها مع إعادة الرسم.
  List<NoteSpan> _spans;
  List<NoteSpan> get spans => _spans;

  final TextStyle base;

  _RichController({
    required String text,
    required List<NoteSpan> spans,
    required this.base,
  })  : _spans = List<NoteSpan>.from(spans),
        super(text: text);

  /// يحدّث التنسيقات ويعيد بناء النص المعروض.
  void setSpans(List<NoteSpan> value) {
    _spans = List<NoteSpan>.from(value);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_spans.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final sorted = List<NoteSpan>.from(_spans)
      ..sort((a, b) => a.start.compareTo(b.start));
    final children = <TextSpan>[];
    var cursor = 0;
    for (final sp in sorted) {
      final s0 = sp.start.clamp(0, text.length);
      final e0 = sp.end.clamp(0, text.length);
      if (e0 <= cursor) continue;
      final from = s0 < cursor ? cursor : s0;
      if (from > cursor) {
        children.add(TextSpan(text: text.substring(cursor, from)));
      }
      children.add(TextSpan(
        text: text.substring(from, e0),
        style: (style ?? base).copyWith(
          fontWeight: sp.bold ? FontWeight.w800 : null,
          fontStyle: sp.italic ? FontStyle.italic : null,
          decoration: _deco(sp),
          fontSize: ((style ?? base).fontSize ?? 15) *
              (1 + _heading(sp.heading) + sp.sizeDelta),
        ),
      ));
      cursor = e0;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }

  double _heading(int h) => switch (h) {
        1 => 0.6,
        2 => 0.35,
        3 => 0.15,
        _ => 0,
      };

  TextDecoration _deco(NoteSpan sp) {
    final parts = <TextDecoration>[];
    if (sp.underline) parts.add(TextDecoration.underline);
    if (sp.strike) parts.add(TextDecoration.lineThrough);
    if (parts.isEmpty) return TextDecoration.none;
    if (parts.length == 1) return parts.first;
    return TextDecoration.combine(parts);
  }
}
