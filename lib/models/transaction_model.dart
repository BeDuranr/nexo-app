enum MovementType { expense, income }

MovementType movementTypeFromString(String value) =>
    value == 'income' ? MovementType.income : MovementType.expense;

String movementTypeToString(MovementType type) => type.name;

class TransactionModel {
  final int? id;
  final double amount;
  final MovementType type;
  final int categoryId;
  final String categoryName;
  final String categoryIconKey;
  final String note;
  final DateTime date;

  /// Deuda en cuotas a la que pertenece, o null si es un movimiento
  /// suelto. Una cuota es un gasto común con fecha futura: este id solo
  /// sirve para agruparlas en la pestaña Deudas.
  final int? debtId;

  const TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIconKey,
    required this.note,
    required this.date,
    this.debtId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': movementTypeToString(type),
      'category_id': categoryId,
      'category_name': categoryName,
      'category_icon_key': categoryIconKey,
      'note': note,
      'date': date.toIso8601String(),
      'debt_id': debtId,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      type: movementTypeFromString(map['type'] as String),
      categoryId: map['category_id'] as int,
      categoryName: map['category_name'] as String,
      categoryIconKey: map['category_icon_key'] as String? ?? 'other',
      note: map['note'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      debtId: map['debt_id'] as int?,
    );
  }
}
