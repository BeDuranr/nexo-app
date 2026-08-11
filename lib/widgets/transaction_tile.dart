import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction_model.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// Fila de un movimiento en el historial. Deslizar hacia la izquierda
/// revela dos acciones: Editar y Borrar.
class TransactionTile extends StatefulWidget {
  final TransactionModel tx;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TransactionTile({
    super.key,
    required this.tx,
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
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    final animation = Tween<double>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    void listener() => setState(() => _offset = animation.value);
    animation.addListener(listener);
    _controller.forward(from: 0).whenCompleteOrCancel(() {
      animation.removeListener(listener);
    });
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
    final formattedAmount = NumberFormat.decimalPattern('es_CL').format(tx.amount);

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
                      Icon(iconForKey(tx.categoryIconKey),
                          color: colorForKey(tx.categoryIconKey), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx.note.isNotEmpty ? tx.note : tx.categoryName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${DateFormat('d MMM, HH:mm', 'es_CL').format(tx.date)} • ${tx.categoryName}',
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
