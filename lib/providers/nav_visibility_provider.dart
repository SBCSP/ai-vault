import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defines a sidebar navigation destination.
class NavDestination {
  final int id;
  final String label;
  final bool isSystem; // System items can't be toggled off

  const NavDestination({
    required this.id,
    required this.label,
    this.isSystem = false,
  });
}

/// All available sidebar destinations in display order.
/// IDs match the IndexedStack indices in shell_screen.dart.
const allNavDestinations = [
  NavDestination(id: 0, label: 'Dashboard', isSystem: true),
  NavDestination(id: 1, label: 'AI Chat', isSystem: true),
  NavDestination(id: 2, label: 'Secrets'),
  NavDestination(id: 3, label: 'Notes'),
  NavDestination(id: 4, label: 'Ideas'),
  NavDestination(id: 5, label: 'Documents'),
  NavDestination(id: 6, label: 'Chat History'),
  NavDestination(id: 7, label: 'Servers'),
  NavDestination(id: 8, label: 'Wiki'),
  NavDestination(id: 9, label: 'Settings', isSystem: true),
];

const _prefsKey = 'nav_hidden_ids';

/// Tracks which nav item IDs are hidden.
/// System items (Dashboard, AI Chat, Settings) are never hidden.
class NavVisibilityNotifier extends StateNotifier<Set<int>> {
  NavVisibilityNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList(_prefsKey);
    if (hidden != null) {
      state = hidden.map(int.parse).toSet();
    }
  }

  Future<void> toggle(int id) async {
    // Don't allow toggling system items
    final dest = allNavDestinations.firstWhere((d) => d.id == id);
    if (dest.isSystem) return;

    final updated = {...state};
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      updated.map((e) => e.toString()).toList(),
    );
  }

  bool isVisible(int id) => !state.contains(id);
}

final navVisibilityProvider =
    StateNotifierProvider<NavVisibilityNotifier, Set<int>>(
  (ref) => NavVisibilityNotifier(),
);

/// Convenience: returns the list of visible destinations (filtered).
final visibleNavDestinationsProvider = Provider<List<NavDestination>>((ref) {
  final hidden = ref.watch(navVisibilityProvider);
  return allNavDestinations.where((d) => !hidden.contains(d.id)).toList();
});
