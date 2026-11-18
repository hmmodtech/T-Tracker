
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'models.dart';

/// قاعدة بيانات مشفرة (SQLCipher). المفتاح محفوظ في Keystore.
class Db {
  Db._();
  static final instance = Db._();
  static const _keyName = 'sos_db_key';
  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    const store = FlutterSecureStorage();
    var key = await store.read(key: _keyName);
    if (key == null || key.isEmpty) {
      final rnd = Random.secure();
      key = base64Url.encode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      try {
        await store.write(key: _keyName, value: key);
      } catch (_) {
        // Keystore unavailable: keep the generated key in memory for this run.
      }
    }
    return openDatabase(
      p.join(await getDatabasesPath(), 'sos_secure.db'),
      password: key,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title_en TEXT NOT NULL, title_ar TEXT,
            details_en TEXT, details_ar TEXT,
            date TEXT NOT NULL, remind_at TEXT,
            category TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 1,
            is_private INTEGER NOT NULL DEFAULT 0,
            recurrence TEXT NOT NULL DEFAULT 'none',
            until TEXT,
            checklist TEXT,
            is_mission INTEGER NOT NULL DEFAULT 0,
            grp TEXT NOT NULL DEFAULT '',
            google_id TEXT, ms_id TEXT,
            updated_at TEXT NOT NULL)''');
        await db.execute('''
          CREATE TABLE completions (
            task_id INTEGER NOT NULL, day TEXT NOT NULL,
            PRIMARY KEY (task_id, day))''');
        await db.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day TEXT NOT NULL,
            text TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            color TEXT,
            spans TEXT,
            pinned INTEGER NOT NULL DEFAULT 0,
            grp TEXT NOT NULL DEFAULT '',
            remind_at TEXT,
            updated_at TEXT)''');
      },
      // Migration is column-aware and individually guarded: an `ALTER TABLE`
      // that fails (or a column that already exists) must never leave the
      // database half-migrated — that used to hang every screen on its
      // loading spinner, because the first query never resolved.
      //
      // v2: recurring windows (the pre-defined plan ends on a fixed day).
      // v3: rich notes (title, colour, formatting spans, pin, timestamp).
      // v4: To-Do groups + note reminders.
      onUpgrade: (db, from, to) async {
        Future<void> add(
          String table,
          String column,
          String type, {
          String? defaultValue,
        }) async {
          try {
            final existing = await db.rawQuery('PRAGMA table_info($table)');
            final has = existing.any((c) => c['name'] == column);
            if (has) return;
            await db.execute(
              'ALTER TABLE $table ADD COLUMN $column $type'
              '${defaultValue == null ? '' : ' NOT NULL DEFAULT $defaultValue'}',
            );
          } catch (_) {
            // Never block startup on a single column.
          }
        }

        if (from < 2) {
          await add('tasks', 'until', 'TEXT');
        }
        if (from < 3) {
          await add('notes', 'title', 'TEXT', defaultValue: "''");
          await add('notes', 'color', 'TEXT');
          await add('notes', 'spans', 'TEXT');
          await add('notes', 'pinned', 'INTEGER', defaultValue: '0');
          await add('notes', 'updated_at', 'TEXT');
        }
        if (from < 4) {
          // To-Do groups for tasks and notes, and a reminder on a note.
          await add('tasks', 'grp', 'TEXT', defaultValue: "''");
          await add('notes', 'grp', 'TEXT', defaultValue: "''");
          await add('notes', 'remind_at', 'TEXT');
        }
      },
    );
  }

  // ---------- Tasks ----------
  Future<List<Task>> tasks() async {
    final db = await _database;
    final rows = await db.query('tasks', orderBy: 'date, remind_at');
    return rows.map(Task.fromMap).toList();
  }

  /// يضيف أو يعدّل ويرجع الـ id
  Future<int> saveTask(Task t) async {
    final db = await _database;
    final map = t.toMap();
    if (t.id == null) return db.insert('tasks', map);
    await db.update('tasks', map, where: 'id = ?', whereArgs: [t.id]);
    return t.id!;
  }

  Future<void> deleteTask(int id) async {
    final db = await _database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    await db.delete('completions', where: 'task_id = ?', whereArgs: [id]);
  }

  Future<void> setSyncIds(int id, {String? google, String? ms}) async {
    final db = await _database;
    await db.update(
      'tasks',
      {if (google != null) 'google_id': google, if (ms != null) 'ms_id': ms},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setChecklistDone(int id, int index, bool done) async {
    final db = await _database;
    final row = (await db.query('tasks',
            columns: ['checklist'], where: 'id = ?', whereArgs: [id]))
        .first;
    final list = (jsonDecode(row['checklist'] as String? ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    list[index]['d'] = done;
    await db.update(
      'tasks',
      {
        'checklist': jsonEncode(list),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// يستبدل مهام الخطة فقط (is_mission = 1)
  Future<void> replaceMission(List<Task> mission) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('tasks', where: 'is_mission = 1');
      for (final t in mission) {
        await txn.insert('tasks', t.toMap());
      }
    });
  }

  /// كل أسماء المجلدات المستخدمة فعلاً، مرتّبة.
  Future<List<String>> taskGroups() async {
    final db = await _database;
    final rows = await db.rawQuery(
      "SELECT grp FROM tasks WHERE grp IS NOT NULL AND grp != '' "
      'GROUP BY grp ORDER BY grp COLLATE NOCASE',
    );
    final noteRows = await db.rawQuery(
      "SELECT grp FROM notes WHERE grp IS NOT NULL AND grp != '' "
      'GROUP BY grp ORDER BY grp COLLATE NOCASE',
    );
    final all = <String>{};
    for (final r in rows) {
      all.add('${r['grp']}');
    }
    for (final r in noteRows) {
      all.add('${r['grp']}');
    }
    final list = all.where((g) => g.trim().isNotEmpty).toList()..sort();
    return list;
  }

  /// ينقل مهمة إلى مجلد آخر (أو يزيل مجلدها عند '').
  Future<void> moveTaskToGroup(int id, String group) async {
    final db = await _database;
    await db.update(
      'tasks',
      {'grp': group, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// كل المهام في مجلد معيّن — تُستخدم لشاشة المجلد.
  Future<List<Task>> tasksInGroup(String group) async {
    final db = await _database;
    final rows = await db.query(
      'tasks',
      where: 'grp = ?',
      whereArgs: [group],
      orderBy: 'date, remind_at',
    );
    return rows.map(Task.fromMap).toList();
  }

  // ---------- Completions ----------
  Future<Set<String>> completionKeys() async {
    final db = await _database;
    final rows = await db.query('completions');
    return {for (final r in rows) '${r['task_id']}|${r['day']}'};
  }

  Future<void> setDone(int taskId, DateTime day, bool done) async {
    final db = await _database;
    if (done) {
      await db.insert(
        'completions',
        {'task_id': taskId, 'day': dayKey(day)},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await db.delete('completions',
          where: 'task_id = ? AND day = ?', whereArgs: [taskId, dayKey(day)]);
    }
  }

  // ---------- Notes ----------
  Future<List<Note>> notesOn(DateTime day) async {
    final db = await _database;
    final rows = await db.query('notes',
        where: 'day = ?', whereArgs: [dayKey(day)], orderBy: 'id');
    return rows.map(Note.fromMap).toList();
  }

  /// كل الملاحظات، الأحدث أولاً — الودجت يعرض أحدث ما كتبه المستخدم.
  Future<List<Note>> allNotes() async {
    final db = await _database;
    final rows = await db.query('notes', orderBy: 'day DESC, id DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<void> addNote(DateTime day, String text) async {
    final db = await _database;
    await db.insert('notes', {
      'day': dayKey(day),
      'text': text,
      'title': '',
      'pinned': 0,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// يحفظ ملاحظة كاملة (مع التنسيقات). يرجع المعرّف.
  Future<int> saveNote(Note n) async {
    final db = await _database;
    final map = n.toMap();
    if (n.id <= 0) return db.insert('notes', map);
    await db.update('notes', map, where: 'id = ?', whereArgs: [n.id]);
    return n.id;
  }

  Future<void> togglePin(Note n) async {
    final db = await _database;
    await db.update(
      'notes',
      {'pinned': n.pinned ? 0 : 1},
      where: 'id = ?',
      whereArgs: [n.id],
    );
  }

  Future<void> deleteNote(int id) async {
    final db = await _database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Backup / Restore ----------
  Future<Map<String, dynamic>> exportAll() async {
    final db = await _database;
    return {
      'version': 2,
      'tasks': await db.query('tasks'),
      'notes': await db.query('notes'),
      'completions': await db.query('completions'),
    };
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('tasks');
      await txn.delete('notes');
      await txn.delete('completions');
      for (final r in data['tasks'] as List) {
        await txn.insert('tasks', Map<String, Object?>.from(r as Map));
      }
      for (final r in data['notes'] as List) {
        await txn.insert('notes', Map<String, Object?>.from(r as Map));
      }
      for (final r in data['completions'] as List) {
        await txn.insert('completions', Map<String, Object?>.from(r as Map));
      }
    });
  }
}

