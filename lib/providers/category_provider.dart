import 'package:flutter/foundation.dart';

import '../db/db_helper.dart';
import '../models/category_model.dart';

class CategoryProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper.instance;

  List<CategoryModel> _categories = [];
  bool _loading = false;
  String? _lastError;

  // Todas las categorías sirven tanto para gastos como para ingresos:
  // no se filtran por tipo de movimiento.
  List<CategoryModel> get categories => _categories;
  bool get loading => _loading;
  String? get lastError => _lastError;

  /// Categoría viva con ese id, o null si fue eliminada. Las pantallas
  /// guardan el id (no una copia del modelo) y resuelven acá, para no
  /// quedarse con un nombre o ícono desactualizado tras una edición.
  CategoryModel? byId(int? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _categories = await _db.getCategories();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> _write(Future<void> Function() action) async {
    try {
      await action();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
    await load();
    return true;
  }

  Future<bool> addCategory(CategoryModel category) {
    return _write(() => _db.insertCategory(category));
  }

  /// Además de la categoría, actualiza el nombre y el ícono copiados en
  /// los movimientos que la usan (ver `DBHelper.updateCategory`). Quien
  /// llame debe recargar `TransactionProvider` para reflejarlo.
  Future<bool> updateCategory(CategoryModel category) {
    return _write(() => _db.updateCategory(category));
  }

  Future<bool> deleteCategory(int id) {
    return _write(() => _db.deleteCategory(id));
  }
}
