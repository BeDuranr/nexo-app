import 'package:flutter/foundation.dart';

import '../db/db_helper.dart';
import '../models/transaction_model.dart';

enum MetricPeriod { week, month, year }

class TransactionProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper.instance;

  List<TransactionModel> _transactions = [];
  bool _loading = false;
  String? _lastError;

  // Guarda la última transacción eliminada para poder deshacer.
  TransactionModel? _lastDeleted;

  List<TransactionModel> get transactions => _transactions;
  bool get loading => _loading;

  /// Detalle del último fallo de base de datos, o null si la última
  /// operación salió bien. Las pantallas muestran su propio mensaje; esto
  /// sirve para agregar el motivo técnico.
  String? get lastError => _lastError;

  /// Saldo actual: todos los ingresos menos todos los gastos registrados
  /// hasta ahora (histórico completo, no solo el periodo filtrado).
  double get balance {
    double total = 0;
    for (final t in _transactions) {
      total += t.type == MovementType.income ? t.amount : -t.amount;
    }
    return total;
  }

  /// Saldo acumulado considerando solo los movimientos con fecha hasta
  /// (inclusive) la indicada. Sirve para responder "¿cuánto tenía hasta
  /// tal mes?", a diferencia de [balance] que es el total histórico
  /// completo (incluye incluso movimientos con fecha futura).
  double balanceUpTo(DateTime date) {
    double total = 0;
    for (final t in _transactions) {
      if (!t.date.isAfter(date)) {
        total += t.type == MovementType.income ? t.amount : -t.amount;
      }
    }
    return total;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _transactions = await _db.getTransactions();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  /// Ejecuta una escritura, recarga y deja el error a mano si falla.
  /// Devuelve false cuando la operación no se pudo completar, para que la
  /// pantalla no anuncie un éxito que no ocurrió.
  Future<bool> _write(Future<void> Function() action) async {
    try {
      await action();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
    await load();
    return true;
  }

  Future<bool> addTransaction(TransactionModel tx) {
    return _write(() => _db.insertTransaction(tx));
  }

  Future<bool> deleteTransaction(TransactionModel tx) async {
    if (tx.id == null) return false;
    final ok = await _write(() => _db.deleteTransaction(tx.id!));
    if (ok) _lastDeleted = tx;
    return ok;
  }

  Future<bool> updateTransaction(TransactionModel tx) {
    return _write(() => _db.updateTransaction(tx));
  }

  Future<bool> undoDelete() async {
    final tx = _lastDeleted;
    if (tx == null) return false;
    final ok = await _write(() => _db.restoreTransaction(tx));
    if (ok) _lastDeleted = null;
    return ok;
  }

  // ---------- Métricas ----------

  /// Rango cerrado del periodo que contiene a [reference] (por defecto,
  /// hoy). Además de los cálculos, lo usa la pantalla de Métricas para
  /// rotular el periodo que se está viendo.
  ({DateTime start, DateTime end}) periodRange(MetricPeriod period, {DateTime? reference}) =>
      _periodRange(period, reference ?? DateTime.now());

  /// El extremo superior importa: la app permite registrar movimientos
  /// con fecha futura, y sin él un ingreso de diciembre entraba en los
  /// totales de "Semana".
  ({DateTime start, DateTime end}) _periodRange(MetricPeriod period, DateTime now) {
    switch (period) {
      case MetricPeriod.week:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(monday.year, monday.month, monday.day);
        // El domingo se calcula con el constructor (que normaliza el
        // desborde de días) y no sumando una Duration: en la semana del
        // cambio de hora, sumar 6 días puede caer un día antes.
        return (
          start: start,
          end: _endOfDay(DateTime(start.year, start.month, start.day + 6)),
        );
      case MetricPeriod.month:
        return (
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 1)
              .subtract(const Duration(milliseconds: 1)),
        );
      case MetricPeriod.year:
        return (
          start: DateTime(now.year, 1, 1),
          end: DateTime(now.year + 1, 1, 1).subtract(const Duration(milliseconds: 1)),
        );
    }
  }

  static DateTime _endOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

  List<TransactionModel> transactionsInPeriod(MetricPeriod period, {DateTime? reference}) {
    final range = _periodRange(period, reference ?? DateTime.now());
    return _transactions
        .where((t) => !t.date.isBefore(range.start) && !t.date.isAfter(range.end))
        .toList();
  }

  /// Total de gastos del periodo.
  double totalExpenseInPeriod(MetricPeriod period, {DateTime? reference}) {
    double total = 0;
    for (final t in transactionsInPeriod(period, reference: reference)) {
      if (t.type == MovementType.expense) total += t.amount;
    }
    return total;
  }

  /// Total de ingresos del periodo.
  double totalIncomeInPeriod(MetricPeriod period, {DateTime? reference}) {
    double total = 0;
    for (final t in transactionsInPeriod(period, reference: reference)) {
      if (t.type == MovementType.income) total += t.amount;
    }
    return total;
  }

  /// Desglose por categoría (ordenado de mayor a menor) para un tipo de
  /// movimiento dentro del periodo — la base de los gráficos de
  /// "Gastos por categoría" e "Ingresos por categoría".
  ///
  /// Agrupa por `categoryId`, no por nombre: renombrar una categoría no
  /// debe partir su historial en dos filas, y dos categorías distintas
  /// que casualmente se llamen igual no deben fusionarse. El nombre y el
  /// ícono salen de las columnas denormalizadas, que `DBHelper` mantiene
  /// sincronizadas mientras la categoría exista.
  List<CategoryTotal> categoryTotals(MetricPeriod period, MovementType type,
      {DateTime? reference}) {
    final txs =
        transactionsInPeriod(period, reference: reference).where((t) => t.type == type);

    final Map<int, CategoryTotal> totals = {};
    for (final t in txs) {
      final existing = totals[t.categoryId];
      totals[t.categoryId] = existing == null
          ? CategoryTotal(
              categoryId: t.categoryId,
              name: t.categoryName,
              iconKey: t.categoryIconKey,
              amount: t.amount,
            )
          : existing.copyWith(amount: existing.amount + t.amount);
    }

    return totals.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }
}

/// Total acumulado de una categoría dentro de un periodo.
class CategoryTotal {
  final int categoryId;
  final String name;
  final String iconKey;
  final double amount;

  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.iconKey,
    required this.amount,
  });

  CategoryTotal copyWith({double? amount}) {
    return CategoryTotal(
      categoryId: categoryId,
      name: name,
      iconKey: iconKey,
      amount: amount ?? this.amount,
    );
  }
}
