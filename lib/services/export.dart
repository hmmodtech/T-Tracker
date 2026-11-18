
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/database.dart';
import '../data/models.dart';

String _ymd(DateTime d) => dayKey(d).replaceAll('-', '');

String _icsStamp(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_ymd(u)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;')
    .replaceAll('\n', '\\n');

/// ملف ICS يُفتح في Google Calendar و Outlook مباشرة. المهام الخاصة لا تُصدَّر.
String toIcs(List<Task> tasks) {
  final b = StringBuffer(
      'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//T-Tracker//EN\r\nCALSCALE:GREGORIAN\r\n');
  for (final t in tasks.where((t) => !t.isPrivate)) {
    final next = DateTime(t.date.year, t.date.month, t.date.day + 1);
    final rule = switch (t.recurrence) {
      'daily' => 'FREQ=DAILY',
      'weekly' => 'FREQ=WEEKLY',
      'monthly' => 'FREQ=MONTHLY',
      _ => '',
    };
    b.write('BEGIN:VEVENT\r\n'
        'UID:sos-${t.id}@ajami\r\n'
        'DTSTAMP:${_icsStamp(t.updatedAt)}\r\n'
        'SUMMARY:${_esc(t.titleEn)}\r\n'
        'DESCRIPTION:${_esc(t.detailsEn)}\r\n'
        'DTSTART;VALUE=DATE:${_ymd(t.date)}\r\n'
        'DTEND;VALUE=DATE:${_ymd(next)}\r\n'
        '${rule.isEmpty ? '' : 'RRULE:$rule\r\n'}'
        'END:VEVENT\r\n');
  }
  b.write('END:VCALENDAR\r\n');
  return b.toString();
}

String toCsv(List<Task> tasks) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer(
      'date,title_en,title_ar,details_en,category,priority,recurrence\n');
  for (final t in tasks.where((t) => !t.isPrivate)) {
    b.writeln([
      dayKey(t.date),
      q(t.titleEn),
      q(t.titleAr),
      q(t.detailsEn),
      t.category,
      t.priority,
      t.recurrence,
    ].join(','));
  }
  return b.toString();
}

/// يستورد مهامّ من CSV (نفس صيغة التصدير).
///
/// إذا كان الملف يحتوي على عمود لغة واحد فقط (عربي مثلاً)، يُوضع النص في
/// العمودين حتى تظهر المهمة بأي لغة يختارها المستخدم لاحقاً — وهذا يحلّ
/// مشكلة المهام المستوردة التي كانت تبقى عربية دائماً.
Future<int> importCsv(String content) async {
  final lines = content
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) return 0;

  List<String> parse(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  final header = parse(lines.first).map((h) => h.trim().toLowerCase()).toList();
  int idx(String name) => header.indexOf(name);
  final iDate = idx('date');
  final iEn = idx('title_en');
  final iAr = idx('title_ar');
  final iDet = idx('details_en');
  final iDetAr = idx('details_ar');
  final iCat = idx('category');
  final iPri = idx('priority');
  final iRep = idx('recurrence');

  var added = 0;
  final now = DateTime.now();
  for (final line in lines.skip(1)) {
    final f = parse(line);
    String at(int i) => (i >= 0 && i < f.length) ? f[i].trim() : '';
    final dateText = iDate >= 0 ? at(iDate) : '';
    if (dateText.isEmpty) continue;
    final date = DateTime.tryParse(dateText) ?? now;

    final en = iEn >= 0 ? at(iEn) : '';
    final ar = iAr >= 0 ? at(iAr) : '';
    // Fall back to whichever language the file actually provides.
    final titleEn = en.isNotEmpty ? en : ar;
    final titleAr = ar.isNotEmpty ? ar : en;
    if (titleEn.isEmpty) continue;

    final detEn = iDet >= 0 ? at(iDet) : '';
    final detAr = iDetAr >= 0 ? at(iDetAr) : '';

    await Db.instance.saveTask(Task(
      titleEn: titleEn,
      titleAr: titleAr,
      detailsEn: detEn.isNotEmpty ? detEn : detAr,
      detailsAr: detAr.isNotEmpty ? detAr : detEn,
      date: dateOnly(date),
      category: iCat >= 0 && at(iCat).isNotEmpty ? at(iCat) : 'general',
      priority: iPri >= 0 ? (int.tryParse(at(iPri)) ?? 1) : 1,
      recurrence: iRep >= 0 && at(iRep).isNotEmpty ? at(iRep) : 'none',
      updatedAt: now,
    ));
    added++;
  }
  return added;
}

/// يفتح منتقي ملفات ويستورد CSV.
Future<int> pickAndImportCsv() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return 0;
  final f = result.files.first;
  final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
  if (bytes == null) return 0;
  // Handle a UTF-8 BOM that Excel writes.
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return importCsv(text);
}

Future<void> shareFile(String name, String content, String mime) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsString(content);
  await Share.shareXFiles([XFile(file.path, mimeType: mime)]);
}

Future<void> exportBackup() async {
  final data = jsonEncode(await Db.instance.exportAll());
  await shareFile('sos_backup.json', data, 'application/json');
}

/// يرجع true إذا تمت الاستعادة
Future<bool> importBackup() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  final bytes = res?.files.single.bytes;
  if (bytes == null) return false;
  await Db.instance.importAll(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
  return true;
}
