import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/debt_model.dart';
import '../providers/debt_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';
import 'debt_form_screen.dart';

String _money(double amount) =>
    '\$${NumberFormat.decimalPattern('es_CL').format(amount.round())}';

/// Deudas en cuotas: cuánto falta de cada una y cuál es la próxima cuota.
///
/// Las cuotas ya están registradas como gastos con fecha futura, así que
/// esta pantalla solo agrupa y resume. Una cuota se edita o se borra en
/// el Historial, como cualquier otro movimiento.
/// Abre el formulario para crear una deuda, o para editar [editing].
void _openDebtForm(BuildContext context, {DebtStatus? editing}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, animation, __) => DebtFormScreen(editing: editing),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  void _openNewDebt(BuildContext context) => _openDebtForm(context);

  @override
  Widget build(BuildContext context) {
    final debtProvider = context.watch<DebtProvider>();
    final transactions = context.watch<TransactionProvider>().transactions;
    final now = DateTime.now();

    final statuses = [
      for (final debt in debtProvider.debts) DebtStatus.of(debt, transactions, now: now),
    ];
    // Las que siguen corriendo arriba; las terminadas quedan al final
    // como registro, sin tapar lo que todavía hay que pagar.
    final active = statuses.where((s) => !s.isFinished).toList();
    final finished = statuses.where((s) => s.isFinished).toList();

    final remaining = active.fold<double>(0, (sum, s) => sum + s.remainingAmount);
    double thisMonth = 0;
    for (final s in statuses) {
      for (final t in s.installments) {
        if (t.date.year == now.year && t.date.month == now.month) thisMonth += t.amount;
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Deudas en cuotas', style: AppTheme.display(size: 16)),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openNewDebt(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nueva'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (debtProvider.loading && statuses.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (statuses.isEmpty)
              Expanded(child: _EmptyState(onCreate: () => _openNewDebt(context)))
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _SummaryStat(
                      label: 'Por pagar',
                      value: _money(remaining),
                      color: AppColors.expense,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryStat(
                      label: 'Cuotas de este mes',
                      value: _money(thisMonth),
                      color: AppColors.urbanBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    for (final s in active) _DebtCard(status: s),
                    if (finished.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(2, 10, 0, 8),
                        child: Text('TERMINADAS',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.urban300,
                                fontWeight: FontWeight.w600)),
                      ),
                      for (final s in finished) _DebtCard(status: s),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_repeat, size: 32, color: AppColors.urban500),
            const SizedBox(height: 10),
            const Text(
              'Registra un crédito o una compra en cuotas y cada cuota se '
              'anota sola como gasto en su fecha.',
              style: TextStyle(color: AppColors.urban300, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Agregar una deuda'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.urban800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.urban700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.urban300,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: AppTheme.display(size: 16, color: color)),
        ],
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final DebtStatus status;

  const _DebtCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final debt = status.debt;
    final total = status.installments.length;
    final progress = total == 0 ? 0.0 : status.paidCount / total;
    final iconKey =
        status.installments.isEmpty ? 'other' : status.installments.first.categoryIconKey;
    final next = status.next;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.urban800,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showDebtDetail(context, status),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.urban700),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(iconForKey(iconKey), size: 18, color: colorForKey(iconKey)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        debt.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    Text(
                      '${status.paidCount}/$total',
                      style: AppTheme.display(size: 13, color: AppColors.urban300),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // El avance se anima al aparecer, como las barras de
                // Métricas, en vez de saltar directo a su valor.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: AppColors.urban700,
                      color: status.isFinished ? AppColors.income : AppColors.urbanBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status.isFinished
                            ? 'Pagada: ${_money(status.paidAmount)}'
                            : 'Quedan ${_money(status.remainingAmount)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.urban100),
                      ),
                    ),
                    if (next != null)
                      Text(
                        'Próxima: ${DateFormat('d MMM', 'es_CL').format(next.date)} · '
                        '${_money(next.amount)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.urban300),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showDebtDetail(BuildContext context, DebtStatus status) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DebtDetailSheet(status: status),
  );
}

/// Calendario completo de la deuda, con la opción de eliminarla.
class _DebtDetailSheet extends StatelessWidget {
  final DebtStatus status;

  const _DebtDetailSheet({required this.status});

  Future<void> _delete(BuildContext context) async {
    final pending = status.installments.length - status.paidCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar "${status.debt.name}"?', style: AppTheme.display(size: 17)),
        content: Text(
          [
            if (pending > 0)
              'Se borran ${pending == 1 ? 'la cuota que falta' : 'las $pending cuotas que faltan'}.',
            if (status.paidCount > 0)
              '${status.paidCount == 1 ? 'La cuota que ya pasó queda' : 'Las ${status.paidCount} cuotas que ya pasaron quedan'} '
                  'en el Historial como gasto.',
          ].join(' '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.urban300)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final transactions = context.read<TransactionProvider>();
    final ok = await context.read<DebtProvider>().deleteDebt(status.debt);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('No se pudo eliminar la deuda. Intenta de nuevo.',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }
    // Las cuotas futuras se borraron de la base: sin esto seguirían en
    // el Historial y en el saldo del mes hasta reabrir la app.
    await transactions.load();
    HapticFeedback.lightImpact();
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Deuda eliminada')));
  }

  @override
  Widget build(BuildContext context) {
    final debt = status.debt;
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final total = status.installments.fold<double>(0, (sum, t) => sum + t.amount);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(debt.name, style: AppTheme.display(size: 18)),
              const SizedBox(height: 2),
              Text(
                '${_money(total)} en ${status.installments.length} cuotas · '
                'quedan ${_money(status.remainingAmount)}',
                style: const TextStyle(fontSize: 11, color: AppColors.urban300),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: status.installments.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.urban700),
                  itemBuilder: (_, i) {
                    final t = status.installments[i];
                    final paid = !t.date.isAfter(endOfToday);
                    final isNext = identical(t, status.next);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Icon(
                            paid ? Icons.check_circle : Icons.schedule,
                            size: 16,
                            color: paid
                                ? AppColors.income
                                : (isNext ? AppColors.urbanBlue : AppColors.urban500),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 44,
                            child: Text('${i + 1}/${status.installments.length}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.urban300)),
                          ),
                          Expanded(
                            child: Text(
                              DateFormat("d 'de' MMMM yyyy", 'es_CL').format(t.date),
                              style: TextStyle(
                                fontSize: 12,
                                color: paid ? AppColors.urban300 : Colors.white,
                                fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          Text(
                            _money(t.amount),
                            style: AppTheme.display(
                                size: 13, color: paid ? AppColors.urban300 : Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Para cambiar una cuota (por ejemplo, si vino con interés), '
                'edítala en el Historial como cualquier movimiento.',
                style: TextStyle(fontSize: 10, color: AppColors.urban500),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => _delete(context),
                    icon:
                        const Icon(Icons.delete_outline, size: 16, color: AppColors.expense),
                    label: const Text('Eliminar deuda',
                        style: TextStyle(color: AppColors.expense)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      // Se cierra el detalle antes de abrir el formulario:
                      // al volver, sus datos ya no serían los de la deuda.
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      _openDebtForm(navigator.context, editing: status);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
