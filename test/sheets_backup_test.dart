import 'package:flutter_test/flutter_test.dart';
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
