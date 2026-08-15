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

class EditTransactionScreen extends StatefulWidget {
  final TransactionModel transaction;

  const EditTransactionScreen({super.key, required this.transaction});

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  late final TextEditingController _amountController;
  final _amountFocusNode = FocusNode();
  late final TextEditingController _noteController;
  late MovementType _type;
  CategoryModel? _selectedCategory;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;
    _amountController = TextEditingController(
      text: NumberFormat.decimalPattern('es_CL').format(tx.amount.toInt()),
    );
    _noteController = TextEditingController(text: tx.note);
    _type = tx.type;
    _selectedDate = tx.date;
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

  void _setType(MovementType type) => setState(() => _type = type);

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
    if (picked != null) setState(() => _selectedDate = picked);
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final formatted = DateFormat("d 'de' MMMM", 'es_CL').format(date);
    return isToday ? 'Hoy, $formatted' : formatted;
  }

  Future<void> _save() async {
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

    final original = widget.transaction;
    final updated = TransactionModel(
      id: original.id,
      amount: amountValue,
      type: _type,
      categoryId: _selectedCategory!.id!,
      categoryName: _selectedCategory!.name,
      categoryIconKey: _selectedCategory!.iconKey,
      note: _noteController.text.trim(),
      // Conserva la hora original del registro, solo cambia el día si
      // el usuario lo editó.
      date: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        original.date.hour,
        original.date.minute,
        original.date.second,
      ),
    );

    await context.read<TransactionProvider>().updateTransaction(updated);
    HapticFeedback.lightImpact();

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Movimiento actualizado')),
    );
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.urban900,
        title: const Text('¿Eliminar movimiento?', style: TextStyle(color: Colors.white)),
        content: const Text('Esta acción no se puede deshacer.',
            style: TextStyle(color: AppColors.urban300)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await context.read<TransactionProvider>().deleteTransaction(widget.transaction);
    HapticFeedback.lightImpact();

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Movimiento eliminado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final categories = categoryProvider.categories;

    // Resuelve la categoría seleccionada apenas la lista está disponible.
    if (_selectedCategory == null && categories.isNotEmpty) {
      final match = categories.where((c) => c.id == widget.transaction.categoryId);
      _selectedCategory = match.isNotEmpty ? match.first : categories.first;
    }

    final isExpense = _type == MovementType.expense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar movimiento'),
        actions: [
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, color: AppColors.expense),
            tooltip: 'Eliminar',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_dateLabel(_selectedDate),
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.urban300,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_calendar_outlined, size: 12, color: AppColors.urbanBlue),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Monto
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
                            keyboardType: const TextInputType.numberWithOptions(decimal: false),
                            inputFormatters: [ThousandsInputFormatter()],
                            style: AppTheme.display(size: 32),
                            decoration: const InputDecoration(
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

              // Toggle tipo — píldora deslizante.
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

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
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
                      Text('Guardar cambios', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

            // Barra "Listo" — igual que en la pantalla de registro.
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
