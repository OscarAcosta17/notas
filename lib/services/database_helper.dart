import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static const _databaseName = "NotasDB.db";
  static const _databaseVersion = 7;

  static const List<String> _requiredTables = [
    'semesters',
    'subjects',
    'categories',
    'evaluations',
    'horario_clases',
  ];

  static const Map<String, Set<String>> _tableColumns = {
    'semesters': {'id', 'name'},
    'subjects': {
      'id',
      'semester_id',
      'name',
      'average_type',
      'has_global_exam',
      'global_exam_replaces_worst',
      'min_passing_grade',
      'order_index',
      'color',
    },
    'categories': {
      'id',
      'subject_id',
      'name',
      'total_weight',
      'min_passing_grade',
      'average_type',
      'custom_formula',
      'drop_lowest',
    },
    'evaluations': {
      'id',
      'category_id',
      'name',
      'specific_weight',
      'grade',
      'date',
    },
    'horario_clases': {
      'id',
      'semester_id',
      'subject_name',
      'dia_semana',
      'bloque',
      'sala',
      'paralelo',
    },
  };

  static bool _ffiInitialized = false;
  static bool _suppressMutationHook = false;
  static VoidCallback? onDatabaseMutated;
  static String? _testDbPathOverride;

  static void ensureInitialized() {
    if (!_ffiInitialized && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
  }

  @visibleForTesting
  static Future<void> setDatabasePathOverrideForTest(String? path) async {
    await instance.closeForTest();
    _testDbPathOverride = path;
  }

  @visibleForTesting
  Future<void> closeForTest() async {
    if (_openingFuture != null) {
      try {
        await _openingFuture;
      } catch (_) {}
    }
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }
    _database = null;
    _openingFuture = null;
  }

  @visibleForTesting
  static Future<void> upgradeDatabaseForTest(
    Database db,
    int oldVersion,
    int newVersion,
  ) =>
      instance._onUpgrade(db, oldVersion, newVersion);

  // Singleton
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  static Future<Database>? _openingFuture;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _openingFuture ??= _initDatabase();
    try {
      _database = await _openingFuture!;
      return _database!;
    } finally {
      _openingFuture = null;
    }
  }

  Future<String> getDatabasePath() async {
    ensureInitialized();
    if (_testDbPathOverride != null) {
      return _testDbPathOverride!;
    }
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final appDir = Directory(join(documentsDirectory.path, 'NotasApp'));
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      return join(appDir.path, _databaseName);
    }
    return join(documentsDirectory.path, _databaseName);
  }

  Future<Database> _initDatabase() async {
    ensureInitialized();
    String path = await getDatabasePath();
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _onCreate(Database db, int version) async {
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
        min_passing_grade REAL NOT NULL DEFAULT 4.0,
        order_index INTEGER NOT NULL DEFAULT 0,
        color INTEGER,
        FOREIGN KEY(semester_id) REFERENCES semesters(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        total_weight REAL NOT NULL,
        min_passing_grade REAL,
        average_type TEXT NOT NULL DEFAULT 'Aritmetico',
        custom_formula TEXT,
        drop_lowest INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(subject_id) REFERENCES subjects(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE evaluations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        specific_weight REAL,
        grade REAL,
        date TEXT,
        FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE horario_clases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        semester_id INTEGER NOT NULL,
        subject_name TEXT NOT NULL,
        dia_semana INTEGER NOT NULL,
        bloque INTEGER NOT NULL,
        sala TEXT NOT NULL,
        paralelo TEXT NOT NULL,
        FOREIGN KEY(semester_id) REFERENCES semesters(id) ON DELETE CASCADE
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS horario_clases');
      await db.execute('DROP TABLE IF EXISTS evaluations');
      await db.execute('DROP TABLE IF EXISTS categories');
      await db.execute('DROP TABLE IF EXISTS subjects');
      await db.execute('DROP TABLE IF EXISTS semesters');
      await _onCreate(db, newVersion);
      return;
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE evaluations ADD COLUMN date TEXT');
      } catch (_) {}
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS horario_clases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          semester_id INTEGER NOT NULL,
          subject_name TEXT NOT NULL,
          dia_semana INTEGER NOT NULL,
          bloque INTEGER NOT NULL,
          sala TEXT NOT NULL,
          paralelo TEXT NOT NULL,
          FOREIGN KEY(semester_id) REFERENCES semesters(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 6) {
      try {
        await db.execute(
          'ALTER TABLE subjects ADD COLUMN order_index INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }

    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE subjects ADD COLUMN color INTEGER');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE categories ADD COLUMN average_type TEXT NOT NULL DEFAULT "Aritmetico"',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN custom_formula TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE categories ADD COLUMN drop_lowest INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
  }

  void _notifyMutated() {
    if (!_suppressMutationHook) {
      onDatabaseMutated?.call();
    }
  }

  // --- CRUD Semesters ---
  Future<int> insertSemester(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final id = await db.insert('semesters', row);
    _notifyMutated();
    return id;
  }

  Future<List<Map<String, dynamic>>> queryAllSemesters() async {
    Database db = await instance.database;
    return await db.query('semesters');
  }

  Future<int> deleteSemester(int id) async {
    Database db = await instance.database;
    final count = await db.delete('semesters', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateSemester(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count =
        await db.update('semesters', row, where: 'id = ?', whereArgs: [row['id']]);
    _notifyMutated();
    return count;
  }

  // --- CRUD Subjects ---
  Future<int> insertSubject(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final id = await db.insert('subjects', row);
    _notifyMutated();
    return id;
  }

  Future<List<Map<String, dynamic>>> querySubjectsBySemester(int semesterId) async {
    Database db = await instance.database;
    return await db.query(
      'subjects',
      where: 'semester_id = ?',
      whereArgs: [semesterId],
      orderBy: 'order_index ASC, id ASC',
    );
  }

  Future<int> deleteSubject(int id) async {
    Database db = await instance.database;
    final count = await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateSubject(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count =
        await db.update('subjects', row, where: 'id = ?', whereArgs: [row['id']]);
    _notifyMutated();
    return count;
  }

  Future<void> updateSubjectOrders(List<({int id, int orderIndex})> orders) async {
    if (orders.isEmpty) return;
    final db = await instance.database;
    await db.transaction((txn) async {
      for (final entry in orders) {
        await txn.update(
          'subjects',
          {'order_index': entry.orderIndex},
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
    });
    _notifyMutated();
  }

  // --- CRUD Categories ---
  Future<int> insertCategory(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final id = await db.insert('categories', row);
    _notifyMutated();
    return id;
  }

  Future<int> insertCategoryWithEvaluations(
    Map<String, dynamic> categoryRow,
    List<Map<String, dynamic>> evaluationRows,
  ) async {
    final db = await instance.database;
    final idCategoria = await db.transaction((txn) async {
      final catId = await txn.insert('categories', categoryRow);
      for (final evRow in evaluationRows) {
        final copy = Map<String, dynamic>.from(evRow);
        copy['category_id'] = catId;
        await txn.insert('evaluations', copy);
      }
      return catId;
    });
    _notifyMutated();
    return idCategoria;
  }

  Future<List<Map<String, dynamic>>> queryCategoriesBySubject(int subjectId) async {
    Database db = await instance.database;
    return await db.query('categories', where: 'subject_id = ?', whereArgs: [subjectId]);
  }

  Future<List<({Map<String, dynamic> category, List<Map<String, dynamic>> evaluations})>>
      queryCategoriesWithEvaluationsBySubject(int subjectId) async {
    final db = await instance.database;
    final categories = await db.query(
      'categories',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'id ASC',
    );
    if (categories.isEmpty) return [];

    final catIds = categories.map((c) => c['id']).whereType<int>().toList();
    final grouped = <int, List<Map<String, dynamic>>>{};
    if (catIds.isNotEmpty) {
      final placeholders = List.filled(catIds.length, '?').join(',');
      final evRows = await db.rawQuery(
        'SELECT * FROM evaluations WHERE category_id IN ($placeholders) ORDER BY id ASC',
        catIds,
      );
      for (final ev in evRows) {
        final cid = ev['category_id'] as int?;
        if (cid != null) {
          grouped.putIfAbsent(cid, () => []).add(ev);
        }
      }
    }

    return [
      for (final cat in categories)
        (
          category: cat,
          evaluations: grouped[cat['id']] ?? const <Map<String, dynamic>>[],
        ),
    ];
  }

  Future<int> deleteCategory(int id) async {
    Database db = await instance.database;
    final count = await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateCategory(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count =
        await db.update('categories', row, where: 'id = ?', whereArgs: [row['id']]);
    _notifyMutated();
    return count;
  }

  // --- CRUD Evaluations ---
  Future<int> insertEvaluation(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final id = await db.insert('evaluations', row);
    _notifyMutated();
    return id;
  }

  Future<List<Map<String, dynamic>>> queryEvaluationsByCategory(int categoryId) async {
    Database db = await instance.database;
    return await db.query('evaluations', where: 'category_id = ?', whereArgs: [categoryId]);
  }

  Future<List<Map<String, dynamic>>> queryAllScheduledEvaluationsWithSubject() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT e.*, s.name AS subject_name, c.subject_id AS subject_id
      FROM evaluations e
      INNER JOIN categories c ON c.id = e.category_id
      INNER JOIN subjects s ON s.id = c.subject_id
      WHERE e.date IS NOT NULL AND e.date != ''
      ORDER BY e.date ASC
    ''');
  }

  Future<int> deleteEvaluation(int id) async {
    Database db = await instance.database;
    final count = await db.delete('evaluations', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateEvaluation(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count =
        await db.update('evaluations', row, where: 'id = ?', whereArgs: [row['id']]);
    _notifyMutated();
    return count;
  }

  // --- CRUD Horarios ---
  Future<int> insertHorario(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final id = await db.insert('horario_clases', row);
    _notifyMutated();
    return id;
  }

  Future<List<Map<String, dynamic>>> queryHorariosBySemester(int semesterId) async {
    Database db = await instance.database;
    return await db.query(
      'horario_clases',
      where: 'semester_id = ?',
      whereArgs: [semesterId],
    );
  }

  Future<int> deleteHorario(int id) async {
    Database db = await instance.database;
    final count = await db.delete('horario_clases', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateHorario(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count = await db.update(
      'horario_clases',
      row,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    _notifyMutated();
    return count;
  }

  // --- Backup, Snapshot Sync and Restore ---
  Future<Map<String, dynamic>> exportFullSnapshot() async {
    final db = await database;
    final semesters = await db.query('semesters', orderBy: 'id ASC');
    final subjects = await db.query('subjects', orderBy: 'id ASC');
    final categories = await db.query('categories', orderBy: 'id ASC');
    final evaluations = await db.query('evaluations', orderBy: 'id ASC');
    final horarioClases = await db.query('horario_clases', orderBy: 'id ASC');

    return {
      'schemaVersion': _databaseVersion,
      'semesters': semesters,
      'subjects': subjects,
      'categories': categories,
      'evaluations': evaluations,
      'horario_clases': horarioClases,
    };
  }

  Future<void> restoreFullSnapshot(Map<String, dynamic> data) async {
    final db = await database;
    _suppressMutationHook = true;
    try {
      await db.transaction((txn) async {
        await txn.delete('horario_clases');
        await txn.delete('evaluations');
        await txn.delete('categories');
        await txn.delete('subjects');
        await txn.delete('semesters');

        Future<void> insertRows(String table, dynamic rawRows) async {
          if (rawRows is! List) return;
          final allowed = _tableColumns[table]!;
          for (final row in rawRows) {
            if (row is Map) {
              final filtered = <String, dynamic>{};
              row.forEach((key, value) {
                final k = key.toString();
                if (allowed.contains(k)) {
                  filtered[k] = value;
                }
              });
              if (filtered.isNotEmpty) {
                await txn.insert(table, filtered);
              }
            }
          }
        }

        await insertRows('semesters', data['semesters']);
        await insertRows('subjects', data['subjects']);
        await insertRows('categories', data['categories']);
        await insertRows('evaluations', data['evaluations']);
        await insertRows('horario_clases', data['horario_clases']);
      });
    } finally {
      _suppressMutationHook = false;
    }
  }

  Future<String> exportDatabase() async {
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception("No hay base de datos para exportar.");
    }

    Directory docs = await getApplicationDocumentsDirectory();
    final backupPath = join(docs.path, 'NotasDB_backup.db');

    await dbFile.copy(backupPath);
    return backupPath;
  }

  static Future<bool> _hasValidSqliteHeader(File file) async {
    if (!await file.exists()) return false;
    final len = await file.length();
    if (len < 16) return false;
    final raf = await file.open();
    try {
      final header = await raf.read(16);
      const magic = [
        0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
      ];
      if (header.length < 16) return false;
      for (var i = 0; i < 16; i++) {
        if (header[i] != magic[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  Future<void> importDatabase(String sourcePath) async {
    final backupFile = File(sourcePath);

    if (!await backupFile.exists()) {
      throw Exception("No se encontró el archivo seleccionado.");
    }
    if (!await _hasValidSqliteHeader(backupFile)) {
      throw Exception("El archivo seleccionado no es una base de datos SQLite válida.");
    }

    final dbPath = await getDatabasePath();
    final currentFile = File(dbPath);
    final rollbackFile = File('$dbPath.bak');

    await closeForTest();

    if (await currentFile.exists()) {
      await currentFile.copy(rollbackFile.path);
    }

    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('$dbPath$suffix');
      if (await sidecar.exists()) {
        await sidecar.delete();
      }
    }

    try {
      await backupFile.copy(dbPath);
      final rawInspect = await databaseFactory.openDatabase(dbPath);
      Set<String> preUpgradeTables;
      try {
        final rawRows = await rawInspect.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        );
        preUpgradeTables = rawRows
            .map((r) => r['name']?.toString() ?? '')
            .toSet();
      } finally {
        await rawInspect.close();
      }
      for (final coreTable in const [
        'semesters',
        'subjects',
        'categories',
        'evaluations',
      ]) {
        if (!preUpgradeTables.contains(coreTable)) {
          throw Exception(
            'La base de datos importada no contiene la tabla requerida "$coreTable".',
          );
        }
      }

      final reopened = await database;
      final tablesRows = await reopened.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final existingTables = tablesRows
          .map((r) => r['name']?.toString() ?? '')
          .toSet();
      for (final req in _requiredTables) {
        if (!existingTables.contains(req)) {
          throw Exception(
            'La base de datos importada no contiene la tabla requerida "$req".',
          );
        }
      }
      if (await rollbackFile.exists()) {
        await rollbackFile.delete();
      }
      _notifyMutated();
    } catch (e) {
      await closeForTest();
      if (await rollbackFile.exists()) {
        await rollbackFile.copy(dbPath);
        await rollbackFile.delete();
        await database;
      }
      rethrow;
    }
  }
}
