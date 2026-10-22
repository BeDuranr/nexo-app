import 'package:flutter/foundation.dart';

import '../db/db_helper.dart';
import '../models/category_model.dart';
import '../models/debt_model.dart';

/// Lista de deudas en cuotas. El avance de cada una (cuántas cuotas
/// pasaron, cuánto falta) no se guarda acá: sale de los movimientos de
/// `TransactionProvider`, vía `DebtStatus.of`.
class DebtProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper.instance;

  List<DebtModel> _debts = [];
  bool _loading = false;
  String? _lastError;

  List<DebtModel> get debts => _debts;
  bool get loading => _loading;
  String? get lastError => _lastError;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _debts = await _db.getDebts();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

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

  /// Además de la deuda, registra sus cuotas como movimientos. Quien
  /// llame debe recargar `TransactionProvider` para que aparezcan.
  Future<bool> addDebt(DebtModel debt, CategoryModel category) {
    return _write(() => _db.insertDebt(debt, category));
  }

  /// Guarda los cambios y rehace las cuotas pendientes si hace falta (ver
  /// `DBHelper.updateDebt`). Quien llame debe recargar `TransactionProvider`.
  Future<bool> updateDebt(DebtModel debt, CategoryModel category) {
    return _write(() => _db.updateDebt(debt, category, now: DateTime.now()));
  }

  /// Pago anticipado de lo que queda (ver `DBHelper.payOffDebt`). Quien
  /// llame debe recargar `TransactionProvider`.
  Future<bool> payOffDebt(DebtModel debt,
      {required double amount, required DateTime date}) async {
    var paid = false;
    final ok = await _write(() async {
      paid = await _db.payOffDebt(debt.id!, amount: amount, date: date);
    });
    return ok && paid;
  }

  /// Borra la deuda y sus cuotas futuras (ver `DBHelper.deleteDebt`).
  /// Quien llame debe recargar `TransactionProvider`.
  Future<bool> deleteDebt(DebtModel debt) {
    return _write(() => _db.deleteDebt(debt.id!, now: DateTime.now()));
  }
}
