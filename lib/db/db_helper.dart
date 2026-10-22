import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/category_model.dart';
import '../models/debt_model.dart';
import '../models/transaction_model.dart';

/// Acceso centralizado a la base de datos SQLite local de Nexo.
///
/// SQLite sigue siendo la única fuente de verdad: la app funciona
/// completa sin cuenta y sin red. El respaldo en Google Sheets
/// (`services/sheets_backup_service.dart`) lee de acá y escribe acá al
/// restaurar, pero nunca es quien manda.
class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  /// Versión actual del schema. Todo cambio va por un paso nuevo de
  /// [_onUpgrade]: hay datos reales en producción, `_onCreate` solo
  /// describe cómo nace una instalación desde cero.
  static const int schemaVersion = 6;

  /// Marca de tiempo de la última escritura a categorías o movimientos.
  /// Comparada contra [settingLastBackup] dice si hay cambios sin
  /// respaldar, y sobrevive a que se cierre la app.
  static const String settingDataChangedAt = 'data_modificada';

  /// Marca de tiempo del último respaldo subido con éxito.
  static const String settingLastBackup = 'ultimo_respaldo';

  /// Id de la planilla de respaldo en Drive. Es solo una caché: si falta,
  /// la planilla se reencuentra por su `appProperties` en Drive.
  static const String settingSpreadsheetId = 'respaldo_spreadsheet_id';

  /// Mail de la cuenta de Google conectada, para mostrarlo en Ajustes.
  static const String settingGoogleAccount = 'cuenta_google';

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
    await _createSettingsTable(db);
    await _createDebts(db);
    await _seedDefaultCategories(db);
  }

  /// Migra instalaciones existentes sin perder categorías ni movimientos:
  /// v1→v2 pasó de emoji a `icon_key`, v2→v3 eliminó las columnas viejas
  /// que habían quedado NOT NULL, v3→v4 agrega los índices y re-sincroniza
  /// los datos denormalizados, v4→v5 agrega la tabla `settings`, v5→v6
  /// agrega las deudas en cuotas.
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
    if (oldVersion < 5) {
      await _createSettingsTable(db);
    }
    if (oldVersion < 6) {
      await _createDebts(db);
    }
  }

  /// Tabla `debts` y columna `transactions.debt_id`, que ata cada cuota a
  /// su deuda. La columna admite null y no reescribe ninguna fila: los
  /// movimientos que ya existen quedan tal cual, como movimientos sueltos.
  ///
  /// Es idempotente porque SQLite no tiene `ADD COLUMN IF NOT EXISTS`: el
  /// paso puede volver a correr si se reinstala una versión vieja encima.
  Future<void> _createDebts(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        total_amount REAL NOT NULL,
        installments INTEGER NOT NULL,
        first_date TEXT NOT NULL
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info(transactions)');
    if (!columns.any((c) => c['name'] == 'debt_id')) {
      await db.execute('ALTER TABLE transactions ADD COLUMN debt_id INTEGER');
    }
  }

  /// Clave/valor para lo que no son datos del usuario: la cuenta de Google
  /// conectada y el estado del respaldo. Va en SQLite y no en
  /// `shared_preferences` para no sumar una dependencia ni un segundo
  /// lugar donde buscar el estado de la app.
  Future<void> _createSettingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
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

  // ---------- Preferencias (tabla `settings`) ----------

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<DateTime?> getSettingAsDate(String key) async {
    final raw = await getSetting(key);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Anota que los datos del usuario cambiaron. Lo llama cada escritura a
  /// categorías o movimientos: es lo que le permite al respaldo saber que
  /// tiene algo nuevo que subir sin que las pantallas tengan que avisarle.
  Future<void> _touch(DatabaseExecutor db) async {
    await db.insert(
      'settings',
      {
        'key': settingDataChangedAt,
        'value': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- Categorías ----------

  Future<List<CategoryModel>> getCategories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'id ASC');
    return rows.map(CategoryModel.fromMap).toList();
  }

  Future<int> insertCategory(CategoryModel category) async {
    final db = await database;
    final id = await db.insert('categories', category.toMap()..remove('id'));
    await _touch(db);
    return id;
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
      await _touch(txn);
      return updated;
    });
  }

  /// Elimina la categoría de la lista. Los movimientos ya registrados se
  /// dejan como están: conservan el nombre y el ícono copiados, que es
  /// justamente para lo que existen esas columnas.
  Future<int> deleteCategory(int id) async {
    final db = await database;
    final deleted =
        await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    await _touch(db);
    return deleted;
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
    final id = await db.insert('transactions', tx.toMap()..remove('id'));
    await _touch(db);
    return id;
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    final deleted =
        await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await _touch(db);
    return deleted;
  }

  Future<int> updateTransaction(TransactionModel tx) async {
    final db = await database;
    final updated = await db
        .update('transactions', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
    await _touch(db);
    return updated;
  }

  /// Reinserta una transacción eliminada (usado por la función "Deshacer").
  Future<int> restoreTransaction(TransactionModel tx) async {
    final db = await database;
    final id = await db.insert('transactions', tx.toMap());
    await _touch(db);
    return id;
  }

  // ---------- Deudas en cuotas ----------

  Future<List<DebtModel>> getDebts() async {
    final db = await database;
    final rows = await db.query('debts', orderBy: 'first_date ASC, id ASC');
    return rows.map(DebtModel.fromMap).toList();
  }

  /// Crea la deuda y registra todas sus cuotas como gastos con fecha
  /// futura, en una sola transacción: nunca queda una deuda a medias.
  Future<int> insertDebt(DebtModel debt, CategoryModel category) async {
    final db = await database;
    return db.transaction((txn) => insertDebtWith(txn, debt, category));
  }

  /// Cuerpo de [insertDebt], expuesto para que los tests lo corran sobre
  /// una base en memoria (DBHelper resuelve su propia ruta de base).
  Future<int> insertDebtWith(
      DatabaseExecutor txn, DebtModel debt, CategoryModel category) async {
    final debtId = await txn.insert('debts', debt.toMap()..remove('id'));
    for (final tx in debt.buildInstallments(debtId: debtId, category: category)) {
      await txn.insert('transactions', tx.toMap()..remove('id'));
    }
    await _touch(txn);
    return debtId;
  }

  /// Guarda la deuda editada. Las cuotas que ya pasaron no se tocan, salvo
  /// el nombre y la categoría: esa plata ya se gastó. Las pendientes se
  /// regeneran si cambió el calendario o el monto (ver
  /// `DebtModel.rebuildPending`); si no, solo se renombran y se les cambia
  /// la categoría, respetando un monto editado a mano.
  Future<void> updateDebt(DebtModel updated, CategoryModel category,
      {required DateTime now}) async {
    final db = await database;
    await db.transaction((txn) => updateDebtWith(txn, updated, category, now: now));
  }

  /// Cuerpo de [updateDebt], expuesto para los tests.
  Future<void> updateDebtWith(
      DatabaseExecutor txn, DebtModel updated, CategoryModel category,
      {required DateTime now}) async {
    final id = updated.id!;
    final oldRows = await txn.query('debts', where: 'id = ?', whereArgs: [id]);
    if (oldRows.isEmpty) return;
    final old = DebtModel.fromMap(oldRows.first);

    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final installments = (await txn.query('transactions',
            where: 'debt_id = ?', whereArgs: [id], orderBy: 'date ASC, id ASC'))
        .map(TransactionModel.fromMap)
        .toList();
    final past = installments.where((t) => !t.date.isAfter(endOfToday)).toList();
    final pending = installments.where((t) => t.date.isAfter(endOfToday)).toList();

    await txn.update('debts', updated.toMap(), where: 'id = ?', whereArgs: [id]);

    final categoryFields = {
      'category_id': category.id,
      'category_name': category.name,
      'category_icon_key': category.iconKey,
    };

    // Las pasadas: misma plata y misma fecha, solo nombre y categoría.
    for (var i = 0; i < past.length; i++) {
      await txn.update(
        'transactions',
        {
          ...categoryFields,
          if (old.isAutoNote(past[i].note)) 'note': updated.installmentNote(i + 1),
        },
        where: 'id = ?',
        whereArgs: [past[i].id],
      );
    }

    if (updated.scheduleDiffers(old)) {
      for (final t in pending) {
        await txn.delete('transactions', where: 'id = ?', whereArgs: [t.id]);
      }
      final paid = past.fold<double>(0, (sum, t) => sum + t.amount);
      final rebuilt = updated.rebuildPending(
          debtId: id, category: category, paidAmount: paid, now: now);
      for (final t in rebuilt) {
        await txn.insert('transactions', t.toMap()..remove('id'));
      }
    } else {
      for (var i = 0; i < pending.length; i++) {
        await txn.update(
          'transactions',
          {
            ...categoryFields,
            if (old.isAutoNote(pending[i].note))
              'note': updated.installmentNote(past.length + i + 1),
          },
          where: 'id = ?',
          whereArgs: [pending[i].id],
        );
      }
    }

    await _touch(txn);
  }

  /// Elimina la deuda y sus cuotas **futuras**. Las que ya pasaron se
  /// quedan en el Historial como gastos sueltos: esa plata ya se gastó, y
  /// borrarlas cambiaría los saldos de meses cerrados.
  Future<void> deleteDebt(int id, {required DateTime now}) async {
    final db = await database;
    await db.transaction((txn) => deleteDebtWith(txn, id, now: now));
  }

  /// Cuerpo de [deleteDebt], expuesto para los tests.
  Future<void> deleteDebtWith(DatabaseExecutor txn, int id,
      {required DateTime now}) async {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    // Las fechas son ISO 8601 locales, así que comparar texto es
    // comparar fechas.
    await txn.delete('transactions',
        where: 'debt_id = ? AND date > ?',
        whereArgs: [id, endOfToday.toIso8601String()]);
    await txn.update('transactions', {'debt_id': null},
        where: 'debt_id = ?', whereArgs: [id]);
    await txn.delete('debts', where: 'id = ?', whereArgs: [id]);
    await _touch(txn);
  }

  // ---------- Restauración desde un respaldo ----------

  /// Reemplaza **todas** las categorías y movimientos por los del
  /// respaldo, en una sola transacción: si algo falla a mitad de camino,
  /// la base queda como estaba.
  ///
  /// Las categorías se reinsertan **con su id original** a propósito:
  /// `transactions.category_id` apunta a ellas, y dejar que SQLite
  /// reasigne los ids haría que los movimientos restaurados terminen
  /// colgados de la categoría equivocada.
  ///
  /// Lo mismo vale para las deudas. Un respaldo anterior al formato 3 no
  /// trae deudas, y una cuota que apunte a una deuda que no vino se
  /// restaura como gasto suelto en vez de quedar colgando de un id que no
  /// existe.
  Future<void> replaceAllData({
    required List<CategoryModel> categories,
    required List<TransactionModel> transactions,
    List<DebtModel> debts = const [],
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('categories');
      await txn.delete('debts');

      for (final category in categories) {
        await txn.insert('categories', category.toMap());
      }
      for (final debt in debts) {
        await txn.insert('debts', debt.toMap());
      }
      final debtIds = debts.map((d) => d.id).toSet();
      for (final tx in transactions) {
        final map = tx.toMap();
        if (!debtIds.contains(tx.debtId)) map['debt_id'] = null;
        await txn.insert('transactions', map);
      }

      await _touch(txn);
    });
  }
}
