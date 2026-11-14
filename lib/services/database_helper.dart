import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static const _databaseName = "NotasDB.db";
  static const _databaseVersion = 7; // Incremented for visual/math features

  static bool _ffiInitialized = false;
  static bool _suppressMutationHook = false;
  static VoidCallback? onDatabaseMutated;

  static void ensureInitialized() {
    if (!_ffiInitialized && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
  }

  // Singleton
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<String> getDatabasePath() async {
    ensureInitialized();
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
      await db.execute('DROP TABLE IF EXISTS evaluations');
      await db.execute('DROP TABLE IF EXISTS categories');
      await db.execute('DROP TABLE IF EXISTS subjects');
      await db.execute('DROP TABLE IF EXISTS semesters');
      await _onCreate(db, newVersion);
    } else if (oldVersion == 3) {
      await db.execute('ALTER TABLE evaluations ADD COLUMN date TEXT');
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
    } else if (oldVersion == 4) {
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
    } else if (oldVersion == 5) {
      await db.execute('ALTER TABLE subjects ADD COLUMN order_index INTEGER NOT NULL DEFAULT 0');
    }

    if (oldVersion < 7) {
      if (oldVersion >= 6) { // If it's jumping from older than 6, we still need to add color but handle properly. We'll just run it safely if it exists by ignoring error or just letting it run since oldVersion < 7.
        // Wait, version 6 added order_index.
      }
      try { await db.execute('ALTER TABLE subjects ADD COLUMN color INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN average_type TEXT NOT NULL DEFAULT "Aritmetico"'); } catch (_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN custom_formula TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN drop_lowest INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
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
    final count = await db.update('semesters', row, where: 'id = ?', whereArgs: [row['id']]);
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
    return await db.query('subjects', where: 'semester_id = ?', whereArgs: [semesterId], orderBy: 'order_index ASC, id ASC');
  }

  Future<int> deleteSubject(int id) async {
    Database db = await instance.database;
    final count = await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateSubject(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count = await db.update('subjects', row, where: 'id = ?', whereArgs: [row['id']]);
    _notifyMutated();
    return count;
  }

  // --- CRUD Categories ---
  Future<int> insertCategory(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final id = await db.insert('categories', row);
    _notifyMutated();
    return id;
  }

  Future<List<Map<String, dynamic>>> queryCategoriesBySubject(int subjectId) async {
    Database db = await instance.database;
    return await db.query('categories', where: 'subject_id = ?', whereArgs: [subjectId]);
  }

  Future<int> deleteCategory(int id) async {
    Database db = await instance.database;
    final count = await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateCategory(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count = await db.update('categories', row, where: 'id = ?', whereArgs: [row['id']]);
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

  Future<int> deleteEvaluation(int id) async {
    Database db = await instance.database;
    final count = await db.delete('evaluations', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateEvaluation(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count = await db.update('evaluations', row, where: 'id = ?', whereArgs: [row['id']]);
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
    return await db.query('horario_clases', where: 'semester_id = ?', whereArgs: [semesterId]);
  }

  Future<int> deleteHorario(int id) async {
    Database db = await instance.database;
    final count = await db.delete('horario_clases', where: 'id = ?', whereArgs: [id]);
    _notifyMutated();
    return count;
  }

  Future<int> updateHorario(Map<String, dynamic> row) async {
    Database db = await instance.database;
    final count = await db.update('horario_clases', row, where: 'id = ?', whereArgs: [row['id']]);
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
          for (final row in rawRows) {
            if (row is Map) {
              await txn.insert(table, Map<String, dynamic>.from(row));
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
    
    // Guardar en la carpeta de documentos de la aplicación, simulando Descargas por simplicidad de permisos.
    // En una app real de Android 11+ se usaría SAF o un directorio público de Descargas, pero requeriría más permisos.
    Directory docs = await getApplicationDocumentsDirectory();
    final backupPath = join(docs.path, 'NotasDB_backup.db');
    
    await dbFile.copy(backupPath);
    return backupPath;
  }

  Future<void> importDatabase(String sourcePath) async {
    final backupFile = File(sourcePath);
    
    if (!await backupFile.exists()) {
      throw Exception("No se encontró el archivo seleccionado.");
    }
    
    // Cerrar BD actual
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
    
    final dbPath = await getDatabasePath();
    await backupFile.copy(dbPath);
    
    // Reabrir
    await database; 
  }
}
