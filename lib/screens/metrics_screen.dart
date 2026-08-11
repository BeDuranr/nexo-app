import 'package:flutter/material.dart';
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

  String _formatCompact(double value) {
    final negative = value < 0;
    final v = value.abs();
    String formatted;
    if (v >= 1000000) {
      formatted = '\$${(v / 1000000).toStringAsFixed(1)}M';
    } else if (v >= 1000) {
      formatted = '\$${(v / 1000).toStringAsFixed(0)}k';
    } else {
      formatted = '\$${v.toStringAsFixed(0)}';
    }
    return negative ? '-$formatted' : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final income = txProvider.totalIncomeInPeriod(_period);
    final expense = txProvider.totalExpenseInPeriod(_period);
    final periodBalance = income - expense;

    final expenseTotals = txProvider.categoryTotals(_period, MovementType.expense);
    final incomeTotals = txProvider.categoryTotals(_period, MovementType.income);

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
                      onTap: () => setState(() => _period = p),
                      child: Container(
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
          Text(value, style: AppTheme.display(size: 15, color: color)),
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
                    child: LinearProgressIndicator(
                      value: total > 0 ? (ct.amount / total).clamp(0, 1) : 0,
                      minHeight: 6,
                      backgroundColor: AppColors.urban700,
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
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
