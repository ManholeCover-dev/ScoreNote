import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'domain.dart';

class Store extends GeneratedDatabase {
  Store(super.executor);
  factory Store.local() => Store(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return NativeDatabase.createInBackground(
        File('${dir.path}/scorenote.sqlite'),
      );
    }),
  );
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE students(id INTEGER PRIMARY KEY,name TEXT NOT NULL,grade TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE plans(student INTEGER NOT NULL REFERENCES students(id),grade TEXT NOT NULL,date TEXT NOT NULL,mode TEXT NOT NULL,choices TEXT NOT NULL, PRIMARY KEY(student,grade,date))',
      );
      await customStatement(
        'CREATE TABLE exams(id INTEGER PRIMARY KEY,student INTEGER NOT NULL REFERENCES students(id),grade TEXT NOT NULL,date TEXT NOT NULL,title TEXT NOT NULL,type TEXT NOT NULL,note TEXT NOT NULL,draft INTEGER NOT NULL,marks TEXT NOT NULL,ranks TEXT)',
      );
      await customStatement(
        'CREATE INDEX by_student_date ON exams(student,date DESC,id DESC)',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await customStatement('ALTER TABLE exams ADD COLUMN ranks TEXT');
      }
    },
    beforeOpen: (d) => customStatement('PRAGMA foreign_keys=ON'),
  );
  Future<List<Student>> students() async =>
      (await customSelect('SELECT * FROM students ORDER BY id').get())
          .map((r) => Student(r.read('id'), r.read('name'), r.read('grade')))
          .toList();
  Future<int> add(String name, String grade) {
    if (name.trim().isEmpty || !grades.contains(grade)) {
      throw ArgumentError('无效的档案');
    }
    return customInsert(
      'INSERT INTO students(name,grade) VALUES (?,?)',
      variables: [Variable(name.trim()), Variable(grade)],
    );
  }

  Future<void> changeGrade(int id, String grade) =>
      customStatement('UPDATE students SET grade=? WHERE id=?', [grade, id]);
  Future<List<Plan>> plans(int id) async =>
      (await customSelect(
            'SELECT * FROM plans WHERE student=? ORDER BY date DESC',
            variables: [Variable(id)],
          ).get())
          .map(
            (r) => Plan(
              id,
              r.read('grade'),
              r.read('date'),
              r.read('mode'),
              List<String>.from(jsonDecode(r.read('choices'))),
            ),
          )
          .toList();
  Future<void> setPlan(Plan p) {
    if (!validPlan(p.mode, p.choices) || !grades.skip(1).contains(p.grade)) {
      throw ArgumentError('选科组合无效');
    }
    return customStatement(
      'INSERT INTO plans VALUES(?,?,?,?,?) ON CONFLICT(student,grade,date) DO UPDATE SET mode=excluded.mode,choices=excluded.choices',
      [p.student, p.grade, p.date, p.mode, jsonEncode(p.choices)],
    );
  }

  Future<List<Exam>> exams(int student) async =>
      (await customSelect(
            'SELECT * FROM exams WHERE student=? ORDER BY date DESC,id DESC',
            variables: [Variable(student)],
          ).get())
          .map(
            (r) => Exam(
              r.read('id'),
              student,
              r.read('grade'),
              r.read('date'),
              r.read('title'),
              r.read('type'),
              r.read('note'),
              r.read<int>('draft') != 0,
              (jsonDecode(r.read('marks')) as List)
                  .map((m) => Mark.read(m))
                  .toList(),
              Ranks.read(jsonDecode(r.readNullable<String>('ranks') ?? 'null')),
            ),
          )
          .toList();
  Future<int> save(Exam e) async {
    final subjects = e.marks.map((m) => m.subject).toSet();
    if (!e.ranks.valid ||
        !grades.contains(e.grade) ||
        !core.every(subjects.contains) ||
        !subjects.every([...core, ...options].contains) ||
        subjects.length != (e.grade == grades.first ? 9 : 6) ||
        subjects.length != e.marks.length ||
        !e.marks.every((m) => m.valid) ||
        (!e.draft && (e.title.trim().isEmpty || e.expected.isEmpty))) {
      throw ArgumentError('成绩单无效');
    }
    final args = [
      Variable(e.student),
      Variable(e.grade),
      Variable(e.date),
      Variable(e.title),
      Variable(e.type),
      Variable(e.note),
      Variable(e.draft ? 1 : 0),
      Variable(jsonEncode(e.marks.map((m) => m.json()).toList())),
      Variable(jsonEncode(e.ranks.json())),
    ];
    if (e.id == null) {
      return customInsert(
        'INSERT INTO exams(student,grade,date,title,type,note,draft,marks,ranks) VALUES(?,?,?,?,?,?,?,?,?)',
        variables: args,
      );
    }
    await customUpdate(
      'UPDATE exams SET student=?,grade=?,date=?,title=?,type=?,note=?,draft=?,marks=?,ranks=? WHERE id=? AND student=?',
      variables: [...args, Variable(e.id!), Variable(e.student)],
    );
    return e.id!;
  }

  Future<void> remove(int id, int student) => customStatement(
    'DELETE FROM exams WHERE id=? AND student=?',
    [id, student],
  );
}
