import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default categories that always ship with the app and cannot be removed.
const defaultCategories = [
  'General',
  'Login',
  'API Key',
  'Credit Card',
  'SSH Key',
  'WiFi',
];

final categoryProvider =
    StateNotifierProvider<CategoryNotifier, List<String>>((ref) {
  return CategoryNotifier();
});

class CategoryNotifier extends StateNotifier<List<String>> {
  static const _storageKey = 'custom_categories';

  CategoryNotifier() : super([...defaultCategories]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getStringList(_storageKey) ?? [];
    // Merge defaults + custom, preserving order and avoiding duplicates
    final merged = [...defaultCategories];
    for (final c in custom) {
      if (!merged.contains(c)) {
        merged.add(c);
      }
    }
    state = merged;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // Only persist the non-default ones
    final custom =
        state.where((c) => !defaultCategories.contains(c)).toList();
    await prefs.setStringList(_storageKey, custom);
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (state.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;
    state = [...state, trimmed];
    await _save();
  }

  Future<void> removeCategory(String name) async {
    // Don't allow removing defaults
    if (defaultCategories.contains(name)) return;
    state = state.where((c) => c != name).toList();
    await _save();
  }

  bool isDefault(String name) => defaultCategories.contains(name);
}
