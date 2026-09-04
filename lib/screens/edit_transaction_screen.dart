import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/movement_form.dart';

class EditTransactionScreen extends StatefulWidget {
  final TransactionModel transaction;

  const EditTransactionScreen({super.key, required this.transaction});

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  Future<bool> _save(MovementFormData data) async {
    final original = widget.transaction;
    final updated = TransactionModel(
      id: original.id,
      amount: data.amount,
      type: data.type,
      categoryId: data.category.id!,
      categoryName: data.category.name,
      categoryIconKey: data.category.iconKey,
      note: data.note,
      // Conserva la hora original del registro, solo cambia el día si el
      // usuario lo editó.
      date: DateTime(
        data.date.year,
        data.date.month,
        data.date.day,
        original.date.hour,
        original.date.minute,
        original.date.second,
      ),
    );

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final saved = await context.read<TransactionProvider>().updateTransaction(updated);

    if (!saved) {
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('No se pudo guardar el movimiento. Intenta de nuevo.',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return false;
    }

    HapticFeedback.lightImpact();
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Movimiento actualizado')),
    );
    return true;
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.urban900,
        title: const Text('¿Eliminar movimiento?', style: TextStyle(color: Colors.white)),
        content: const Text('Podrás deshacerlo desde el aviso que aparece después.',
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
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = context.read<TransactionProvider>();
    final deleted = await provider.deleteTransaction(widget.transaction);

    if (!deleted) {
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('No se pudo eliminar el movimiento. Intenta de nuevo.',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.urban700,
        content: const Text('Movimiento eliminado', style: TextStyle(color: Colors.white)),
        action: SnackBarAction(
          label: 'DESHACER',
          textColor: AppColors.urbanBlue,
          onPressed: provider.undoDelete,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;

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
        child: MovementForm(
          initialAmount: tx.amount,
          initialType: tx.type,
          initialCategoryId: tx.categoryId,
          initialNote: tx.note,
          initialDate: tx.date,
          submitLabel: 'Guardar cambios',
          onSubmit: _save,
        ),
      ),
    );
  }
}
