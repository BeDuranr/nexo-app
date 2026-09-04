import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/movement_form.dart';

class QuickEntryScreen extends StatefulWidget {
  const QuickEntryScreen({super.key});

  @override
  State<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends State<QuickEntryScreen> {
  // Si el saldo mostrado es el "mensual" (hasta fin del mes de la fecha
  // elegida en el formulario) o el "histórico" (total absoluto).
  bool _showMonthlyBalance = true;

  Future<bool> _submit(MovementFormData data) async {
    // Combina la fecha elegida con la hora actual, para que el orden
    // dentro de un mismo día siga siendo coherente en el historial.
    final now = DateTime.now();
    final effectiveDate = DateTime(
      data.date.year,
      data.date.month,
      data.date.day,
      now.hour,
      now.minute,
      now.second,
    );

    final tx = TransactionModel(
      amount: data.amount,
      type: data.type,
      categoryId: data.category.id!,
      categoryName: data.category.name,
      categoryIconKey: data.category.iconKey,
      note: data.note,
      date: effectiveDate,
    );

    final provider = context.read<TransactionProvider>();
    final saved = await provider.addTransaction(tx);
    if (!mounted) return saved;

    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('No se pudo guardar el movimiento. Intenta de nuevo.',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return false;
    }

    HapticFeedback.lightImpact();
    final amountLabel = NumberFormat.decimalPattern('es_CL').format(data.amount);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '¡${data.type == MovementType.expense ? 'Gasto' : 'Ingreso'} de \$$amountLabel guardado!',
        ),
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: MovementForm(
        initialDate: DateTime.now(),
        autoSelectFirstCategory: true,
        submitLabel: 'Guardar movimiento',
        clearOnSuccess: true,
        onSubmit: _submit,
        headerBuilder: (context, selectedDate) => _BalanceCard(
          selectedDate: selectedDate,
          showMonthly: _showMonthlyBalance,
          onModeChanged: (monthly) => setState(() => _showMonthlyBalance = monthly),
        ),
      ),
    );
  }
}

/// Saldo con selector Mensual (neto del mes de la fecha elegida:
/// ingresos menos gastos de ese mes) / Histórico (acumulado de siempre
/// hasta hoy, sin contar movimientos con fecha futura).
class _BalanceCard extends StatelessWidget {
  final DateTime selectedDate;
  final bool showMonthly;
  final ValueChanged<bool> onModeChanged;

  const _BalanceCard({
    required this.selectedDate,
    required this.showMonthly,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    // "Mensual" es el neto del mes elegido; "Histórico", el acumulado
    // hasta hoy. Antes ambos cortaban a fin de mes, asi que sin
    // movimientos futuros mostraban exactamente lo mismo.
    final displayedBalance = showMonthly
        ? txProvider.netInMonth(selectedDate)
        : txProvider.balance;
    final isNegative = displayedBalance < 0;
    final monthLabel = DateFormat('MMMM', 'es_CL').format(selectedDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.urban900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.urban700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SALDO',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppColors.urban300,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.urban950,
                  border: Border.all(color: AppColors.urban700),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _SaldoTabButton(
                      label: 'Mensual',
                      selected: showMonthly,
                      onTap: () => onModeChanged(true),
                    ),
                    _SaldoTabButton(
                      label: 'Histórico',
                      selected: !showMonthly,
                      onTap: () => onModeChanged(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              '${isNegative ? '-' : ''}\$${NumberFormat.decimalPattern('es_CL').format(displayedBalance.abs())}',
              key: ValueKey('$showMonthly-$displayedBalance'),
              style: AppTheme.display(
                size: 20,
                color: isNegative ? AppColors.expense : AppColors.income,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            showMonthly ? 'neto de $monthLabel' : 'acumulado hasta hoy',
            style: const TextStyle(fontSize: 9, color: AppColors.urban500),
          ),
        ],
      ),
    );
  }
}

class _SaldoTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SaldoTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? AppColors.urban700 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.urban300,
            ),
          ),
        ),
      ),
    );
  }
}
