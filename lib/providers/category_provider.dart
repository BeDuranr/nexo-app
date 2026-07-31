import 'package:flutter/foundation.dart';

import '../db/db_helper.dart';
import '../models/category_model.dart';

class CategoryProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper.instance;

  List<CategoryModel> _categories = [];
  bool _loading = false;

  // Todas las categorías sirven tanto para gastos como para ingresos:
  // no se filtran por tipo de movimiento.
  List<CategoryModel> get categories => _categories;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _categories = await _db.getCategories();
    _loading = false;
    notifyListeners();
  }

  Future<void> addCategory(CategoryModel category) async {
    await _db.insertCategory(category);
    await load();
  }

  Future<void> updateCategory(CategoryModel category) async {
    await _db.updateCategory(category);
    await load();
  }

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    await load();
  }
}
