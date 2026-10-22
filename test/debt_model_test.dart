import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/models/category_model.dart';
import 'package:nexo/models/debt_model.dart';
import 'package:nexo/models/transaction_model.dart';

/// Las cuotas se insertan todas de una vez al crear la deuda: un error en
/// las fechas o los montos queda escrito en doce meses del Historial.
void main() {
  const category = CategoryModel(id: 3, name: 'Auto', iconKey: 'car');

  // El caso que pidió el usuario: crédito del auto, 12 cuotas el día 30,
  // la primera el 30 de noviembre de 2026.
  final carLoan = DebtModel(
    id: 1,
    name: 'Crédito auto',
    totalAmount: 3000000,
    installments: 12,
    firstDate: DateTime(2026, 11, 30),
  );

  group('dueDates', () {
    test('el mismo día de cada mes, y febrero en su último día', () {
      final dates = carLoan.dueDates();

      expect(dates.length, 12);
      expect(dates.first, DateTime(2026, 11, 30, 12));
      expect(dates[1], DateTime(2026, 12, 30, 12));
      expect(dates[2], DateTime(2027, 1, 30, 12));
      // 2027 no es bisiesto: el 30 de febrero no existe y no puede
      // saltar a marzo, que ya tiene su propia cuota.
      expect(dates[3], DateTime(2027, 2, 28, 12));
      expect(dates[4], DateTime(2027, 3, 30, 12));
      expect(dates.last, DateTime(2027, 10, 30, 12));
    });

    test('un mes corto no corre las cuotas siguientes', () {
      final debt = DebtModel(
        name: 'x',
        totalAmount: 100,
        installments: 4,
        firstDate: DateTime(2027, 12, 31),
      );

      expect(debt.dueDates(), [
        DateTime(2027, 12, 31, 12),
        DateTime(2028, 1, 31, 12),
        DateTime(2028, 2, 29, 12), // 2028 es bisiesto
        DateTime(2028, 3, 31, 12),
      ]);
    });

    test('una sola cuota cae en la fecha elegida', () {
      final debt = DebtModel(
          name: 'x', totalAmount: 100, installments: 1, firstDate: DateTime(2026, 11, 30));
      expect(debt.dueDates(), [DateTime(2026, 11, 30, 12)]);
    });
  });

  group('amounts', () {
    test('un total que se divide exacto da cuotas iguales', () {
      expect(carLoan.amounts(), List.filled(12, 250000.0));
    });

    test('la última cuota absorbe el resto y la suma da el total', () {
      final debt = DebtModel(
          name: 'x', totalAmount: 1000000, installments: 3, firstDate: DateTime(2026, 1, 1));

      final amounts = debt.amounts();

      expect(amounts, [333333, 333333, 333334]);
      expect(amounts.reduce((a, b) => a + b), 1000000);
    });
  });

  group('buildInstallments', () {
    test('gastos con la categoría, la nota numerada y la deuda', () {
      final installments = carLoan.buildInstallments(debtId: 7, category: category);

      expect(installments.length, 12);
      expect(installments.every((t) => t.type == MovementType.expense), isTrue);
      expect(installments.every((t) => t.debtId == 7), isTrue);
      expect(installments.first.categoryName, 'Auto');
      expect(installments.first.note, 'Crédito auto · cuota 1/12');
      expect(installments.last.note, 'Crédito auto · cuota 12/12');
    });
  });

  group('DebtStatus', () {
    final installments = carLoan.buildInstallments(debtId: 1, category: category);
    final unrelated = TransactionModel(
      amount: 999,
      type: MovementType.expense,
      categoryId: 3,
      categoryName: 'Auto',
      categoryIconKey: 'car',
      note: '',
      date: DateTime(2026, 11, 30),
    );

    test('antes de la primera cuota no hay nada pagado', () {
      final status =
          DebtStatus.of(carLoan, [unrelated, ...installments], now: DateTime(2026, 10, 22));

      expect(status.installments.length, 12);
      expect(status.paidCount, 0);
      expect(status.remainingAmount, 3000000);
      expect(status.next!.date, DateTime(2026, 11, 30, 12));
      expect(status.isFinished, isFalse);
    });

    test('el día del vencimiento la cuota ya cuenta como pagada', () {
      final status = DebtStatus.of(carLoan, installments, now: DateTime(2026, 12, 30, 8));

      expect(status.paidCount, 2);
      expect(status.paidAmount, 500000);
      expect(status.remainingAmount, 2500000);
      expect(status.next!.date, DateTime(2027, 1, 30, 12));
    });

    test('refleja una cuota editada o borrada en el Historial', () {
      final edited = [
        for (final t in installments.skip(1)) // la primera se borró
          t.date.month == 12
              ? TransactionModel(
                  amount: 260000, // vino con interés
                  type: t.type,
                  categoryId: t.categoryId,
                  categoryName: t.categoryName,
                  categoryIconKey: t.categoryIconKey,
                  note: t.note,
                  date: t.date,
                  debtId: t.debtId,
                )
              : t,
      ];

      final status = DebtStatus.of(carLoan, edited, now: DateTime(2026, 10, 22));

      expect(status.installments.length, 11);
      expect(status.remainingAmount, 2760000);
    });

    test('termina cuando pasa la última cuota', () {
      final status = DebtStatus.of(carLoan, installments, now: DateTime(2027, 11, 1));

      expect(status.isFinished, isTrue);
      expect(status.paidCount, 12);
      expect(status.remainingAmount, 0);
    });
  });
}
