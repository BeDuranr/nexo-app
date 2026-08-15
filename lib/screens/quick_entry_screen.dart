import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_category_dialog.dart';
import '../widgets/category_grid.dart';
import '../widgets/thousands_input_formatter.dart';

class QuickEntryScreen extends StatefulWidget {
  const QuickEntryScreen({super.key});

  @override
  State<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends State<QuickEntryScreen> {
  final _amountController = TextEditingController();
  final _amountFocusNode = FocusNode();
  MovementType _type = MovementType.expense;
  CategoryModel? _selectedCategory;
  final _noteController = TextEditingController();

  // Fecha del movimiento. Por defecto es hoy, pero el usuario puede
  // cambiarla para registrar algo pasado o futuro (ej. un ingreso que
  // sabe que llegará el 1 de agosto).
  DateTime _selectedDate = DateTime.now();

  // Si el saldo mostrado es el "mensual" (hasta fin del mes de la fecha
  // seleccionada arriba) o el "histórico" (total absoluto de siempre).
  bool _showMonthlyBalance = true;

  @override
  void initState() {
    super.initState();
    // Redibuja para mostrar/ocultar la barra "Listo" según el foco.
    _amountFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocusNode.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _setType(MovementType type) {
    // El tipo (gasto/ingreso) es independiente de la categoría elegida:
    // cambiar el tipo NO deselecciona ni filtra la categoría actual.
    setState(() => _type = type);
  }

  Future<void> _addCategory(CategoryProvider categoryProvider) async {
    final newCategory = await showAddCategoryDialog(context);
    if (newCategory != null) {
      await categoryProvider.addCategory(newCategory);
    }
  }

  Future<void> _editCategory(CategoryProvider categoryProvider, CategoryModel category) async {
    final result = await showEditCategoryDialog(context, category);
    if (result == null) return;

    if (result.isDelete) {
      final confirmed = await confirmDeleteCategory(context, category.name);
      if (!confirmed) return;
      await categoryProvider.deleteCategory(category.id!);
      if (_selectedCategory?.id == category.id) {
        setState(() => _selectedCategory = null);
      }
    } else if (result.category != null) {
      await categoryProvider.updateCategory(result.category!);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('es', 'CL'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.urbanBlue,
                  onPrimary: Colors.white,
                  surface: AppColors.urban900,
                  onSurface: Colors.white,
                ),
            dialogTheme: const DialogThemeData(backgroundColor: AppColors.urban900),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final formatted = DateFormat("d 'de' MMMM", 'es_CL').format(date);
    return isToday ? 'Hoy, $formatted' : formatted;
  }

  Future<void> _submit() async {
    final amountValue = parseFormattedAmount(_amountController.text);
    if (amountValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.urban700,
          content: Text('Ingresa un monto válido', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.urban700,
          content: Text('Selecciona una categoría', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    // Combina la fecha elegida con la hora actual, para que el orden
    // dentro de un mismo día siga siendo coherente en el historial.
    final now = DateTime.now();
    final effectiveDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );

    final tx = TransactionModel(
      amount: amountValue,
      type: _type,
      categoryId: _selectedCategory!.id!,
      categoryName: _selectedCategory!.name,
      categoryIconKey: _selectedCategory!.iconKey,
      note: _noteController.text.trim(),
      date: effectiveDate,
    );

    await context.read<TransactionProvider>().addTransaction(tx);
    HapticFeedback.lightImpact();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '¡${_type == MovementType.expense ? 'Gasto' : 'Ingreso'} de \$${NumberFormat.decimalPattern('es_CL').format(amountValue)} guardado!',
        ),
      ),
    );

    setState(() {
      _amountController.clear();
      _noteController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    // Todas las categorías están siempre disponibles, sin importar si el
    // movimiento actual es gasto o ingreso.
    final categories = categoryProvider.categories;

    // Autoseleccionar la primera categoría disponible si aún no hay ninguna.
    if (categories.isNotEmpty && _selectedCategory == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedCategory == null) {
          setState(() => _selectedCategory = categories.first);
        }
      });
    }

    final isExpense = _type == MovementType.expense;

    return SafeArea(
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tocar la fecha abre el selector para editarla.
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_dateLabel(_selectedDate),
                      style: AppTheme.display(size: 16)),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_calendar_outlined,
                      size: 14, color: AppColors.urbanBlue),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Saldo — con selector Mensual (hasta fin del mes de la fecha
            // elegida arriba) / Histórico (total absoluto de siempre).
            Builder(builder: (context) {
              final txProvider = context.watch<TransactionProvider>();
              final monthEnd = DateTime(_selectedDate.year, _selectedDate.month + 1, 1)
                  .subtract(const Duration(seconds: 1));
              final displayedBalance = _showMonthlyBalance
                  ? txProvider.balanceUpTo(monthEnd)
                  : txProvider.balance;
              final isNegative = displayedBalance < 0;
              final monthLabel = DateFormat('MMMM', 'es_CL').format(_selectedDate);

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
                                selected: _showMonthlyBalance,
                                onTap: () => setState(() => _showMonthlyBalance = true),
                              ),
                              _SaldoTabButton(
                                label: 'Histórico',
                                selected: !_showMonthlyBalance,
                                onTap: () => setState(() => _showMonthlyBalance = false),
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
                        key: ValueKey('$_showMonthlyBalance-$displayedBalance'),
                        style: AppTheme.display(
                          size: 20,
                          color: isNegative ? AppColors.expense : AppColors.income,
                        ),
                      ),
                    ),
                    if (_showMonthlyBalance) ...[
                      const SizedBox(height: 2),
                      Text('a fin de $monthLabel',
                          style: const TextStyle(fontSize: 9, color: AppColors.urban500)),
                    ],
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),

            // Monto — se edita con el teclado numérico nativo del sistema,
            // que se abre automáticamente al tocar el campo.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.urban800,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.urbanBlue.withOpacity(0.5), width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isExpense ? 'GASTO (CLP)' : 'INGRESO (CLP)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: isExpense ? AppColors.expense : AppColors.income,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('\$', style: AppTheme.display(size: 28, color: AppColors.urban300)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _amountController,
                          focusNode: _amountFocusNode,
                          autofocus: false,
                          keyboardType: const TextInputType.numberWithOptions(decimal: false),
                          inputFormatters: [ThousandsInputFormatter()],
                          style: AppTheme.display(size: 32),
                          decoration: InputDecoration(
                            hintText: '0',
                            hintStyle: AppTheme.display(size: 32, color: AppColors.urban500),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Toggle tipo — píldora deslizante, independiente de la
            // categoría elegida.
            Container(
              height: 40,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.urban950,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.urban700),
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: isExpense ? Alignment.centerLeft : Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        decoration: BoxDecoration(
                          color: isExpense ? AppColors.expense : AppColors.income,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _TypeButton(
                          label: 'Gasto',
                          icon: Icons.trending_down,
                          selected: isExpense,
                          onTap: () => _setType(MovementType.expense),
                        ),
                      ),
                      Expanded(
                        child: _TypeButton(
                          label: 'Ingreso',
                          icon: Icons.trending_up,
                          selected: !isExpense,
                          onTap: () => _setType(MovementType.income),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            const Text('SELECCIONAR CATEGORÍA',
                style: TextStyle(
                    fontSize: 10, color: AppColors.urban300, fontWeight: FontWeight.w600)),
            const Text('Mantén presionada una categoría para editarla o eliminarla.',
                style: TextStyle(fontSize: 9, color: AppColors.urban500)),
            const SizedBox(height: 6),
            CategoryGrid(
              categories: categories,
              selected: _selectedCategory,
              onSelect: (cat) => setState(() => _selectedCategory = cat),
              onAddNew: () => _addCategory(categoryProvider),
              onLongPress: (cat) => _editCategory(categoryProvider, cat),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _noteController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                hintText: '+ Nota o detalle corto...',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),

            // Botón de guardar, reemplaza al antiguo botón "OK" del teclado virtual.
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: isExpense ? AppColors.expense : AppColors.income,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check, size: 18),
                    SizedBox(width: 8),
                    Text('Guardar movimiento', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),

          // Barra "Listo" — el teclado numérico de iOS/Android no trae
          // una tecla para ocultarse, así que la agregamos nosotros,
          // igual que hace Calculadora o Notas de Apple.
          if (_amountFocusNode.hasFocus)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom,
              child: Container(
                height: 40,
                color: AppColors.urban800,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextButton(
                  onPressed: () => _amountFocusNode.unfocus(),
                  child: const Text('Listo',
                      style: TextStyle(
                          color: AppColors.urbanBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                ),
              ),
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

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? Colors.white : AppColors.urban300),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : AppColors.urban300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
