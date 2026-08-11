import 'package:flutter/foundation.dart';

import '../db/db_helper.dart';
import '../models/transaction_model.dart';

enum MetricPeriod { week, month, year }

class TransactionProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper.instance;

  List<TransactionModel> _transactions = [];
  bool _loading = false;

  // Guarda la última transacción eliminada para poder deshacer.
  TransactionModel? _lastDeleted;

  List<TransactionModel> get transactions => _transactions;
  bool get loading => _loading;
  bool get canUndo => _lastDeleted != null;

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
    _transactions = await _db.getTransactions();
    _loading = false;
    notifyListeners();
  }

  Future<void> addTransaction(TransactionModel tx) async {
    await _db.insertTransaction(tx);
    await load();
  }

  Future<void> deleteTransaction(TransactionModel tx) async {
    if (tx.id == null) return;
    await _db.deleteTransaction(tx.id!);
    _lastDeleted = tx;
    await load();
  }

  Future<void> updateTransaction(TransactionModel tx) async {
    await _db.updateTransaction(tx);
    await load();
  }

  Future<void> undoDelete() async {
    final tx = _lastDeleted;
    if (tx == null) return;
    await _db.restoreTransaction(tx);
    _lastDeleted = null;
    await load();
  }

  void clearUndo() {
    _lastDeleted = null;
  }

  // ---------- Métricas ----------

  DateTime _startOfPeriod(MetricPeriod period, DateTime now) {
    switch (period) {
      case MetricPeriod.week:
        final startOfWeekDay = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(startOfWeekDay.year, startOfWeekDay.month, startOfWeekDay.day);
      case MetricPeriod.month:
        return DateTime(now.year, now.month, 1);
      case MetricPeriod.year:
        return DateTime(now.year, 1, 1);
    }
  }

  List<TransactionModel> transactionsInPeriod(MetricPeriod period, {DateTime? reference}) {
    final now = reference ?? DateTime.now();
    final start = _startOfPeriod(period, now);
    return _transactions.where((t) => !t.date.isBefore(start)).toList();
  }

  /// Total de gastos del periodo.
  double totalExpenseInPeriod(MetricPeriod period) {
    final txs = transactionsInPeriod(period);
    double total = 0;
    for (final t in txs) {
      if (t.type == MovementType.expense) total += t.amount;
    }
    return total;
  }

  /// Total de ingresos del periodo.
  double totalIncomeInPeriod(MetricPeriod period) {
    final txs = transactionsInPeriod(period);
    double total = 0;
    for (final t in txs) {
      if (t.type == MovementType.income) total += t.amount;
    }
    return total;
  }

  /// Desglose por categoría (ordenado de mayor a menor) para un tipo de
  /// movimiento dentro del periodo — la base de los gráficos de
  /// "Gastos por categoría" e "Ingresos por categoría".
  List<CategoryTotal> categoryTotals(MetricPeriod period, MovementType type) {
    final txs = transactionsInPeriod(period).where((t) => t.type == type);

    final Map<String, CategoryTotal> totals = {};
    for (final t in txs) {
      final existing = totals[t.categoryName];
      if (existing != null) {
        totals[t.categoryName] = existing.copyWith(amount: existing.amount + t.amount);
      } else {
        totals[t.categoryName] = CategoryTotal(
          name: t.categoryName,
          iconKey: t.categoryIconKey,
          amount: t.amount,
        );
      }
    }

    final list = totals.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }
}

/// Total acumulado de una categoría dentro de un periodo.
class CategoryTotal {
  final String name;
  final String iconKey;
  final double amount;

  const CategoryTotal({required this.name, required this.iconKey, required this.amount});

  CategoryTotal copyWith({double? amount}) {
    return CategoryTotal(name: name, iconKey: iconKey, amount: amount ?? this.amount);
  }
}
