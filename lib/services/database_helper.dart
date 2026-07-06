import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseHelper {
  static const _databaseName = "NotasDB.db";
  static const _databaseVersion = 5; // Incremented for horario_clases

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
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, _databaseName);
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
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
    }
  }

  // --- CRUD Semesters ---
  Future<int> insertSemester(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('semesters', row);
  }

  Future<List<Map<String, dynamic>>> queryAllSemesters() async {
    Database db = await instance.database;
    return await db.query('semesters');
  }

  Future<int> deleteSemester(int id) async {
    Database db = await instance.database;
    return await db.delete('semesters', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateSemester(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.update('semesters', row, where: 'id = ?', whereArgs: [row['id']]);
  }

  // --- CRUD Subjects ---
  Future<int> insertSubject(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('subjects', row);
  }

  Future<List<Map<String, dynamic>>> querySubjectsBySemester(int semesterId) async {
    Database db = await instance.database;
    return await db.query('subjects', where: 'semester_id = ?', whereArgs: [semesterId]);
  }

  Future<int> deleteSubject(int id) async {
    Database db = await instance.database;
    return await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateSubject(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.update('subjects', row, where: 'id = ?', whereArgs: [row['id']]);
  }

  // --- CRUD Categories ---
  Future<int> insertCategory(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('categories', row);
  }

  Future<List<Map<String, dynamic>>> queryCategoriesBySubject(int subjectId) async {
    Database db = await instance.database;
    return await db.query('categories', where: 'subject_id = ?', whereArgs: [subjectId]);
  }

  Future<int> deleteCategory(int id) async {
    Database db = await instance.database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateCategory(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.update('categories', row, where: 'id = ?', whereArgs: [row['id']]);
  }

  // --- CRUD Evaluations ---
  Future<int> insertEvaluation(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('evaluations', row);
  }

  Future<List<Map<String, dynamic>>> queryEvaluationsByCategory(int categoryId) async {
    Database db = await instance.database;
    return await db.query('evaluations', where: 'category_id = ?', whereArgs: [categoryId]);
  }
  
  Future<int> deleteEvaluation(int id) async {
    Database db = await instance.database;
    return await db.delete('evaluations', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateEvaluation(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.update('evaluations', row, where: 'id = ?', whereArgs: [row['id']]);
  }

  // --- CRUD Horarios ---
  Future<int> insertHorario(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert('horario_clases', row);
  }

  Future<List<Map<String, dynamic>>> queryHorariosBySemester(int semesterId) async {
    Database db = await instance.database;
    return await db.query('horario_clases', where: 'semester_id = ?', whereArgs: [semesterId]);
  }

  Future<int> deleteHorario(int id) async {
    Database db = await instance.database;
    return await db.delete('horario_clases', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateHorario(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.update('horario_clases', row, where: 'id = ?', whereArgs: [row['id']]);
  }
}
