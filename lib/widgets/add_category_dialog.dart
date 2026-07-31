import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../theme/app_theme.dart';

/// Muestra el diálogo y retorna la nueva categoría, o null si se cancela.
/// Las categorías no tienen tipo: sirven tanto para gastos como ingresos.
Future<CategoryModel?> showAddCategoryDialog(BuildContext context) {
  final nameController = TextEditingController();
  final emojiController = TextEditingController(text: '🏷️');

  return showDialog<CategoryModel>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: AppColors.urban900,
        title: const Text('Nueva categoría', style: TextStyle(color: Colors.white)),
        content: Row(
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: emojiController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22),
                decoration: const InputDecoration(hintText: '🏷️'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Nombre de la categoría'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final emoji = emojiController.text.trim().isEmpty
                  ? '🏷️'
                  : emojiController.text.trim();
              Navigator.pop(ctx, CategoryModel(name: name, emoji: emoji));
            },
            child: const Text('Crear'),
          ),
        ],
      );
    },
  );
}

/// Resultado de editar una categoría existente: guardar cambios o eliminarla.
class CategoryEditResult {
  final CategoryModel? category; // no-nulo cuando la acción fue "guardar"
  final bool isDelete;

  const CategoryEditResult.save(this.category) : isDelete = false;
  const CategoryEditResult.delete()
      : category = null,
        isDelete = true;
}

/// Muestra el diálogo para editar una categoría existente (incluidas las
/// que vienen por defecto). Retorna null si se cancela.
Future<CategoryEditResult?> showEditCategoryDialog(
  BuildContext context,
  CategoryModel category,
) {
  final nameController = TextEditingController(text: category.name);
  final emojiController = TextEditingController(text: category.emoji);

  return showDialog<CategoryEditResult>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: AppColors.urban900,
        title: const Text('Editar categoría', style: TextStyle(color: Colors.white)),
        content: Row(
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: emojiController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22),
                decoration: const InputDecoration(hintText: '🏷️'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Nombre de la categoría'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, const CategoryEditResult.delete()),
            child: const Text('Eliminar', style: TextStyle(color: AppColors.expense)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final emoji =
                  emojiController.text.trim().isEmpty ? category.emoji : emojiController.text.trim();
              Navigator.pop(
                ctx,
                CategoryEditResult.save(category.copyWith(name: name, emoji: emoji)),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      );
    },
  );
}

/// Confirma antes de eliminar definitivamente una categoría. Los
/// movimientos ya registrados con ella conservan su nombre y emoji
/// guardados, así que no se ven afectados.
Future<bool> confirmDeleteCategory(BuildContext context, String categoryName) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.urban900,
      title: const Text('¿Eliminar categoría?', style: TextStyle(color: Colors.white)),
      content: Text(
        'Se eliminará "$categoryName" de la lista. Los movimientos ya registrados con esta categoría no se ven afectados.',
        style: const TextStyle(color: AppColors.urban300),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar', style: TextStyle(color: AppColors.expense)),
        ),
      ],
    ),
  );
  return confirmed == true;
}
