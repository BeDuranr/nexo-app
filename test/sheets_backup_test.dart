import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexo/models/category_model.dart';
import 'package:nexo/models/transaction_model.dart';
import 'package:nexo/services/sheets_backup_service.dart';

/// El parseo de la planilla es la única parte del respaldo que puede
/// corromper datos reales: la restauración borra la base local y escribe
/// lo que salga de acá. Todo esto corre sin red y sin dispositivo.
final _service = SheetsBackupService();

/// Monto de un movimiento cuya celda llegó como el texto [raw].
double _amountFrom(String raw) {
  final rows = <List<dynamic>>[
    ['id', 'fecha', 'tipo', 'monto', 'categoria_id', 'categoria', 'icono', 'nota'],
    ['3', '2026-09-03T12:00:00.000', 'expense', raw, '1', 'Comida', 'food', ''],
  ];
  return _service.parseTransactions(rows).single.amount;
}

void main() {
  final service = _service;

  group('parseTransactions', () {
    test('lee una planilla tal como la escribe la app', () {
      final rows = <List<dynamic>>[
        ['id', 'fecha', 'tipo', 'monto', 'categoria_id', 'categoria', 'icono', 'nota'],
        [1, '2026-09-01T12:00:00.000', 'expense', 5000, 1, 'Comida', 'food', 'almuerzo'],
        [2, '2026-09-02T08:30:00.000', 'income', 350000.5, 6, 'Sueldo', 'briefcase', ''],
      ];

      final transactions = service.parseTransactions(rows);

      expect(transactions.length, 2);
      expect(transactions[0].id, 1);
      expect(transactions[0].amount, 5000);
      expect(transactions[0].type, MovementType.expense);
      expect(transactions[0].note, 'almuerzo');
      expect(transactions[1].type, MovementType.income);
      expect(transactions[1].amount, 350000.5);
      expect(transactions[1].date.hour, 8);
    });

    test('tolera filas en blanco y celdas finales ausentes', () {
      // Sheets recorta las celdas vacías del final de cada fila, así que
      // un movimiento sin nota llega con 7 columnas en vez de 8.
      final rows = <List<dynamic>>[
        ['id', 'fecha', 'tipo', 'monto', 'categoria_id', 'categoria', 'icono', 'nota'],
        [1, '2026-09-01T12:00:00.000', 'expense', 5000, 1, 'Comida', 'food'],
        <dynamic>[],
        ['', '', '', '', '', '', '', ''],
      ];

      final transactions = service.parseTransactions(rows);

      expect(transactions.length, 1);
      expect(transactions.single.note, '');
    });

    test('acepta un monto tipeado a mano con formato es-CL', () {
      // En pesos el punto agrupa miles, igual que en el campo de monto de
      // la app: "1.234" son mil doscientos treinta y cuatro.
      expect(_amountFrom('1.234'), 1234);
      expect(_amountFrom('1.234.567'), 1234567);
      expect(_amountFrom('1.234,5'), 1234.5);

      // Pero un decimal escrito con punto se respeta tal cual: tratarlo
      // como miles convertiría $1,5 en $15.
      expect(_amountFrom('1.5'), 1.5);
      expect(_amountFrom('5000'), 5000);
    });

    test('se niega si las columnas no son las esperadas', () {
      final rows = <List<dynamic>>[
        ['fecha', 'monto', 'tipo'],
        ['2026-09-01T12:00:00.000', 5000, 'expense'],
      ];

      // Restaurar con las columnas corridas escribiría basura en la base
      // real: mejor fallar y no tocar nada.
      expect(
        () => service.parseTransactions(rows),
        throwsA(isA<SheetsBackupException>()),
      );
    });

    test('se niega si una fecha o un monto quedaron ilegibles', () {
      final header = ['id', 'fecha', 'tipo', 'monto', 'categoria_id', 'categoria', 'icono', 'nota'];

      expect(
        () => service.parseTransactions(<List<dynamic>>[
          header,
          [1, 'ayer', 'expense', 5000, 1, 'Comida', 'food', ''],
        ]),
        throwsA(isA<SheetsBackupException>()),
      );

      expect(
        () => service.parseTransactions(<List<dynamic>>[
          header,
          [1, '2026-09-01T12:00:00.000', 'expense', 'mucho', 1, 'Comida', 'food', ''],
        ]),
        throwsA(isA<SheetsBackupException>()),
      );
    });

    test('una planilla vacía no es un error, es un respaldo sin datos', () {
      expect(service.parseTransactions(const []), isEmpty);
    });
  });

  group('formato 2 (en español)', () {
    const header = ['ID', 'Fecha', 'Tipo', 'Monto', 'ID categoría', 'Categoría', 'Ícono', 'Nota'];

    test('lee fechas como número de serie y tipos en español', () {
      final serial = SheetsBackupService.dateToSerial(DateTime(2026, 10, 19, 14, 32));
      final rows = <List<dynamic>>[
        header,
        [1, serial, 'Gasto', 5000, 1, 'Comida', 'food', ''],
        [2, serial, 'Ingreso', 350000, 6, 'Sueldo', 'briefcase', ''],
      ];

      final transactions = service.parseTransactions(rows);

      expect(transactions[0].type, MovementType.expense);
      expect(transactions[1].type, MovementType.income);
      expect(transactions[0].date, DateTime(2026, 10, 19, 14, 32));
    });

    test('el número de serie coincide con el de Sheets', () {
      // 45000 es el 15/03/2023 en Sheets; la hora va como fracción del día.
      expect(SheetsBackupService.dateToSerial(DateTime(2023, 3, 15)), 45000);
      expect(SheetsBackupService.dateToSerial(DateTime(2023, 3, 15, 18)), 45000.75);
    });

    test('ida y vuelta conserva la fecha al milisegundo', () {
      final dates = [
        DateTime(2026, 10, 19, 14, 32, 5, 123),
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31, 23, 59, 59, 999),
        // Cambio de horario en Chile: la celda no tiene zona horaria, así
        // que la hora local tiene que volver tal cual.
        DateTime(2026, 9, 6, 0, 30),
      ];
      for (final date in dates) {
        expect(
          SheetsBackupService.serialToDate(SheetsBackupService.dateToSerial(date)),
          date,
        );
      }
    });

    test('compara encabezados sin mayúsculas ni tildes', () {
      final rows = <List<dynamic>>[
        ['id', 'fecha', 'tipo', 'monto', 'id categoria', 'categoria', 'icono', 'nota'],
        [1, 45000, 'gasto', 5000, 1, 'Comida', 'food', ''],
      ];

      expect(service.parseTransactions(rows).single.type, MovementType.expense);
    });

    test('se niega si el tipo no es Gasto ni Ingreso', () {
      // Antes se leía como gasto: un "Ingresos" tipeado a mano habría
      // restado del saldo en vez de sumar.
      for (final type in ['Ingresos', '']) {
        expect(
          () => service.parseTransactions(<List<dynamic>>[
            header,
            [1, 45000, type, 5000, 1, 'Comida', 'food', ''],
          ]),
          throwsA(isA<SheetsBackupException>()),
        );
      }
    });

    test('lee "Sí" y "No" en las categorías', () {
      final rows = <List<dynamic>>[
        ['ID', 'Nombre', 'Ícono', 'Por defecto'],
        [1, 'Comida', 'food', 'Sí'],
        [2, 'Gatos', 'other', 'No'],
        [3, 'Varios', 'other', 'si'],
      ];

      expect(service.parseCategories(rows).map((c) => c.isDefault), [true, false, true]);
    });

    test('lo que sube la app se restaura idéntico', () async {
      final categories = [
        const CategoryModel(id: 1, name: 'Comida', iconKey: 'food', isDefault: true),
        const CategoryModel(id: 7, name: 'Freelance', iconKey: 'laptop'),
      ];
      final transactions = [
        TransactionModel(
          id: 1,
          amount: 15000,
          type: MovementType.expense,
          categoryId: 1,
          categoryName: 'Comida',
          categoryIconKey: 'food',
          note: 'almuerzo',
          date: DateTime(2026, 10, 19, 13, 5, 42, 250),
        ),
        TransactionModel(
          id: 2,
          amount: 420000,
          type: MovementType.income,
          categoryId: 7,
          categoryName: 'Freelance',
          categoryIconKey: 'laptop',
          note: '',
          date: DateTime(2026, 10, 1, 9),
        ),
      ];

      final fake = _FakeSheets();
      final sheets = SheetsBackupService(client: fake.client);

      await sheets.upload(
        token: 't',
        spreadsheetId: 's',
        categories: categories,
        transactions: transactions,
      );
      final snapshot = await sheets.download(token: 't', spreadsheetId: 's');

      expect(fake.tabs['movimientos']![1].sublist(2, 4), ['Gasto', 15000]);
      expect(
        snapshot.categories.map((c) => [c.id, c.name, c.iconKey, c.isDefault]),
        categories.map((c) => [c.id, c.name, c.iconKey, c.isDefault]),
      );
      expect(
        snapshot.transactions.map((t) => t.toMap()),
        transactions.map((t) => t.toMap()),
      );
    });
  });

  group('subida', () {
    TransactionModel tx(int id) => TransactionModel(
          id: id,
          amount: 1000,
          type: MovementType.expense,
          categoryId: 1,
          categoryName: 'Comida',
          categoryIconKey: 'food',
          note: '',
          date: DateTime(2026, 10, 19),
        );

    test('reemplaza las tres hojas en un solo batchUpdate, sin borrar antes', () async {
      // Si iOS suspende la app entre dos llamadas, ninguna hoja puede
      // quedar a medio escribir: los datos van todos en una sola, que
      // Google aplica entera o no aplica.
      final fake = _FakeSheets();
      await SheetsBackupService(client: fake.client).upload(
        token: 't',
        spreadsheetId: 's',
        categories: const [CategoryModel(id: 1, name: 'Comida', iconKey: 'food')],
        transactions: [tx(1), tx(2)],
      );

      expect(fake.requests.where((r) => r.url.path.endsWith(':clear')), isEmpty);
      final dataBatches = fake.batches.where((b) => b.any((r) => r.containsKey('updateCells')));
      expect(dataBatches.length, 1);
      expect(dataBatches.single.where((r) => r.containsKey('updateCells')).length, 3);
    });

    test('achica la grilla para no dejar filas viejas al final', () async {
      // Con menos movimientos que en el respaldo anterior, las filas
      // sobrantes se eliminan junto con la grilla en la misma operación.
      final fake = _FakeSheets();
      await SheetsBackupService(client: fake.client).upload(
        token: 't',
        spreadsheetId: 's',
        categories: const [],
        transactions: [tx(1)],
      );

      // Encabezado + 1 movimiento + la fila de margen.
      expect(fake.rowCounts['movimientos'], 3);
      expect(fake.columnCounts['movimientos'], 8);
    });

    test('vuelve a crear una hoja que se borró a mano', () async {
      final fake = _FakeSheets(titles: ['movimientos', 'info']);
      await SheetsBackupService(client: fake.client).upload(
        token: 't',
        spreadsheetId: 's',
        categories: const [CategoryModel(id: 1, name: 'Comida', iconKey: 'food')],
        transactions: [tx(1)],
      );

      expect(fake.tabs['categorias']![1], [1, 'Comida', 'food', 'No']);
    });

    test('un error al dar formato no hace fallar el respaldo', () async {
      final fake = _FakeSheets(failFormatting: true);
      await SheetsBackupService(client: fake.client).upload(
        token: 't',
        spreadsheetId: 's',
        categories: const [],
        transactions: [tx(1)],
      );

      expect(fake.tabs['movimientos']!.length, 2);
    });
  });

  group('parseCategories', () {
    test('conserva el id, que es lo que ata los movimientos a su categoría', () {
      final rows = <List<dynamic>>[
        ['id', 'nombre', 'icono', 'por_defecto'],
        [7, 'Freelance', 'laptop', 1],
        [8, 'Gatos', 'other', 0],
      ];

      final categories = service.parseCategories(rows);

      expect(categories.map((c) => c.id), [7, 8]);
      expect(categories[0].isDefault, isTrue);
      expect(categories[1].isDefault, isFalse);
      expect(categories[1].iconKey, 'other');
    });

    test('completa el ícono cuando la celda quedó vacía', () {
      final rows = <List<dynamic>>[
        ['id', 'nombre', 'icono', 'por_defecto'],
        [9, 'Varios', '', 0],
      ];

      expect(service.parseCategories(rows).single.iconKey, 'other');
    });

    test('ignora las filas sin nombre', () {
      final rows = <List<dynamic>>[
        ['id', 'nombre', 'icono', 'por_defecto'],
        [10, '', 'food', 0],
      ];

      expect(service.parseCategories(rows), isEmpty);
    });
  });
}

/// Sheets falso que entiende lo justo de la API: el `batchUpdate` con
/// que sube la app y el `values` con que lee al restaurar. Las celdas
/// vuelven como las devolvería `UNFORMATTED_VALUE`, con los vacíos del
/// final de cada fila recortados.
class _FakeSheets {
  _FakeSheets({
    List<String> titles = const ['movimientos', 'categorias', 'info'],
    this.failFormatting = false,
  }) {
    for (final title in titles) {
      _titles[_nextId++] = title;
    }
  }

  final bool failFormatting;
  final _titles = <int, String>{};
  var _nextId = 0;

  final tabs = <String, List<List<dynamic>>>{};
  final rowCounts = <String, int>{};
  final columnCounts = <String, int>{};
  final requests = <http.Request>[];
  final batches = <List<Map<String, dynamic>>>[];

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;

    if (request.method == 'GET' && path.contains('/values/')) {
      final tab = path.split('/values/').last;
      return http.Response(jsonEncode({'values': tabs[tab] ?? []}), 200);
    }
    if (request.method == 'GET') {
      return http.Response(
        jsonEncode({
          'sheets': [
            for (final e in _titles.entries)
              {
                'properties': {'sheetId': e.key, 'title': e.value},
              },
          ],
        }),
        200,
      );
    }
    if (path.endsWith(':batchUpdate')) {
      final batch = ((jsonDecode(request.body) as Map)['requests'] as List)
          .cast<Map<String, dynamic>>();
      batches.add(batch);
      if (failFormatting && batch.any((r) => r.containsKey('repeatCell'))) {
        return http.Response('{"error": {"message": "formato inválido"}}', 400);
      }
      return http.Response(jsonEncode({'replies': batch.map(_apply).toList()}), 200);
    }
    return http.Response('{}', 200);
  });

  Map<String, dynamic> _apply(Map<String, dynamic> request) {
    final add = request['addSheet'];
    if (add != null) {
      final id = _nextId++;
      final title = add['properties']['title'] as String;
      _titles[id] = title;
      return {
        'addSheet': {
          'properties': {'sheetId': id, 'title': title},
        },
      };
    }

    final props = request['updateSheetProperties']?['properties'];
    final grid = props?['gridProperties'];
    if (grid != null && grid['rowCount'] != null) {
      final title = _titles[props['sheetId']]!;
      rowCounts[title] = grid['rowCount'] as int;
      columnCounts[title] = grid['columnCount'] as int;
    }

    final update = request['updateCells'];
    if (update != null) {
      final title = _titles[update['start']['sheetId']]!;
      tabs[title] = [
        for (final row in update['rows'] as List)
          _trimTrailing([
            for (final cell in row['values'] as List)
              (cell['userEnteredValue'] as Map?)?.values.single,
          ]),
      ];
    }
    return {};
  }

  List<dynamic> _trimTrailing(List<dynamic> row) {
    var end = row.length;
    while (end > 0 && row[end - 1] == null) {
      end--;
    }
    return row.sublist(0, end);
  }
}
