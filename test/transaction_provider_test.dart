import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/models/transaction_model.dart';
import 'package:nexo/providers/transaction_provider.dart';

/// Provider con datos puestos a mano: la lógica de periodos y totales no
/// toca SQLite, así que se puede probar sin dispositivo.
class _TestableProvider extends TransactionProvider {
  _TestableProvider(List<TransactionModel> txs) {
    transactions.addAll(txs);
  }
}

TransactionModel _tx({
  required double amount,
  required MovementType type,
  required DateTime date,
  int categoryId = 1,
  String categoryName = 'Comida',
  String categoryIconKey = 'food',
  String note = '',
}) {
  return TransactionModel(
    amount: amount,
    type: type,
    categoryId: categoryId,
    categoryName: categoryName,
    categoryIconKey: categoryIconKey,
    note: note,
    date: date,
  );
}

void main() {
  // Jueves 4 de septiembre de 2026. La semana va del lunes 31 de agosto
  // al domingo 6 de septiembre.
  final reference = DateTime(2026, 9, 4, 12);

  group('balance', () {
    test('resta gastos y suma ingresos sobre todo el histórico', () {
      final provider = _TestableProvider([
        _tx(amount: 1000, type: MovementType.income, date: DateTime(2026, 9, 1)),
        _tx(amount: 400, type: MovementType.expense, date: DateTime(2026, 9, 2)),
      ]);

      expect(provider.balance, 600);
    });

    test('balanceUpTo ignora los movimientos posteriores a la fecha', () {
      final provider = _TestableProvider([
        _tx(amount: 1000, type: MovementType.income, date: DateTime(2026, 9, 1)),
        _tx(amount: 5000, type: MovementType.income, date: DateTime(2026, 12, 25)),
      ]);

      expect(provider.balanceUpTo(DateTime(2026, 9, 30, 23, 59, 59)), 1000);
      expect(provider.balance, 6000);
    });
  });

  group('transactionsInPeriod', () {
    test('un movimiento con fecha futura solo cuenta en el periodo que le toca', () {
      final provider = _TestableProvider([
        _tx(amount: 100, type: MovementType.expense, date: reference),
        // El bug original: sin límite superior, este caía en los tres.
        _tx(amount: 9999, type: MovementType.income, date: DateTime(2026, 12, 25)),
        _tx(amount: 7777, type: MovementType.income, date: DateTime(2027, 1, 5)),
      ]);

      List<double> amountsIn(MetricPeriod period) => provider
          .transactionsInPeriod(period, reference: reference)
          .map((t) => t.amount)
          .toList();

      expect(amountsIn(MetricPeriod.week), [100],
          reason: 'diciembre no pertenece a esta semana');
      expect(amountsIn(MetricPeriod.month), [100],
          reason: 'diciembre no pertenece a septiembre');
      // Diciembre sí es parte del año en curso; enero del siguiente, no.
      expect(amountsIn(MetricPeriod.year), [100, 9999]);
    });

    test('la semana va de lunes a domingo, ambos incluidos', () {
      final provider = _TestableProvider([
        _tx(amount: 1, type: MovementType.expense, date: DateTime(2026, 8, 30, 23, 59)),
        _tx(amount: 2, type: MovementType.expense, date: DateTime(2026, 8, 31)),
        _tx(amount: 3, type: MovementType.expense, date: DateTime(2026, 9, 6, 23, 59)),
        _tx(amount: 4, type: MovementType.expense, date: DateTime(2026, 9, 7)),
      ]);

      final amounts = provider
          .transactionsInPeriod(MetricPeriod.week, reference: reference)
          .map((t) => t.amount)
          .toList();

      expect(amounts, [2, 3]);
    });

    test('el mes incluye el último instante del último día', () {
      final provider = _TestableProvider([
        _tx(amount: 5, type: MovementType.expense, date: DateTime(2026, 9, 30, 23, 59, 59)),
        _tx(amount: 6, type: MovementType.expense, date: DateTime(2026, 10, 1)),
      ]);

      final amounts = provider
          .transactionsInPeriod(MetricPeriod.month, reference: reference)
          .map((t) => t.amount)
          .toList();

      expect(amounts, [5]);
    });
  });

  group('categoryTotals', () {
    test('agrupa por id, no por nombre', () {
      final provider = _TestableProvider([
        _tx(
          amount: 100,
          type: MovementType.expense,
          date: reference,
          categoryId: 1,
          categoryName: 'Almuerzo',
        ),
        _tx(
          amount: 50,
          type: MovementType.expense,
          date: reference,
          categoryId: 1,
          categoryName: 'Almuerzo',
        ),
        // Otra categoría que casualmente se llama igual: no debe fusionarse.
        _tx(
          amount: 30,
          type: MovementType.expense,
          date: reference,
          categoryId: 2,
          categoryName: 'Almuerzo',
        ),
      ]);

      final totals = provider.categoryTotals(MetricPeriod.month, MovementType.expense,
          reference: reference);

      expect(totals.length, 2);
      expect(totals.first.categoryId, 1);
      expect(totals.first.amount, 150);
      expect(totals.last.categoryId, 2);
      expect(totals.last.amount, 30);
    });

    test('separa gastos de ingresos y ordena de mayor a menor', () {
      final provider = _TestableProvider([
        _tx(amount: 10, type: MovementType.expense, date: reference, categoryId: 1),
        _tx(amount: 90, type: MovementType.expense, date: reference, categoryId: 2),
        _tx(amount: 500, type: MovementType.income, date: reference, categoryId: 3),
      ]);

      final expenses = provider.categoryTotals(MetricPeriod.month, MovementType.expense,
          reference: reference);
      expect(expenses.map((t) => t.amount), [90, 10]);

      final incomes = provider.categoryTotals(MetricPeriod.month, MovementType.income,
          reference: reference);
      expect(incomes.map((t) => t.categoryId), [3]);
    });
  });
}
