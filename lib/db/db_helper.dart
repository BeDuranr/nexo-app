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

  /// Versión actual del schema. Todo cambio va por un paso nuevo de
  /// [_onUpgrade]: hay datos reales en producción, `_onCreate` solo
  /// describe cómo nace una instalación desde cero.
  static const int schemaVersion = 4;

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
      version: schemaVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

  /// Expuesto (junto con [onUpgrade]) para que los tests puedan abrir una
  /// base sintética con `sqflite_common_ffi` sin pasar por el filesystem
  /// del dispositivo.
  Future<void> onCreate(Database db, int version) async {
    // Nota: las categorías NO tienen un campo de tipo (gasto/ingreso).
    // Una misma categoría (ej. "Freelance") puede usarse para ambos
    // tipos de movimiento; el tipo se elige aparte en el toggle.
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon_key TEXT NOT NULL DEFAULT 'other',
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
        category_icon_key TEXT NOT NULL DEFAULT 'other',
        note TEXT,
        date TEXT NOT NULL
      )
    ''');

    await _createIndexes(db);
    await _seedDefaultCategories(db);
  }

  /// Migra instalaciones existentes sin perder categorías ni movimientos:
  /// v1→v2 pasó de emoji a `icon_key`, v2→v3 eliminó las columnas viejas
  /// que habían quedado NOT NULL, v3→v4 agrega los índices y re-sincroniza
  /// los datos denormalizados.
  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateEmojiToIconKey(db);
    }
    if (oldVersion < 3) {
      await _dropLegacyEmojiColumns(db);
    }
    if (oldVersion < 4) {
      await _createIndexes(db);
      await _resyncDenormalizedCategories(db);
    }
  }

  Future<void> _migrateEmojiToIconKey(Database db) async {
    await db.execute(
        "ALTER TABLE categories ADD COLUMN icon_key TEXT NOT NULL DEFAULT 'other'");
    await db.execute(
        "ALTER TABLE transactions ADD COLUMN category_icon_key TEXT NOT NULL DEFAULT 'other'");

    const emojiToIconKey = {
      '\u{1F687}': 'train',
      '\u{1F354}': 'food',
      '\u{2615}': 'coffee',
      '\u{1F3E0}': 'home',
      '\u{1F48A}': 'health',
      '\u{1F4BC}': 'briefcase',
      '\u{1F4BB}': 'laptop',
      '\u{1F4E6}': 'other',
    };

    for (final entry in emojiToIconKey.entries) {
      await db.update(
        'categories',
        {'icon_key': entry.value},
        where: 'emoji = ?',
        whereArgs: [entry.key],
      );
      await db.update(
        'transactions',
        {'category_icon_key': entry.value},
        where: 'category_emoji = ?',
        whereArgs: [entry.key],
      );
    }
  }

  /// La migración v1→v2 agregó `icon_key`/`category_icon_key` pero dejó
  /// las columnas viejas `emoji`/`category_emoji` con su restricción
  /// NOT NULL original (SQLite no permite quitar un NOT NULL con ALTER
  /// TABLE), lo que hacía fallar cualquier INSERT nuevo. Se reconstruyen
  /// ambas tablas sin esas columnas, preservando categorías y movimientos.
  Future<void> _dropLegacyEmojiColumns(Database db) async {
    final categoryColumns = await db.rawQuery('PRAGMA table_info(categories)');
    if (categoryColumns.any((c) => c['name'] == 'emoji')) {
      await db.execute('''
        CREATE TABLE categories_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon_key TEXT NOT NULL DEFAULT 'other',
          is_default INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        INSERT INTO categories_new (id, name, icon_key, is_default)
        SELECT id, name, icon_key, is_default FROM categories
      ''');
      await db.execute('DROP TABLE categories');
      await db.execute('ALTER TABLE categories_new RENAME TO categories');
    }

    final txColumns = await db.rawQuery('PRAGMA table_info(transactions)');
    if (txColumns.any((c) => c['name'] == 'category_emoji')) {
      await db.execute('''
        CREATE TABLE transactions_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount REAL NOT NULL,
          type TEXT NOT NULL,
          category_id INTEGER NOT NULL,
          category_name TEXT NOT NULL,
          category_icon_key TEXT NOT NULL DEFAULT 'other',
          note TEXT,
          date TEXT NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO transactions_new
          (id, amount, type, category_id, category_name, category_icon_key, note, date)
        SELECT id, amount, type, category_id, category_name, category_icon_key, note, date
        FROM transactions
      ''');
      await db.execute('DROP TABLE transactions');
      await db.execute('ALTER TABLE transactions_new RENAME TO transactions');
    }
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id)');
  }

  /// Hasta v3, editar una categoría no tocaba el nombre ni el ícono ya
  /// copiados en sus movimientos, así que las Métricas y la búsqueda del
  /// Historial mostraban datos viejos. Esto repara lo desincronizado.
  /// Los movimientos de categorías **eliminadas** quedan intactos: ahí la
  /// copia guardada es lo único que los mantiene legibles.
  Future<void> _resyncDenormalizedCategories(Database db) async {
    await db.execute('''
      UPDATE transactions
         SET category_name     = (SELECT name     FROM categories WHERE categories.id = transactions.category_id),
             category_icon_key = (SELECT icon_key FROM categories WHERE categories.id = transactions.category_id)
       WHERE category_id IN (SELECT id FROM categories)
    ''');
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final defaults = <CategoryModel>[
      const CategoryModel(name: 'Metro', iconKey: 'train', isDefault: true),
      const CategoryModel(name: 'Comida', iconKey: 'food', isDefault: true),
      const CategoryModel(name: 'Café', iconKey: 'coffee', isDefault: true),
      const CategoryModel(name: 'Hogar', iconKey: 'home', isDefault: true),
      const CategoryModel(name: 'Salud', iconKey: 'health', isDefault: true),
      const CategoryModel(name: 'Sueldo', iconKey: 'briefcase', isDefault: true),
      const CategoryModel(name: 'Freelance', iconKey: 'laptop', isDefault: true),
      const CategoryModel(name: 'Otros', iconKey: 'other', isDefault: true),
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

  /// Guarda la categoría y propaga el nombre y el ícono nuevos a los
  /// movimientos que la usan, en una sola transacción. Sin esto los
  /// movimientos viejos quedaban con la copia congelada y cada pantalla
  /// mostraba algo distinto.
  Future<int> updateCategory(CategoryModel category) async {
    final db = await database;
    return db.transaction((txn) async {
      final updated = await txn.update(
        'categories',
        category.toMap(),
        where: 'id = ?',
        whereArgs: [category.id],
      );
      await txn.update(
        'transactions',
        {'category_name': category.name, 'category_icon_key': category.iconKey},
        where: 'category_id = ?',
        whereArgs: [category.id],
      );
      return updated;
    });
  }

  /// Elimina la categoría de la lista. Los movimientos ya registrados se
  /// dejan como están: conservan el nombre y el ícono copiados, que es
  /// justamente para lo que existen esas columnas.
  Future<int> deleteCategory(int id) async {
    final db = await database;
    return db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Transacciones ----------

  Future<List<TransactionModel>> getTransactions() async {
    final db = await database;
    // El desempate por id mantiene un orden estable entre movimientos con
    // la misma marca de tiempo.
    final rows = await db.query('transactions', orderBy: 'date DESC, id DESC');
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
    return db.insert('transactions', tx.toMap());
  }
}
