import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// Fila de un movimiento en el historial. Deslizar hacia la izquierda
/// revela dos acciones: Editar y Borrar.
class TransactionTile extends StatefulWidget {
  final TransactionModel tx;

  /// Categoría actual (viva) del movimiento, si todavía existe. Se usa
  /// para mostrar ícono/nombre al día aunque la categoría haya sido
  /// editada después de crear el movimiento; si es null (la categoría
  /// fue eliminada) se cae a lo que quedó guardado en [tx].
  final CategoryModel? category;

  /// Incluye el año en la fecha. Se usa cuando la lista mezcla meses
  /// (búsqueda en todo el historial) y "12 sep" sería ambiguo.
  final bool showYear;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.category,
    this.showYear = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<TransactionTile> createState() => _TransactionTileState();
}

class _TransactionTileState extends State<TransactionTile>
    with SingleTickerProviderStateMixin {
  static const double _actionsWidth = 152; // 2 botones de 76 c/u

  late final AnimationController _controller;
  Animation<double>? _slide;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    // Un único listener sobre el controller: acumularlos por animación
    // hacía que dos swipes seguidos se pelearan por `_offset`.
    _controller.addListener(_syncOffset);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncOffset);
    _controller.dispose();
    super.dispose();
  }

  void _syncOffset() {
    final slide = _slide;
    if (slide == null) return;
    setState(() => _offset = slide.value);
  }

  void _animateTo(double target) {
    _slide = Tween<double>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward(from: 0);
  }

  void _close() {
    if (_offset != 0) _animateTo(0);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_actionsWidth, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_offset < -_actionsWidth / 2) {
      _animateTo(-_actionsWidth);
    } else {
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final isExpense = tx.type == MovementType.expense;
    final color = isExpense ? AppColors.expense : AppColors.income;
    final formattedAmount = NumberFormat.decimalPattern('es_CL').format(tx.amount.round());
    final datePattern = widget.showYear ? 'd MMM yyyy, HH:mm' : 'd MMM, HH:mm';
    // Prioriza la categoría viva (por si fue editada); si fue borrada,
    // cae a la copia guardada en el movimiento.
    final categoryIconKey = widget.category?.iconKey ?? tx.categoryIconKey;
    final categoryName = widget.category?.name ?? tx.categoryName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Acciones reveladas al deslizar.
            Positioned.fill(
              child: Row(
                children: [
                  const Spacer(),
                  _SwipeAction(
                    label: 'Editar',
                    icon: Icons.edit_outlined,
                    color: AppColors.urbanBlue,
                    onTap: () {
                      _close();
                      widget.onEdit();
                    },
                  ),
                  _SwipeAction(
                    label: 'Borrar',
                    icon: Icons.delete_outline,
                    color: AppColors.expense,
                    onTap: widget.onDelete,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onTap: _offset != 0 ? _close : null,
              child: Transform.translate(
                offset: Offset(_offset, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.urban800,
                    border: Border(left: BorderSide(color: color, width: 4)),
                  ),
                  child: Row(
                    children: [
                      Icon(iconForKey(categoryIconKey),
                          color: colorForKey(categoryIconKey), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx.note.isNotEmpty ? tx.note : categoryName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${DateFormat(datePattern, 'es_CL').format(tx.date)} • $categoryName',
                              style: const TextStyle(fontSize: 10, color: AppColors.urban300),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${isExpense ? '-' : '+'}\$$formattedAmount',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
