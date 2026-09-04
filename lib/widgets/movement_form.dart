import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import 'add_category_dialog.dart';
import 'category_grid.dart';
import 'thousands_input_formatter.dart';

/// Lo que el formulario entrega al guardar. La fecha viene solo con día,
/// mes y año: cada pantalla decide qué hora ponerle (la actual al
/// registrar, la original al editar).
class MovementFormData {
  final double amount;
  final MovementType type;
  final CategoryModel category;
  final String note;
  final DateTime date;

  const MovementFormData({
    required this.amount,
    required this.type,
    required this.category,
    required this.note,
    required this.date,
  });
}

/// Formulario de movimiento compartido por la pantalla de registro y la
/// de edición, que antes tenían ~250 líneas casi idénticas duplicadas.
///
/// La categoría se guarda como **id**, no como copia del modelo: se
/// resuelve contra `CategoryProvider` en cada build, así renombrarla o
/// cambiarle el ícono se refleja al instante y nunca se guarda un nombre
/// viejo. Si la categoría fue eliminada, la resolución da null y la
/// validación obliga a elegir una, en vez de reasignar en silencio.
class MovementForm extends StatefulWidget {
  final double? initialAmount;
  final MovementType initialType;
  final int? initialCategoryId;
  final String initialNote;
  final DateTime initialDate;

  /// Selecciona la primera categoría disponible cuando no hay ninguna
  /// elegida. Se usa al registrar (baja fricción); al editar no, porque
  /// reasignaría el movimiento sin que el usuario lo pida.
  final bool autoSelectFirstCategory;

  /// Contenido opcional sobre el campo de monto (la tarjeta de saldo de
  /// la pantalla de registro). Recibe la fecha elegida para poder
  /// mostrar el saldo del mes correspondiente.
  final Widget Function(BuildContext context, DateTime selectedDate)? headerBuilder;

  final String submitLabel;

  /// Devuelve true si el movimiento se guardó. En false el formulario
  /// conserva lo escrito para que no se pierda nada.
  final Future<bool> Function(MovementFormData data) onSubmit;

  /// Limpia monto y nota tras un guardado exitoso (registro en cadena).
  final bool clearOnSuccess;

  const MovementForm({
    super.key,
    this.initialAmount,
    this.initialType = MovementType.expense,
    this.initialCategoryId,
    this.initialNote = '',
    required this.initialDate,
    this.autoSelectFirstCategory = false,
    this.headerBuilder,
    required this.submitLabel,
    required this.onSubmit,
    this.clearOnSuccess = false,
  });

  @override
  State<MovementForm> createState() => _MovementFormState();
}

class _MovementFormState extends State<MovementForm> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final _amountFocusNode = FocusNode();

  late MovementType _type;
  late DateTime _selectedDate;
  int? _selectedCategoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount == null ? '' : formatAmountForInput(widget.initialAmount!),
    );
    _noteController = TextEditingController(text: widget.initialNote);
    _type = widget.initialType;
    _selectedDate = widget.initialDate;
    _selectedCategoryId = widget.initialCategoryId;
    // Redibuja para mostrar/ocultar la barra "Listo" según el foco.
    _amountFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _amountFocusNode.removeListener(_onFocusChanged);
    _amountController.dispose();
    _amountFocusNode.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  /// Categoría efectiva: la elegida si sigue viva, o la primera de la
  /// lista cuando la pantalla pidió autoselección.
  CategoryModel? _resolveCategory(CategoryProvider provider) {
    final selected = provider.byId(_selectedCategoryId);
    if (selected != null) return selected;
    if (widget.autoSelectFirstCategory && provider.categories.isNotEmpty) {
      return provider.categories.first;
    }
    return null;
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.expense : null,
        content: Text(
          message,
          style: isError ? const TextStyle(color: Colors.white) : null,
        ),
      ),
    );
  }

  Future<void> _addCategory() async {
    final newCategory = await showAddCategoryDialog(context);
    if (newCategory == null || !mounted) return;

    final provider = context.read<CategoryProvider>();
    final ok = await provider.addCategory(newCategory);
    if (!mounted) return;
    if (!ok) {
      _showMessage('No se pudo crear la categoría', isError: true);
      return;
    }
    // Deja lista para usar la categoría recién creada.
    final created = provider.categories.isNotEmpty ? provider.categories.last : null;
    if (created != null) setState(() => _selectedCategoryId = created.id);
  }

  Future<void> _editCategory(CategoryModel category) async {
    final result = await showEditCategoryDialog(context, category);
    if (result == null || !mounted) return;

    final categories = context.read<CategoryProvider>();
    final transactions = context.read<TransactionProvider>();

    if (result.isDelete) {
      final confirmed = await confirmDeleteCategory(context, category.name);
      if (!confirmed || !mounted) return;
      final ok = await categories.deleteCategory(category.id!);
      if (!mounted) return;
      if (!ok) {
        _showMessage('No se pudo eliminar la categoría', isError: true);
        return;
      }
      if (_selectedCategoryId == category.id) {
        setState(() => _selectedCategoryId = null);
      }
    } else if (result.category != null) {
      final ok = await categories.updateCategory(result.category!);
      if (!mounted) return;
      if (!ok) {
        _showMessage('No se pudo guardar la categoría', isError: true);
        return;
      }
      // El nombre y el ícono también se copiaron a los movimientos que la
      // usan, así que hay que releerlos para que el Historial y las
      // Métricas queden al día.
      await transactions.load();
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
    if (picked != null && mounted) {
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
    if (_saving) return;

    final amount = parseFormattedAmount(_amountController.text);
    if (amount <= 0) {
      _showMessage('Ingresa un monto válido', isError: true);
      return;
    }
    final category = _resolveCategory(context.read<CategoryProvider>());
    if (category == null) {
      _showMessage('Selecciona una categoría', isError: true);
      return;
    }

    setState(() => _saving = true);
    final saved = await widget.onSubmit(MovementFormData(
      amount: amount,
      type: _type,
      category: category,
      note: _noteController.text.trim(),
      date: _selectedDate,
    ));
    if (!mounted) return;
    setState(() => _saving = false);

    if (saved && widget.clearOnSuccess) {
      _amountController.clear();
      _noteController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    // Todas las categorías están siempre disponibles, sin importar si el
    // movimiento actual es gasto o ingreso.
    final categories = categoryProvider.categories;
    final selectedCategory = _resolveCategory(categoryProvider);
    final isExpense = _type == MovementType.expense;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                    Text(_dateLabel(_selectedDate), style: AppTheme.display(size: 16)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_calendar_outlined,
                        size: 14, color: AppColors.urbanBlue),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (widget.headerBuilder != null) ...[
                widget.headerBuilder!(context, _selectedDate),
                const SizedBox(height: 10),
              ],

              // Monto — se edita con el teclado numérico nativo del
              // sistema, que se abre al tocar el campo.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.urban800,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.urbanBlue.withValues(alpha: 0.5), width: 2),
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
                        Text('\$',
                            style: AppTheme.display(size: 28, color: AppColors.urban300)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            focusNode: _amountFocusNode,
                            autofocus: false,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: false),
                            inputFormatters: const [ThousandsInputFormatter()],
                            style: AppTheme.display(size: 32),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle:
                                  AppTheme.display(size: 32, color: AppColors.urban500),
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
              _TypeToggle(
                isExpense: isExpense,
                onChanged: (type) => setState(() => _type = type),
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
                selected: selectedCategory,
                onSelect: (cat) => setState(() => _selectedCategoryId = cat.id),
                onAddNew: _addCategory,
                onLongPress: _editCategory,
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
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: isExpense ? AppColors.expense : AppColors.income,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_saving)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Text(widget.submitLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // Barra "Listo" — el teclado numérico de iOS/Android no trae una
        // tecla para ocultarse, así que la agregamos nosotros, igual que
        // hace Calculadora o Notas de Apple.
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
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final bool isExpense;
  final ValueChanged<MovementType> onChanged;

  const _TypeToggle({required this.isExpense, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  onTap: () => onChanged(MovementType.expense),
                ),
              ),
              Expanded(
                child: _TypeButton(
                  label: 'Ingreso',
                  icon: Icons.trending_up,
                  selected: !isExpense,
                  onTap: () => onChanged(MovementType.income),
                ),
              ),
            ],
          ),
        ],
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
