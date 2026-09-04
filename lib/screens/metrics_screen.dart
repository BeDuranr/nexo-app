import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  MetricPeriod _period = MetricPeriod.month;

  // Fecha dentro del periodo que se está mirando. Cambiarla permite
  // revisar meses (o semanas y años) anteriores sin tocar los datos.
  DateTime _reference = DateTime.now();

  /// Avanza o retrocede un periodo completo, en la unidad que esté
  /// seleccionada. Se usa el constructor de DateTime y no una Duration
  /// para que el cambio de hora no corra el resultado un día.
  void _shiftPeriod(int delta) {
    setState(() {
      _reference = switch (_period) {
        MetricPeriod.week =>
          DateTime(_reference.year, _reference.month, _reference.day + 7 * delta),
        MetricPeriod.month => DateTime(_reference.year, _reference.month + delta, 1),
        MetricPeriod.year => DateTime(_reference.year + delta, 1, 1),
      };
    });
  }

  String _periodLabel(({DateTime start, DateTime end}) range) {
    switch (_period) {
      case MetricPeriod.week:
        final from = DateFormat('d MMM', 'es_CL').format(range.start);
        final to = DateFormat('d MMM', 'es_CL').format(range.end);
        return '$from – $to';
      case MetricPeriod.month:
        final label = DateFormat('MMMM yyyy', 'es_CL').format(range.start);
        return label[0].toUpperCase() + label.substring(1);
      case MetricPeriod.year:
        return DateFormat('yyyy', 'es_CL').format(range.start);
    }
  }

  /// Un decimal en los miles: redondear a entero mostraba $1.500 como
  /// "$2k", y en pesos casi todos los montos caen en ese rango.
  static final _compact = NumberFormat('#,##0.#', 'es_CL');

  String _formatCompact(double value) {
    final negative = value < 0;
    final v = value.abs();
    String formatted;
    if (v >= 1000000) {
      formatted = '\$${_compact.format(v / 1000000)}M';
    } else if (v >= 1000) {
      formatted = '\$${_compact.format(v / 1000)}k';
    } else {
      formatted = '\$${v.round()}';
    }
    return negative ? '-$formatted' : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    if (txProvider.loading && txProvider.transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final income = txProvider.totalIncomeInPeriod(_period, reference: _reference);
    final expense = txProvider.totalExpenseInPeriod(_period, reference: _reference);
    final periodBalance = income - expense;

    final expenseTotals =
        txProvider.categoryTotals(_period, MovementType.expense, reference: _reference);
    final incomeTotals =
        txProvider.categoryTotals(_period, MovementType.income, reference: _reference);

    final range = txProvider.periodRange(_period, reference: _reference);
    final now = DateTime.now();
    final isCurrentPeriod = !now.isBefore(range.start) && !now.isAfter(range.end);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Análisis financiero', style: AppTheme.display(size: 16)),
            const SizedBox(height: 12),

            // Filtro de periodo
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.urban950,
                border: Border.all(color: AppColors.urban700),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: MetricPeriod.values.map((p) {
                  final selected = p == _period;
                  final label = switch (p) {
                    MetricPeriod.week => 'Semana',
                    MetricPeriod.month => 'Mes',
                    MetricPeriod.year => 'Año',
                  };
                  return Expanded(
                    child: GestureDetector(
                      // Cambiar de unidad conserva la fecha que se está
                      // mirando: de "Septiembre" a "Año" se pasa a 2026.
                      onTap: () => setState(() => _period = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.urban700 : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            color: selected ? Colors.white : AppColors.urban300,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),

            // Navegador del periodo: permite revisar meses (o semanas y
            // años) anteriores, no solo el actual.
            _PeriodNavigator(
              label: _periodLabel(range),
              isCurrent: isCurrentPeriod,
              onPrevious: () => _shiftPeriod(-1),
              onNext: () => _shiftPeriod(1),
              onBackToToday: () => setState(() => _reference = DateTime.now()),
            ),
            const SizedBox(height: 16),

            // Resumen del periodo: ingresos, gastos y balance neto.
            Row(
              children: [
                Expanded(
                  child: _SummaryStat(
                    label: 'Ingresos',
                    value: _formatCompact(income),
                    color: AppColors.income,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryStat(
                    label: 'Gastos',
                    value: _formatCompact(expense),
                    color: AppColors.expense,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryStat(
                    label: 'Balance',
                    value: _formatCompact(periodBalance),
                    color: periodBalance < 0 ? AppColors.expense : AppColors.urbanBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _CategorySection(
              title: 'Gastos por categoría',
              totals: expenseTotals,
              total: expense,
              barColor: AppColors.expense,
              emptyText: 'Aún no registras gastos en este periodo.',
              formatCompact: _formatCompact,
            ),
            const SizedBox(height: 20),

            _CategorySection(
              title: 'Ingresos por categoría',
              totals: incomeTotals,
              total: income,
              barColor: AppColors.income,
              emptyText: 'Aún no registras ingresos en este periodo.',
              formatCompact: _formatCompact,
            ),
          ],
        ),
      ),
    );
  }
}

/// Flechas para moverse entre periodos, con el rango visible al centro.
/// Mismo patrón que el selector de mes del Historial, para que las dos
/// pantallas se naveguen igual.
class _PeriodNavigator extends StatelessWidget {
  final String label;
  final bool isCurrent;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onBackToToday;

  const _PeriodNavigator({
    required this.label,
    required this.isCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onBackToToday,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left, color: AppColors.urban300),
            visualDensity: VisualDensity.compact,
            tooltip: 'Periodo anterior',
          ),
          Flexible(
            child: GestureDetector(
              onTap: isCurrent ? null : onBackToToday,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  if (!isCurrent)
                    const Text('Volver a hoy',
                        style: TextStyle(fontSize: 9, color: AppColors.urbanBlue)),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right, color: AppColors.urban300),
            visualDensity: VisualDensity.compact,
            tooltip: 'Periodo siguiente',
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
              value,
              key: ValueKey(value),
              style: AppTheme.display(size: 15, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String title;
  final List<CategoryTotal> totals;
  final double total;
  final Color barColor;
  final String emptyText;
  final String Function(double) formatCompact;

  const _CategorySection({
    required this.title,
    required this.totals,
    required this.total,
    required this.barColor,
    required this.emptyText,
    required this.formatCompact,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.display(size: 13)),
        const SizedBox(height: 10),
        if (totals.isEmpty)
          Text(emptyText, style: const TextStyle(fontSize: 11, color: AppColors.urban300))
        else
          ...totals.map((ct) {
            final pct = total > 0 ? (ct.amount / total * 100) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(iconForKey(ct.iconKey), color: colorForKey(ct.iconKey), size: 16),
                          const SizedBox(width: 6),
                          Text(ct.name,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Text(
                        '${formatCompact(ct.amount)} · ${pct.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 11, color: AppColors.urban300),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      tween: Tween<double>(
                        begin: 0,
                        end: total > 0 ? (ct.amount / total).clamp(0, 1) : 0,
                      ),
                      builder: (context, animatedValue, _) => LinearProgressIndicator(
                        value: animatedValue,
                        minHeight: 6,
                        backgroundColor: AppColors.urban700,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
