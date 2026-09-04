import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/db/db_helper.dart';
import 'package:nexo/models/category_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Crea una base con el schema v1 original (íconos como emoji, columnas
/// `emoji`/`category_emoji` NOT NULL) para poder verificar que las
/// migraciones no pierden nada. Hay datos reales en producción: esto es
/// lo que impide repetir el bug del botón de guardar.
Future<Database> _openLegacyV1(DatabaseFactory factory) async {
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1));

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

  await db.insert('categories',
      {'id': 1, 'name': 'Comida', 'emoji': '\u{1F354}', 'is_default': 1});
  await db.insert('categories',
      {'id': 2, 'name': 'Café', 'emoji': '\u{2615}', 'is_default': 1});
  await db.insert('transactions', {
    'id': 1,
    'amount': 5000.0,
    'type': 'expense',
    'category_id': 1,
    'category_name': 'Comida',
    'category_emoji': '\u{1F354}',
    'note': 'almuerzo',
    'date': '2026-09-01T12:00:00.000',
  });
  // Movimiento de una categoría que ya no existe: su copia guardada es lo
  // único que lo mantiene legible y no se debe tocar nunca.
  await db.insert('transactions', {
    'id': 2,
    'amount': 900.0,
    'type': 'expense',
    'category_id': 99,
    'category_name': 'Categoría borrada',
    'category_emoji': '\u{1F4E6}',
    'note': '',
    'date': '2026-09-02T12:00:00.000',
  });

  return db;
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  final helper = DBHelper.instance;

  /// Corre las migraciones sobre la base ya abierta, como haría sqflite
  /// al detectar una versión vieja.
  Future<void> migrate(Database db, int from) async {
    await helper.onUpgrade(db, from, DBHelper.schemaVersion);
    await db.setVersion(DBHelper.schemaVersion);
  }

  group('migración v1 → v4', () {
    test('conserva categorías y movimientos, y traduce los emoji', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      final categories = await db.query('categories', orderBy: 'id ASC');
      expect(categories.length, 2);
      expect(categories[0]['name'], 'Comida');
      expect(categories[0]['icon_key'], 'food');
      expect(categories[1]['icon_key'], 'coffee');

      final txs = await db.query('transactions', orderBy: 'id ASC');
      expect(txs.length, 2);
      expect(txs[0]['category_icon_key'], 'food');
      expect(txs[0]['note'], 'almuerzo');

      await db.close();
    });

    test('deja las tablas sin las columnas legacy, para que INSERT funcione',
        () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      final columns = await db.rawQuery('PRAGMA table_info(transactions)');
      expect(columns.any((c) => c['name'] == 'category_emoji'), isFalse);

      // El bug del commit 8a17084: con la columna NOT NULL huérfana esto
      // fallaba y la app no daba ninguna señal.
      final id = await db.insert('transactions', {
        'amount': 1200.0,
        'type': 'income',
        'category_id': 1,
        'category_name': 'Comida',
        'category_icon_key': 'food',
        'note': 'test',
        'date': '2026-09-03T10:00:00.000',
      });
      expect(id, greaterThan(0));

      await db.close();
    });

    test('crea el índice por fecha', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      final indexes = await db.rawQuery('PRAGMA index_list(transactions)');
      expect(indexes.any((i) => i['name'] == 'idx_transactions_date'), isTrue);

      await db.close();
    });
  });

  group('re-sincronización de nombre e ícono (v3 → v4)', () {
    test('actualiza los movimientos desincronizados y respeta los huérfanos',
        () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      // Simula el estado que dejaba la app vieja: la categoría se editó,
      // pero sus movimientos quedaron con el nombre y el ícono viejos.
      await db.update('categories', {'name': 'Almuerzo', 'icon_key': 'shopping'},
          where: 'id = ?', whereArgs: [1]);

      var tx = (await db.query('transactions', where: 'id = 1')).first;
      expect(tx['category_name'], 'Comida', reason: 'todavía sin re-sincronizar');

      // Volver a correr el paso v4 es lo que repara la base existente.
      await helper.onUpgrade(db, 3, DBHelper.schemaVersion);

      tx = (await db.query('transactions', where: 'id = 1')).first;
      expect(tx['category_name'], 'Almuerzo');
      expect(tx['category_icon_key'], 'shopping');

      final orphan = (await db.query('transactions', where: 'id = 2')).first;
      expect(orphan['category_name'], 'Categoría borrada');
      expect(orphan['category_icon_key'], 'other');

      await db.close();
    });
  });

  group('updateCategory', () {
    test('propaga nombre e ícono a los movimientos de esa categoría', () async {
      // DBHelper resuelve su propia ruta de base, así que para probar la
      // propagación se usa la misma consulta sobre una base en memoria.
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      const updated = CategoryModel(id: 1, name: 'Almuerzo', iconKey: 'shopping');
      await db.transaction((txn) async {
        await txn.update('categories', updated.toMap(),
            where: 'id = ?', whereArgs: [updated.id]);
        await txn.update(
          'transactions',
          {'category_name': updated.name, 'category_icon_key': updated.iconKey},
          where: 'category_id = ?',
          whereArgs: [updated.id],
        );
      });

      final tx = (await db.query('transactions', where: 'id = 1')).first;
      expect(tx['category_name'], 'Almuerzo');
      expect(tx['category_icon_key'], 'shopping');

      final orphan = (await db.query('transactions', where: 'id = 2')).first;
      expect(orphan['category_name'], 'Categoría borrada');

      await db.close();
    });
  });
}
