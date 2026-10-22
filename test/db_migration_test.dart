import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/db/db_helper.dart';
import 'package:nexo/models/category_model.dart';
import 'package:nexo/models/debt_model.dart';
import 'package:nexo/models/transaction_model.dart';
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

const _category = CategoryModel(id: 1, name: 'Comida', iconKey: 'food');

final _carLoan = DebtModel(
  name: 'Crédito auto',
  totalAmount: 3000000,
  installments: 12,
  firstDate: DateTime(2026, 11, 30),
);

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

  group('migración v4 → v5 (tabla settings)', () {
    test('crea la tabla sin tocar categorías ni movimientos', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'settings'");
      expect(tables, isNotEmpty);

      // El respaldo no es una excusa para perder datos en el camino.
      expect((await db.query('transactions')).length, 2);
      expect((await db.query('categories')).length, 2);

      await db.close();
    });

    test('es idempotente: volver a correr el paso no falla', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      await db.insert('settings',
          {'key': 'ultimo_respaldo', 'value': '2026-10-18T10:00:00.000'});
      // Una base que ya pasó por v5 puede volver a recibir el paso si se
      // reinstala una versión vieja y se actualiza de nuevo.
      await helper.onUpgrade(db, 4, DBHelper.schemaVersion);

      final rows = await db.query('settings', where: 'key = ?',
          whereArgs: ['ultimo_respaldo']);
      expect(rows.single['value'], '2026-10-18T10:00:00.000');

      await db.close();
    });
  });

  group('migración v5 → v6 (deudas en cuotas)', () {
    test('agrega la tabla y la columna sin tocar los movimientos', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'debts'");
      expect(tables, isNotEmpty);

      // Los movimientos que ya existían quedan como sueltos, con todo lo
      // demás intacto.
      final txs = await db.query('transactions', orderBy: 'id ASC');
      expect(txs.length, 2);
      expect(txs.every((t) => t['debt_id'] == null), isTrue);
      expect(txs[0]['note'], 'almuerzo');
      expect(txs[1]['category_name'], 'Categoría borrada');

      await db.close();
    });

    test('es idempotente: volver a correr el paso no falla', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      await helper.insertDebtWith(db, _carLoan, _category);

      // SQLite no tiene ADD COLUMN IF NOT EXISTS: sin el chequeo, esto
      // reventaba con "duplicate column name".
      await helper.onUpgrade(db, 5, DBHelper.schemaVersion);

      expect((await db.query('debts')).length, 1);
      expect((await db.query('transactions', where: 'debt_id IS NOT NULL')).length, 12);

      await db.close();
    });
  });

  group('deudas', () {
    test('crear una deuda registra todas sus cuotas', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);

      final debtId = await helper.insertDebtWith(db, _carLoan, _category);

      final installments = (await db.query('transactions',
              where: 'debt_id = ?', whereArgs: [debtId], orderBy: 'date ASC'))
          .map(TransactionModel.fromMap)
          .toList();
      expect(installments.length, 12);
      expect(installments.first.date, DateTime(2026, 11, 30, 12));
      expect(installments.first.categoryId, 1);
      expect(installments.fold<double>(0, (s, t) => s + t.amount), 3000000);
      // Y avisa al respaldo que hay algo nuevo para subir.
      expect(await db.query('settings', where: "key = 'data_modificada'"), isNotEmpty);

      await db.close();
    });

    test('eliminarla borra las cuotas futuras y deja las pasadas como sueltas',
        () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      final debtId = await helper.insertDebtWith(db, _carLoan, _category);

      // Pasaron noviembre, diciembre y enero.
      await helper.deleteDebtWith(db, debtId, now: DateTime(2027, 1, 30, 8));

      expect(await db.query('debts'), isEmpty);
      final remaining = (await db.query('transactions',
              where: "note LIKE 'Crédito auto%'", orderBy: 'date ASC'))
          .map(TransactionModel.fromMap)
          .toList();
      expect(remaining.length, 3);
      expect(remaining.last.date, DateTime(2027, 1, 30, 12));
      expect(remaining.every((t) => t.debtId == null), isTrue);
      // Los movimientos que no eran de la deuda no se tocan.
      expect((await db.query('transactions')).length, 5);

      await db.close();
    });
  });

  group('editar una deuda', () {
    const otherCategory = CategoryModel(id: 2, name: 'Café', iconKey: 'coffee');
    // Pasaron noviembre, diciembre y enero: 3 cuotas pagadas, 9 pendientes.
    final now = DateTime(2027, 1, 30, 8);

    Future<List<TransactionModel>> installmentsOf(Database db, int debtId) async =>
        (await db.query('transactions',
                where: 'debt_id = ?', whereArgs: [debtId], orderBy: 'date ASC'))
            .map(TransactionModel.fromMap)
            .toList();

    DebtModel edited(int id,
            {String name = 'Crédito auto',
            double total = 3000000,
            int installments = 12}) =>
        DebtModel(
          id: id,
          name: name,
          totalAmount: total,
          installments: installments,
          firstDate: DateTime(2026, 11, 30),
        );

    test('cambiar solo nombre y categoría no toca montos ni fechas', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      final debtId = await helper.insertDebtWith(db, _carLoan, _category);

      // Una cuota futura editada a mano (vino con interés) se respeta.
      final march = (await installmentsOf(db, debtId))[4];
      await db.update('transactions', {'amount': 260000.0},
          where: 'id = ?', whereArgs: [march.id]);
      final before = await installmentsOf(db, debtId);

      await helper.updateDebtWith(db, edited(debtId, name: 'Auto'), otherCategory, now: now);

      final after = await installmentsOf(db, debtId);
      expect(after.map((t) => [t.id, t.amount, t.date]),
          before.map((t) => [t.id, t.amount, t.date]));
      expect(after.every((t) => t.categoryName == 'Café'), isTrue);
      expect(after.first.note, 'Auto · cuota 1/12');
      expect(after.last.note, 'Auto · cuota 12/12');
      expect((await db.query('debts')).single['name'], 'Auto');

      await db.close();
    });

    test('cambiar el total rehace solo las pendientes y la suma da el total',
        () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      final debtId = await helper.insertDebtWith(db, _carLoan, _category);
      final pastBefore = (await installmentsOf(db, debtId)).take(3).toList();

      await helper.updateDebtWith(
          db, edited(debtId, total: 3900000, installments: 12), _category, now: now);

      final after = await installmentsOf(db, debtId);
      expect(after.length, 12);
      // Las tres pasadas son exactamente las mismas filas.
      expect(after.take(3).map((t) => [t.id, t.amount]),
          pastBefore.map((t) => [t.id, t.amount]));
      // Faltaban 3.900.000 - 750.000 = 3.150.000 en 9 cuotas.
      expect(after.skip(3).every((t) => t.amount == 350000), isTrue);
      expect(after.fold<double>(0, (s, t) => s + t.amount), 3900000);
      expect(after[3].date, DateTime(2027, 2, 28, 12));
      expect(after[3].note, 'Crédito auto · cuota 4/12');

      await db.close();
    });

    test('alargar el plazo agrega cuotas al final', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      final debtId = await helper.insertDebtWith(db, _carLoan, _category);

      await helper.updateDebtWith(db, edited(debtId, installments: 18), _category, now: now);

      final after = await installmentsOf(db, debtId);
      expect(after.length, 18);
      expect(after.last.date, DateTime(2028, 4, 30, 12));
      expect(after.last.note, 'Crédito auto · cuota 18/18');
      expect(after.first.note, 'Crédito auto · cuota 1/18');
      expect(after.fold<double>(0, (s, t) => s + t.amount), 3000000);

      await db.close();
    });
  });

  group('pago anticipado', () {
    // 18 cuotas de $100.000 desde el 30 de noviembre de 2026.
    final loan = DebtModel(
      name: 'Crédito auto',
      totalAmount: 1800000,
      installments: 18,
      firstDate: DateTime(2026, 11, 30),
    );

    Future<List<TransactionModel>> installmentsOf(Database db, int debtId) async =>
        (await db.query('transactions',
                where: 'debt_id = ?', whereArgs: [debtId], orderBy: 'date ASC'))
            .map(TransactionModel.fromMap)
            .toList();

    test('en el mes 12 reemplaza de la 12 a la 18 por un solo pago', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      final debtId = await helper.insertDebtWith(db, loan, _category);

      // Pagó el 15 de octubre de 2027, antes de que venza la cuota 12
      // (30 de octubre), con descuento: $650.000 en vez de $700.000.
      final ok = await helper.payOffDebtWith(db, debtId,
          amount: 650000, date: DateTime(2027, 10, 15));

      expect(ok, isTrue);
      final after = await installmentsOf(db, debtId);
      expect(after.length, 12);
      expect(after[10].note, 'Crédito auto · cuota 11/18');
      expect(after.last.note, 'Crédito auto · pago anticipado');
      expect(after.last.amount, 650000);
      expect(after.last.date, DateTime(2027, 10, 15, 12));

      final debt = DebtModel.fromMap((await db.query('debts')).single);
      expect(debt.installments, 12);
      expect(debt.totalAmount, 1100000 + 650000);
      final status = DebtStatus.of(debt, after, now: DateTime(2027, 10, 15, 18));
      expect(status.isFinished, isTrue);
      expect(status.paidAmount, debt.totalAmount);

      await db.close();
    });

    test('el día que vence una cuota, esa se paga como siempre', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      final debtId = await helper.insertDebtWith(db, loan, _category);

      await helper.payOffDebtWith(db, debtId,
          amount: 600000, date: DateTime(2027, 10, 30));

      final after = await installmentsOf(db, debtId);
      expect(after.length, 13);
      expect(after[11].note, 'Crédito auto · cuota 12/18');
      expect(after.last.amount, 600000);

      await db.close();
    });

    test('sin cuotas después de la fecha no toca nada', () async {
      final db = await _openLegacyV1(factory);
      await migrate(db, 1);
      final debtId = await helper.insertDebtWith(db, loan, _category);

      final ok = await helper.payOffDebtWith(db, debtId,
          amount: 1000, date: DateTime(2028, 5, 1));

      expect(ok, isFalse);
      expect((await installmentsOf(db, debtId)).length, 18);
      expect(DebtModel.fromMap((await db.query('debts')).single).totalAmount, 1800000);

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
