import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/transaction_tile.dart';
import 'edit_transaction_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Mes actualmente mostrado (siempre normalizado al día 1).
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  bool _isSameMonth(DateTime date) =>
      date.year == _selectedMonth.year && date.month == _selectedMonth.month;

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final transactions =
        txProvider.transactions.where((t) => _isSameMonth(t.date)).toList();

    final monthLabel = DateFormat('MMMM yyyy', 'es_CL').format(_selectedMonth);
    final capitalizedMonthLabel = monthLabel[0].toUpperCase() + monthLabel.substring(1);

    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historial de movimientos', style: AppTheme.display(size: 16)),
            const SizedBox(height: 10),

            // Selector de mes.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.urban900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.urban700),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left, color: AppColors.urban300),
                    visualDensity: VisualDensity.compact,
                  ),
                  GestureDetector(
                    onTap: isCurrentMonth
                        ? null
                        : () => setState(() => _selectedMonth = DateTime(now.year, now.month, 1)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          capitalizedMonthLabel,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (!isCurrentMonth)
                          const Text('Volver a hoy',
                              style: TextStyle(fontSize: 9, color: AppColors.urbanBlue)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right, color: AppColors.urban300),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            const Row(
              children: [
                Icon(Icons.swipe_left_alt, size: 14, color: AppColors.urbanBlue),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Desliza un movimiento a la izquierda para editarlo o borrarlo.',
                    style: TextStyle(fontSize: 10, color: AppColors.urban300),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: transactions.isEmpty
                  ? Center(
                      child: Text(
                        'No hay movimientos en $capitalizedMonthLabel.',
                        style: const TextStyle(color: AppColors.urban300, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return TransactionTile(
                          key: ValueKey(tx.id),
                          tx: tx,
                          onEdit: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EditTransactionScreen(transaction: tx),
                              ),
                            );
                          },
                          onDelete: () async {
                            await context.read<TransactionProvider>().deleteTransaction(tx);
                            HapticFeedback.lightImpact();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.urban700,
                                content: const Text('Movimiento eliminado',
                                    style: TextStyle(color: Colors.white)),
                                action: SnackBarAction(
                                  label: 'DESHACER',
                                  textColor: AppColors.urbanBlue,
                                  onPressed: () =>
                                      context.read<TransactionProvider>().undoDelete(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
