import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../services/widget_bridge.dart';
import 'note_editor_screen.dart';

/// قائمة كل الملاحظات: بحث، تثبيت، وحذف بالسحب.
class NotesScreen extends StatefulWidget {
  final DateTime? day;
  const NotesScreen({super.key, this.day});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _all = [];
  String _query = '';
  bool _loading = true;

  String s(String en, String ar) => appState.t(en, ar);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await Db.instance.allNotes();
    if (!mounted) return;
    setState(() {
      _all = notes;
      _loading = false;
    });
  }

  List<Note> get _filtered {
    var list = _all;
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((n) =>
          n.text.toLowerCase().contains(q) ||
          n.title.toLowerCase().contains(q)).toList();
    }
    // المثبّت أولاً ثم الأحدث.
    list = List<Note>.from(list)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return list;
  }

  Future<void> _open(Note? note) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          note: note,
          day: note?.day ?? widget.day ?? dateOnly(DateTime.now()),
        ),
      ),
    );
    if (changed == true || note == null) _load();
  }

  Future<void> _delete(Note n) async {
    await Db.instance.deleteNote(n.id);
    WidgetBridge.sync();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _filtered;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s('Notes', 'الملاحظات')),
        actions: [
          IconButton(
            tooltip: s('New note', 'ملاحظة جديدة'),
            icon: const Icon(Icons.note_add_outlined),
            onPressed: () => _open(null),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: BidiField(
                controller: TextEditingController(text: _query),
                hintText: s('Search notes…', 'ابحث في الملاحظات…'),
                prefixIcon: Icon(Icons.search, color: kMuted, size: 18),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (_loading)
              Expanded(child: Center(child: CircularProgressIndicator(color: kGreen)))
            else if (notes.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    s('No notes yet', 'لا ملاحظات بعد'),
                    style: TextStyle(color: kMuted),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: notes.length,
                  itemBuilder: (context, i) {
                    final n = notes[i];
                    return _tile(n);
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: kGreen,
        foregroundColor: isLight ? Colors.white : kBlack,
        onPressed: () => _open(null),
        child: const Icon(Icons.add, size: 22),
      ),
    );
  }

  Widget _tile(Note n) {
    final accent = n.colorHex == null ? kPetrol : _hex(n.colorHex!);
    return Dismissible(
      key: ValueKey('note-${n.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(s('Delete note?', 'حذف الملاحظة؟')),
                content: Text(s('This cannot be undone.', 'لا يمكن الرجوع بعد الحذف.')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(s('Cancel', 'إلغاء')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(s('Delete', 'حذف'), style: TextStyle(color: kRed)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => _delete(n),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          color: kRed.withAlpha(60),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: kRed),
      ),
      child: GestureDetector(
        onTap: () => _open(n),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: glass(border: accent.withAlpha(110)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (n.pinned)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Icon(Icons.push_pin, size: 14, color: kAmber),
                    ),
                  Expanded(
                    child: BidiText(
                      n.displayTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (n.remindAt != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: Icon(Icons.notifications_active,
                          size: 13, color: kAmber),
                    ),
                  // التاريخ معلومة فقط — الملاحظات كلها مجموعة معاً.
                  Text(
                    DateFormat.MMMd(appState.isArabic ? 'ar' : 'en_US')
                        .format(n.day),
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              if (n.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                BidiText(
                  n.text.replaceAll('\n', ' '),
                  style: TextStyle(color: kMuted, fontSize: 12, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    s('${n.wordCount} words', '${n.wordCount} كلمة'),
                    style: TextStyle(color: kMutedGreen, fontSize: 10),
                  ),
                  if (n.group.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.folder_outlined, size: 12, color: kAqua),
                    const SizedBox(width: 3),
                    Flexible(
                      child: BidiText(
                        n.group,
                        style: TextStyle(color: kAqua, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (n.spans.isNotEmpty)
                    Icon(Icons.format_size, size: 13, color: kMutedGreen),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: Icon(
                      n.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: n.pinned ? kAmber : kMuted,
                    ),
                    onPressed: () async {
                      await Db.instance.togglePin(n);
                      WidgetBridge.sync();
                      _load();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _hex(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}
