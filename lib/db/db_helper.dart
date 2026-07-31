import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/category_model.dart';
import '../models/transaction_model.dart';

/// Acceso centralizado a la base de datos SQLite local de Nexo.
/// Toda la información vive únicamente en el dispositivo: no hay red
/// ni cuentas involucradas.
class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'nexo.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Nota: las categorías NO tienen un campo de tipo (gasto/ingreso).
    // Una misma categoría (ej. "Freelance") puede usarse para ambos
    // tipos de movimiento; el tipo se elige aparte en el toggle.
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        category_emoji TEXT NOT NULL,
        note TEXT,
        date TEXT NOT NULL
      )
    ''');

    await _seedDefaultCategories(db);
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final defaults = <CategoryModel>[
      const CategoryModel(name: 'Metro', emoji: '🚇', isDefault: true),
      const CategoryModel(name: 'Comida', emoji: '🍔', isDefault: true),
      const CategoryModel(name: 'Café', emoji: '☕', isDefault: true),
      const CategoryModel(name: 'Hogar', emoji: '🏠', isDefault: true),
      const CategoryModel(name: 'Salud', emoji: '💊', isDefault: true),
      const CategoryModel(name: 'Sueldo', emoji: '💼', isDefault: true),
      const CategoryModel(name: 'Freelance', emoji: '💻', isDefault: true),
      const CategoryModel(name: 'Otros', emoji: '📦', isDefault: true),
    ];

    for (final cat in defaults) {
      await db.insert('categories', cat.toMap()..remove('id'));
    }
  }

  // ---------- Categorías ----------

  Future<List<CategoryModel>> getCategories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'id ASC');
    return rows.map(CategoryModel.fromMap).toList();
  }

  Future<int> insertCategory(CategoryModel category) async {
    final db = await database;
    return db.insert('categories', category.toMap()..remove('id'));
  }

  Future<int> updateCategory(CategoryModel category) async {
    final db = await database;
    return db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Transacciones ----------

  Future<List<TransactionModel>> getTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date DESC');
    return rows.map(TransactionModel.fromMap).toList();
  }

  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await database;
    return db.insert('transactions', tx.toMap()..remove('id'));
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateTransaction(TransactionModel tx) async {
    final db = await database;
    return db.update('transactions', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
  }

  /// Reinserta una transacción eliminada (usado por la función "Deshacer").
  Future<int> restoreTransaction(TransactionModel tx) async {
    final db = await database;
    final map = tx.toMap();
    return db.insert('transactions', map);
  }
}
