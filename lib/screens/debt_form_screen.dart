import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_model.dart';
import '../models/debt_model.dart';
import '../models/transaction_model.dart';
import '../providers/category_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_category_dialog.dart';
import '../widgets/category_grid.dart';
import '../widgets/thousands_input_formatter.dart';

String _money(double amount) =>
    '\$${NumberFormat.decimalPattern('es_CL').format(amount.round())}';

/// Alta y edición de una deuda en cuotas: monto total, cantidad de cuotas
/// y fecha de la primera. Antes de guardar muestra exactamente qué cuotas
/// se van a registrar, porque se insertan (o se rehacen) todas de una vez.
class DebtFormScreen extends StatefulWidget {
  /// La deuda a editar, con su avance; null para crear una nueva.
  final DebtStatus? editing;

  const DebtFormScreen({super.key, this.editing});

  @override
  State<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends State<DebtFormScreen> {
  static const int _maxInstallments = 120;

  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _installmentsController = TextEditingController(text: '12');
  final _amountFocusNode = FocusNode();
  final _installmentsFocusNode = FocusNode();

  late DateTime _firstDate;
  int? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Lo más común es que la primera cuota sea el mes que viene. El
    // constructor normaliza el desborde (31 de enero → 3 de marzo), pero
    // igual el usuario elige la fecha real del crédito.
    final now = DateTime.now();
    _firstDate = DateTime(now.year, now.month + 1, now.day);

    final editing = widget.editing;
    if (editing != null) {
      final debt = editing.debt;
      _nameController.text = debt.name;
      _amountController.text = formatAmountForInput(debt.totalAmount);
      _installmentsController.text = '${debt.installments}';
      _firstDate = DateTime(debt.firstDate.year, debt.firstDate.month, debt.firstDate.day);
      // Si la categoría se eliminó, byId da null y el formulario obliga
      // a elegir otra en vez de reasignar en silencio.
      _categoryId =
          editing.installments.isEmpty ? null : editing.installments.first.categoryId;
    }

    // Redibuja la vista previa y la barra "Listo" mientras se escribe.
    for (final c in [_nameController, _amountController, _installmentsController]) {
      c.addListener(_refresh);
    }
    _amountFocusNode.addListener(_refresh);
    _installmentsFocusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _installmentsController.dispose();
    _amountFocusNode.dispose();
    _installmentsFocusNode.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  int get _installments => int.tryParse(_installmentsController.text) ?? 0;

  void _changeInstallments(int delta) {
    final next = (_installments + delta).clamp(1, _maxInstallments);
    _installmentsController.text = '$next';
  }

  /// La deuda tal como quedaría con lo escrito, o null si falta algo.
  DebtModel? _draft() {
    final amount = parseFormattedAmount(_amountController.text);
    final installments = _installments;
    if (amount <= 0 || installments < 1 || installments > _maxInstallments) return null;
    final name = _nameController.text.trim();
    return DebtModel(
      id: widget.editing?.debt.id,
      name: name.isEmpty ? 'Deuda' : name,
      totalAmount: amount,
      installments: installments,
      firstDate: _firstDate,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.expense : null,
        content: Text(message, style: isError ? const TextStyle(color: Colors.white) : null),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstDate,
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
    if (picked != null && mounted) setState(() => _firstDate = picked);
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
    final created = provider.categories.isNotEmpty ? provider.categories.last : null;
    if (created != null) setState(() => _categoryId = created.id);
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    if (_nameController.text.trim().isEmpty) {
      _showMessage('Ponle un nombre a la deuda', isError: true);
      return;
    }
    final debt = _draft();
    if (debt == null) {
      _showMessage(parseFormattedAmount(_amountController.text) <= 0
          ? 'Ingresa el monto total'
          : 'Las cuotas van de 1 a $_maxInstallments', isError: true);
      return;
    }
    final category = context.read<CategoryProvider>().byId(_categoryId);
    if (category == null) {
      _showMessage('Selecciona una categoría', isError: true);
      return;
    }
    final editError = _editError(debt);
    if (editError != null) {
      _showMessage(editError, isError: true);
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final transactions = context.read<TransactionProvider>();
    final debts = context.read<DebtProvider>();
    final ok = widget.editing == null
        ? await debts.addDebt(debt, category)
        : await debts.updateDebt(debt, category);
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      _showMessage('No se pudo guardar la deuda. Intenta de nuevo.', isError: true);
      return;
    }

    // Las cuotas se insertaron o se rehicieron como movimientos: sin
    // recargar, el Historial y el saldo no las verían hasta reabrir la app.
    await transactions.load();
    HapticFeedback.lightImpact();
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(widget.editing != null
          ? 'Deuda actualizada'
          : 'Deuda guardada: ${debt.installments} '
              '${debt.installments == 1 ? 'cuota' : 'cuotas'} registradas'),
    ));
  }

  /// Al editar con un calendario o monto nuevo, las cuotas pendientes se
  /// rehacen repartiendo lo que falta pagar. Eso no tiene sentido si no
  /// queda ninguna cuota por delante, o si lo pagado ya cubre el total.
  String? _editError(DebtModel draft) {
    final editing = widget.editing;
    if (editing == null || !draft.scheduleDiffers(editing.debt)) return null;
    final pending = _pendingPreview(draft, editing);
    if (pending.isEmpty) {
      return 'Con esa fecha y cantidad de cuotas ya no queda ninguna por pagar.';
    }
    if (draft.totalAmount <= editing.paidAmount) {
      return 'El total tiene que ser mayor a lo ya pagado (${_money(editing.paidAmount)}).';
    }
    return null;
  }

  /// Cuotas pendientes que quedarían al guardar. La categoría no cambia
  /// montos ni fechas, así que para la vista previa basta una cualquiera.
  List<TransactionModel> _pendingPreview(DebtModel draft, DebtStatus editing) {
    return draft.rebuildPending(
      debtId: editing.debt.id ?? 0,
      category: const CategoryModel(id: 0, name: '', iconKey: 'other'),
      paidAmount: editing.paidAmount,
      now: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final draft = _draft();
    final editing = widget.editing;
    final showDoneBar = _amountFocusNode.hasFocus || _installmentsFocusNode.hasFocus;

    final Widget preview;
    if (draft == null) {
      preview = const SizedBox.shrink();
    } else if (editing == null) {
      preview = _Preview(key: const ValueKey('nueva'), debt: draft);
    } else if (!draft.scheduleDiffers(editing.debt)) {
      preview = const _PreviewBox(
        key: ValueKey('sin-cambios'),
        children: [
          Text(
            'Solo se actualizan el nombre y la categoría de sus cuotas. '
            'Los montos y las fechas quedan como están.',
            style: TextStyle(fontSize: 11, color: AppColors.urban100),
          ),
        ],
      );
    } else {
      preview = _EditPreview(
        key: const ValueKey('rehacer'),
        pending: _pendingPreview(draft, editing),
        paidCount: editing.paidCount,
        paidAmount: editing.paidAmount,
        totalAmount: draft.totalAmount,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(editing == null ? 'Nueva deuda' : 'Editar deuda')),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('NOMBRE'),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Ej: Crédito auto',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  _AmountField(controller: _amountController, focusNode: _amountFocusNode),
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Label('CUOTAS'),
                            _InstallmentsStepper(
                              controller: _installmentsController,
                              focusNode: _installmentsFocusNode,
                              onChange: _changeInstallments,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Label('PRIMERA CUOTA'),
                            _DateButton(date: _firstDate, onTap: _pickDate),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Las demás caen el día ${_firstDate.day} de cada mes'
                    '${_firstDate.day > 28 ? ', o el último día si el mes es más corto' : ''}.',
                    style: const TextStyle(fontSize: 9, color: AppColors.urban500),
                  ),
                  const SizedBox(height: 14),

                  const _Label('CATEGORÍA'),
                  CategoryGrid(
                    categories: categoryProvider.categories,
                    selected: categoryProvider.byId(_categoryId),
                    onSelect: (cat) => setState(() => _categoryId = cat.id),
                    onAddNew: _addCategory,
                  ),
                  const SizedBox(height: 14),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: preview,
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.expense,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape:
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                          Text(editing == null ? 'Guardar deuda' : 'Guardar cambios',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Barra "Listo": el teclado numérico no trae una tecla para
            // cerrarse (mismo arreglo que en el formulario de movimiento).
            if (showDoneBar)
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
                    onPressed: () => FocusScope.of(context).unfocus(),
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

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 10, color: AppColors.urban300, fontWeight: FontWeight.w600)),
    );
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _AmountField({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.urban800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.urbanBlue.withValues(alpha: 0.5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MONTO TOTAL DE LA DEUDA (CLP)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: AppColors.expense,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('\$', style: AppTheme.display(size: 28, color: AppColors.urban300)),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: const [ThousandsInputFormatter()],
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
    );
  }
}

/// Cantidad de cuotas: se puede escribir (36 cuotas a puro "+" sería
/// tedioso) o ajustar de a una con los botones.
class _InstallmentsStepper extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<int> onChange;

  const _InstallmentsStepper({
    required this.controller,
    required this.focusNode,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.urban800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.urban700),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onChange(-1),
            icon: const Icon(Icons.remove, size: 16, color: AppColors.urban300),
            visualDensity: VisualDensity.compact,
            tooltip: 'Una cuota menos',
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: AppTheme.display(size: 16),
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
          IconButton(
            onPressed: () => onChange(1),
            icon: const Icon(Icons.add, size: 16, color: AppColors.urban300),
            visualDensity: VisualDensity.compact,
            tooltip: 'Una cuota más',
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DateButton({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.urban800,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.urban700),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('d MMM yyyy', 'es_CL').format(date),
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ),
              const Icon(Icons.edit_calendar_outlined, size: 14, color: AppColors.urbanBlue),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen de lo que se va a registrar, antes de guardar.
class _Preview extends StatelessWidget {
  final DebtModel debt;

  const _Preview({super.key, required this.debt});

  @override
  Widget build(BuildContext context) {
    final dates = debt.dueDates();
    final amounts = debt.amounts();
    final format = DateFormat('d MMM yyyy', 'es_CL');
    final lastDiffers = amounts.length > 1 && amounts.last != amounts.first;

    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final alreadyDue = dates.where((d) => !d.isAfter(endOfToday)).length;

    return _PreviewBox(
      children: [
        Text(
          '${debt.installments} ${debt.installments == 1 ? 'cuota' : 'cuotas'} '
          'de ${_money(amounts.first)}',
          style: AppTheme.display(size: 15),
        ),
        const SizedBox(height: 4),
        Text(
          debt.installments == 1
              ? 'El ${format.format(dates.first)}'
              : 'Del ${format.format(dates.first)} al ${format.format(dates.last)}',
          style: const TextStyle(fontSize: 11, color: AppColors.urban100),
        ),
        if (lastDiffers) ...[
          const SizedBox(height: 4),
          Text(
            'La última es de ${_money(amounts.last)} para cuadrar el total.',
            style: const TextStyle(fontSize: 10, color: AppColors.urban300),
          ),
        ],
        if (alreadyDue > 0) ...[
          const SizedBox(height: 4),
          Text(
            alreadyDue == 1
                ? 'La primera cuota ya pasó: queda registrada como gasto en su fecha.'
                : '$alreadyDue cuotas ya pasaron: quedan registradas como gasto en su fecha.',
            style: const TextStyle(fontSize: 10, color: AppColors.urban300),
          ),
        ],
      ],
    );
  }
}

/// Qué pasa con las cuotas al guardar una edición que cambia el
/// calendario o el monto: las pasadas quedan y las pendientes se rehacen.
class _EditPreview extends StatelessWidget {
  final List<TransactionModel> pending;
  final int paidCount;
  final double paidAmount;
  final double totalAmount;

  const _EditPreview({
    super.key,
    required this.pending,
    required this.paidCount,
    required this.paidAmount,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('d MMM yyyy', 'es_CL');
    const detail = TextStyle(fontSize: 10, color: AppColors.urban300);

    // Mismos mensajes que frena _editError al guardar, para que el
    // problema se vea antes de apretar el botón.
    if (pending.isEmpty) {
      return const _PreviewBox(children: [
        Text('Con esa fecha y cantidad de cuotas ya no queda ninguna por pagar.',
            style: TextStyle(fontSize: 11, color: AppColors.expense)),
      ]);
    }
    if (totalAmount <= paidAmount) {
      return _PreviewBox(children: [
        Text('El total tiene que ser mayor a lo ya pagado (${_money(paidAmount)}).',
            style: const TextStyle(fontSize: 11, color: AppColors.expense)),
      ]);
    }

    final lastDiffers =
        pending.length > 1 && pending.last.amount != pending.first.amount;
    return _PreviewBox(
      children: [
        Text(
          'Quedan ${pending.length} ${pending.length == 1 ? 'cuota' : 'cuotas'} '
          'de ${_money(pending.first.amount)}',
          style: AppTheme.display(size: 15),
        ),
        const SizedBox(height: 4),
        Text(
          pending.length == 1
              ? 'El ${format.format(pending.first.date)}'
              : 'Del ${format.format(pending.first.date)} al ${format.format(pending.last.date)}',
          style: const TextStyle(fontSize: 11, color: AppColors.urban100),
        ),
        if (lastDiffers) ...[
          const SizedBox(height: 4),
          Text('La última es de ${_money(pending.last.amount)} para cuadrar el total.',
              style: detail),
        ],
        if (paidCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            paidCount == 1
                ? 'La cuota que ya pasó (${_money(paidAmount)}) no se toca.'
                : 'Las $paidCount cuotas que ya pasaron (${_money(paidAmount)}) no se tocan.',
            style: detail,
          ),
        ],
        const SizedBox(height: 4),
        const Text(
          'Las cuotas pendientes se vuelven a calcular: si editaste alguna a mano, '
          'se reemplaza.',
          style: detail,
        ),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final List<Widget> children;

  const _PreviewBox({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.urbanBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.urbanBlue.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
