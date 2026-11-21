import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas/services/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late String testDbPath;

  setUpAll(() {
    DatabaseHelper.ensureInitialized();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notas_db_test_');
    testDbPath = p.join(tempDir.path, 'NotasTest.db');
    await DatabaseHelper.setDatabasePathOverrideForTest(testDbPath);
  });

  tearDown(() async {
    await DatabaseHelper.setDatabasePathOverrideForTest(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DatabaseHelper migrations, batch queries, and safe import/restore', () {
    test('sequentially upgrades v4 schema to v7 preserving existing data', () async {
      final legacyPath = p.join(tempDir.path, 'legacy_v4.db');
      final legacyDb = await databaseFactory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE semesters (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE subjects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                semester_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                average_type TEXT NOT NULL DEFAULT 'Aritmetico',
                has_global_exam INTEGER NOT NULL DEFAULT 0,
                global_exam_replaces_worst INTEGER NOT NULL DEFAULT 0,
                min_passing_grade REAL NOT NULL DEFAULT 4.0
              )
            ''');
            await db.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                subject_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                total_weight REAL NOT NULL,
                min_passing_grade REAL
              )
            ''');
            await db.execute('''
              CREATE TABLE evaluations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                specific_weight REAL,
                grade REAL,
                date TEXT
              )
            ''');
          },
        ),
      );

      await legacyDb.insert('semesters', {'id': 1, 'name': '2025-1'});
      await legacyDb.insert('subjects', {
        'id': 10,
        'semester_id': 1,
        'name': 'Programación',
        'average_type': 'Aritmetico',
        'has_global_exam': 0,
        'global_exam_replaces_worst': 0,
        'min_passing_grade': 4.0,
      });
      await legacyDb.insert('categories', {
        'id': 20,
        'subject_id': 10,
        'name': 'Certámenes',
        'total_weight': 60.0,
      });

      await DatabaseHelper.upgradeDatabaseForTest(legacyDb, 4, 7);

      final upgradedSubjects = await legacyDb.query('subjects');
      expect(upgradedSubjects, hasLength(1));
      expect(upgradedSubjects.first['name'], 'Programación');
      expect(upgradedSubjects.first['order_index'], 0);
      expect(upgradedSubjects.first.containsKey('color'), isTrue);

      final upgradedCategories = await legacyDb.query('categories');
      expect(upgradedCategories, hasLength(1));
      expect(upgradedCategories.first['average_type'], 'Aritmetico');
      expect(upgradedCategories.first['drop_lowest'], 0);
      expect(upgradedCategories.first.containsKey('custom_formula'), isTrue);

      await legacyDb.insert('horario_clases', {
        'semester_id': 1,
        'subject_name': 'Programación',
        'dia_semana': 1,
        'bloque': 3,
        'sala': 'A-101',
        'paralelo': '1',
      });
      final horarios = await legacyDb.query('horario_clases');
      expect(horarios, hasLength(1));
      await legacyDb.close();
    });

    test('supports atomic category+evaluations insert, batch order update, and scheduled join query', () async {
      final db = DatabaseHelper.instance;
      final semId = await db.insertSemester({'name': '2026-2'});
      final subA = await db.insertSubject({
        'semester_id': semId,
        'name': 'Física',
        'average_type': 'Aritmetico',
        'has_global_exam': 0,
        'global_exam_replaces_worst': 0,
        'min_passing_grade': 4.0,
        'order_index': 0,
      });
      final subB = await db.insertSubject({
        'semester_id': semId,
        'name': 'Cálculo',
        'average_type': 'Aritmetico',
        'has_global_exam': 0,
        'global_exam_replaces_worst': 0,
        'min_passing_grade': 4.0,
        'order_index': 1,
      });

      await db.updateSubjectOrders([
        (id: subA, orderIndex: 5),
        (id: subB, orderIndex: 1),
      ]);
      final orderedSubjects = await db.querySubjectsBySemester(semId);
      expect(orderedSubjects.first['id'], subB);
      expect(orderedSubjects.last['id'], subA);

      final catId = await db.insertCategoryWithEvaluations(
        {
          'subject_id': subA,
          'name': 'Controles',
          'total_weight': 40.0,
          'average_type': 'Aritmetico',
          'drop_lowest': 0,
        },
        [
          {'name': 'Control 1', 'grade': 5.5, 'date': '2026-10-15T10:00:00.000'},
          {'name': 'Control 2', 'grade': null, 'date': null},
        ],
      );
      expect(catId, greaterThan(0));

      final grouped = await db.queryCategoriesWithEvaluationsBySubject(subA);
      expect(grouped, hasLength(1));
      expect(grouped.first.category['name'], 'Controles');
      expect(grouped.first.evaluations, hasLength(2));

      final scheduled = await db.queryAllScheduledEvaluationsWithSubject();
      expect(scheduled, hasLength(1));
      expect(scheduled.first['name'], 'Control 1');
      expect(scheduled.first['subject_name'], 'Física');
      expect(scheduled.first['subject_id'], subA);
    });

    test('restoreFullSnapshot filters unknown columns through allowlist', () async {
      final db = DatabaseHelper.instance;
      await db.restoreFullSnapshot({
        'semesters': [
          {'id': 1, 'name': '2026-2', 'unknown_column': 'ignored'},
        ],
        'subjects': [
          {
            'id': 2,
            'semester_id': 1,
            'name': 'Química',
            'average_type': 'Aritmetico',
            'has_global_exam': 0,
            'global_exam_replaces_worst': 0,
            'min_passing_grade': 4.0,
            'order_index': 0,
            'evil_injection': 'DROP TABLE semesters',
          },
        ],
        'categories': [],
        'evaluations': [],
        'horario_clases': [],
      });

      final exported = await db.exportFullSnapshot();
      expect((exported['semesters'] as List).single['name'], '2026-2');
      expect((exported['subjects'] as List).single['name'], 'Química');
    });

    test('importDatabase rejects invalid files and rolls back incomplete schemas', () async {
      final db = DatabaseHelper.instance;
      await db.insertSemester({'name': 'Semestre Seguro'});

      // 1. Non-SQLite text file
      final textFile = File(p.join(tempDir.path, 'fake.db'));
      await textFile.writeAsString('not an sqlite file at all');
      await expectLater(
        () => db.importDatabase(textFile.path),
        throwsA(isA<Exception>()),
      );
      expect((await db.queryAllSemesters()).single['name'], 'Semestre Seguro');

      // 2. Valid SQLite header/file but missing required tables
      final incompletePath = p.join(tempDir.path, 'incomplete.db');
      final incompleteDb = await databaseFactory.openDatabase(
        incompletePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE only_one_table (id INTEGER PRIMARY KEY)');
          },
        ),
      );
      await incompleteDb.close();

      await expectLater(
        () => db.importDatabase(incompletePath),
        throwsA(isA<Exception>()),
      );

      // Verify automatic rollback preserved the original data
      final semestersAfterRollback = await db.queryAllSemesters();
      expect(semestersAfterRollback, hasLength(1));
      expect(semestersAfterRollback.single['name'], 'Semestre Seguro');
    });
  });
}
