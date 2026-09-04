import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// Grilla de íconos reutilizable dentro de los diálogos de categoría.
class _IconPicker extends StatelessWidget {
  final String selectedKey;
  final void Function(String) onSelect;

  const _IconPicker({required this.selectedKey, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      width: double.maxFinite,
      child: GridView.count(
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: categoryIcons.entries.map((entry) {
          final isSelected = entry.key == selectedKey;
          final color = colorForKey(entry.key);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(entry.key),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.2) : AppColors.urban800,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : AppColors.urban700,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Icon(entry.value, color: color, size: 20),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Cuerpo compartido por los diálogos de crear y editar: nombre + ícono.
/// Es un StatefulWidget (y no un StatefulBuilder) para poder liberar el
/// TextEditingController cuando el diálogo se cierra.
class _CategoryDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final CategoryModel? initial;

  /// Muestra el botón "Eliminar" (solo al editar).
  final bool allowDelete;

  const _CategoryDialog({
    required this.title,
    required this.confirmLabel,
    this.initial,
    this.allowDelete = false,
  });

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _nameController;
  late String _selectedIconKey;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _selectedIconKey = widget.initial?.iconKey ?? 'other';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      // Antes el botón simplemente no hacía nada, sin explicar por qué.
      setState(() => _nameError = 'Escribe un nombre');
      return;
    }
    final base = widget.initial;
    Navigator.pop(
      context,
      CategoryEditResult.save(
        base == null
            ? CategoryModel(name: name, iconKey: _selectedIconKey)
            : base.copyWith(name: name, iconKey: _selectedIconKey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.urban900,
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              hintText: 'Nombre de la categoría',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          _IconPicker(
            selectedKey: _selectedIconKey,
            onSelect: (key) => setState(() => _selectedIconKey = key),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.maxFinite,
          child: Row(
            children: [
              if (widget.allowDelete)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, const CategoryEditResult.delete()),
                  child: const Text('Eliminar', style: TextStyle(color: AppColors.expense)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Resultado de un diálogo de categoría: guardar cambios o eliminarla.
class CategoryEditResult {
  final CategoryModel? category; // no-nulo cuando la acción fue "guardar"
  final bool isDelete;

  const CategoryEditResult.save(this.category) : isDelete = false;
  const CategoryEditResult.delete()
      : category = null,
        isDelete = true;
}

/// Muestra el diálogo y retorna la nueva categoría, o null si se cancela.
/// Las categorías no tienen tipo: sirven tanto para gastos como ingresos.
Future<CategoryModel?> showAddCategoryDialog(BuildContext context) async {
  final result = await showDialog<CategoryEditResult>(
    context: context,
    builder: (_) => const _CategoryDialog(
      title: 'Nueva categoría',
      confirmLabel: 'Crear',
    ),
  );
  return result?.category;
}

/// Muestra el diálogo para editar una categoría existente (incluidas las
/// que vienen por defecto). Retorna null si se cancela.
Future<CategoryEditResult?> showEditCategoryDialog(
  BuildContext context,
  CategoryModel category,
) {
  return showDialog<CategoryEditResult>(
    context: context,
    builder: (_) => _CategoryDialog(
      title: 'Editar categoría',
      confirmLabel: 'Guardar',
      initial: category,
      allowDelete: true,
    ),
  );
}

/// Confirma antes de eliminar definitivamente una categoría. Los
/// movimientos ya registrados con ella conservan su ícono guardado,
/// así que no se ven afectados.
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
