import 'dart:math';

import 'category_model.dart';
import 'transaction_model.dart';

/// Una deuda en cuotas mensuales (ej. "Crédito auto", 12 cuotas desde el
/// 30 de noviembre).
///
/// Las cuotas no viven acá: al crear la deuda se registran de una vez
/// como gastos comunes con fecha futura, atados por `debt_id`. Así cada
/// una aparece sola en su mes del Historial, cuenta en las Métricas de
/// ese mes y entra al saldo recién cuando llega su día, sin depender de
/// que la app esté abierta esa fecha.
class DebtModel {
  final int? id;
  final String name;
  final double totalAmount;
  final int installments;

  /// Fecha de la primera cuota. Su día del mes es el de todas las demás.
  final DateTime firstDate;

  const DebtModel({
    this.id,
    required this.name,
    required this.totalAmount,
    required this.installments,
    required this.firstDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'total_amount': totalAmount,
      'installments': installments,
      'first_date': firstDate.toIso8601String(),
    };
  }

  factory DebtModel.fromMap(Map<String, dynamic> map) {
    return DebtModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      totalAmount: (map['total_amount'] as num).toDouble(),
      installments: map['installments'] as int,
      firstDate: DateTime.parse(map['first_date'] as String),
    );
  }

  /// Fechas de vencimiento: el mismo día de [firstDate] cada mes. Si el
  /// mes es más corto (el 30 en febrero), cae el último día de ese mes,
  /// que es lo que hacen los bancos, en vez de saltar a marzo.
  ///
  /// Van a mediodía y no a medianoche: en Chile el cambio de hora es a
  /// las 00:00, y una medianoche que no existe puede correrse de día.
  List<DateTime> dueDates() {
    return [
      for (var i = 0; i < installments; i++)
        _clampedDate(firstDate.year, firstDate.month + i, firstDate.day),
    ];
  }

  static DateTime _clampedDate(int year, int month, int day) {
    // El día 0 del mes siguiente es el último de este; el constructor
    // normaliza el desborde de meses (mes 13 → enero del año siguiente).
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, min(day, lastDay), 12);
  }

  /// Montos de cada cuota, en pesos enteros. Si el total no se divide
  /// exacto, la última absorbe la diferencia: así la suma da siempre el
  /// total que escribió el usuario.
  List<double> amounts() => _split(totalAmount, installments);

  static List<double> _split(double total, int parts) {
    if (parts == 0) return const [];
    final base = (total / parts).floorToDouble();
    return [
      for (var i = 0; i < parts - 1; i++) base,
      total - base * (parts - 1),
    ];
  }

  /// Nota automática de cada cuota. También sirve para reconocerla al
  /// editar la deuda: una nota que el usuario cambió a mano no se pisa.
  String installmentNote(int number) => '$name · cuota $number/$installments';

  bool isAutoNote(String note) => note.startsWith('$name · cuota ');

  /// ¿Cambia el calendario o los montos respecto de [other]? Si solo
  /// cambió el nombre o la categoría, editar no tiene por qué recalcular
  /// las cuotas, y así se respeta una cuota futura editada a mano.
  bool scheduleDiffers(DebtModel other) =>
      totalAmount != other.totalAmount ||
      installments != other.installments ||
      firstDate.year != other.firstDate.year ||
      firstDate.month != other.firstDate.month ||
      firstDate.day != other.firstDate.day;

  /// Las cuotas como movimientos listos para insertar. [debtId] es el id
  /// que SQLite le dio a la deuda recién creada.
  List<TransactionModel> buildInstallments({
    required int debtId,
    required CategoryModel category,
  }) {
    final dates = dueDates();
    final values = amounts();
    return [
      for (var i = 0; i < installments; i++)
        _installment(i, values[i], dates[i], debtId, category),
    ];
  }

  /// Cuotas que reemplazan a las pendientes al editar la deuda: las del
  /// calendario nuevo con fecha posterior a hoy, repartiéndose en partes
  /// iguales lo que falta pagar ([paidAmount] es lo que suman las cuotas
  /// que ya pasaron, que no se tocan).
  ///
  /// Se reparte lo que falta y no el total entre todas, para que la suma
  /// siga dando el total aunque una cuota pasada se haya editado.
  List<TransactionModel> rebuildPending({
    required int debtId,
    required CategoryModel category,
    required double paidAmount,
    required DateTime now,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final dates = dueDates();
    final pending = [
      for (var i = 0; i < dates.length; i++)
        if (dates[i].isAfter(endOfToday)) i,
    ];
    final values = _split(totalAmount - paidAmount, pending.length);
    return [
      for (var k = 0; k < pending.length; k++)
        _installment(pending[k], values[k], dates[pending[k]], debtId, category),
    ];
  }

  TransactionModel _installment(
      int index, double amount, DateTime date, int debtId, CategoryModel category) {
    return TransactionModel(
      amount: amount,
      type: MovementType.expense,
      categoryId: category.id!,
      categoryName: category.name,
      categoryIconKey: category.iconKey,
      note: installmentNote(index + 1),
      date: date,
      debtId: debtId,
    );
  }
}

/// Estado de una deuda a una fecha: qué cuotas ya pasaron y cuánto falta.
///
/// Se calcula desde los movimientos reales y no desde la deuda, porque
/// una cuota se puede editar (un atraso con interés) o borrar en el
/// Historial como cualquier otro gasto.
class DebtStatus {
  final DebtModel debt;

  /// Cuotas que siguen existiendo, de la más antigua a la más nueva.
  final List<TransactionModel> installments;

  /// Cuotas con fecha hasta hoy: ya se registraron como gasto.
  final int paidCount;

  final double paidAmount;
  final double remainingAmount;

  /// Próxima cuota por registrarse, o null si ya no queda ninguna.
  final TransactionModel? next;

  const DebtStatus._({
    required this.debt,
    required this.installments,
    required this.paidCount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.next,
  });

  bool get isFinished => next == null;

  factory DebtStatus.of(
    DebtModel debt,
    Iterable<TransactionModel> transactions, {
    required DateTime now,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final installments = transactions.where((t) => t.debtId == debt.id).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    var paidCount = 0;
    double paid = 0;
    double remaining = 0;
    TransactionModel? next;
    for (final t in installments) {
      if (t.date.isAfter(endOfToday)) {
        remaining += t.amount;
        next ??= t;
      } else {
        paidCount++;
        paid += t.amount;
      }
    }

    return DebtStatus._(
      debt: debt,
      installments: installments,
      paidCount: paidCount,
      paidAmount: paid,
      remainingAmount: remaining,
      next: next,
    );
  }
}
