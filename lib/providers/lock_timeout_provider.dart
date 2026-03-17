import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider.dart';

/// Available lock timeout options.
enum LockTimeout {
  intense(Duration(minutes: 1), '1 min', 'Intense'),
  fait(Duration(minutes: 5), '5 min', 'Fait'),
  chillin(Duration(minutes: 10), '10 min', 'Chillin'),
  loco(Duration(minutes: 30), '30 min', 'Loco'),
  never(Duration.zero, 'Never', 'Never');

  final Duration duration;
  final String label;
  final String subtitle;

  const LockTimeout(this.duration, this.label, this.subtitle);
}

/// Persists and exposes the chosen lock timeout.
final lockTimeoutProvider =
    StateNotifierProvider<LockTimeoutNotifier, LockTimeout>((ref) {
  return LockTimeoutNotifier();
});

class LockTimeoutNotifier extends StateNotifier<LockTimeout> {
  LockTimeoutNotifier() : super(LockTimeout.fait) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('lock_timeout');
    if (saved != null) {
      final match = LockTimeout.values
          .where((t) => t.name == saved)
          .firstOrNull;
      if (match != null) state = match;
    }
  }

  Future<void> setTimeout(LockTimeout timeout) async {
    state = timeout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lock_timeout', timeout.name);
  }
}

/// Manages the inactivity timer that auto-locks the vault.
/// Should be created once at the app root and attached to the
/// widget tree via [WidgetsBindingObserver].
final lockTimerProvider =
    StateNotifierProvider<LockTimerNotifier, bool>((ref) {
  return LockTimerNotifier(ref);
});

class LockTimerNotifier extends StateNotifier<bool>
    with WidgetsBindingObserver {
  final Ref _ref;
  Timer? _timer;

  LockTimerNotifier(this._ref) : super(false) {
    WidgetsBinding.instance.addObserver(this);
    _startTimer();

    // Re-start timer when timeout setting changes
    _ref.listen<LockTimeout>(lockTimeoutProvider, (_, __) {
      _startTimer();
    });

    // Reset timer when auth state changes to unlocked
    _ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (next.status == AuthStatus.unlocked) {
        _startTimer();
      } else {
        _cancelTimer();
      }
    });
  }

  @override
  void dispose() {
    _cancelTimer();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called when app lifecycle changes (background/foreground).
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.resumed) {
      // App came back to foreground — restart timer
      _startTimer();
    } else if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden) {
      // App went to background — keep timer running
      // (it will lock even in background)
    }
  }

  /// Call this on any user interaction to reset the timer.
  void resetTimer() {
    final auth = _ref.read(authStateProvider);
    if (auth.status == AuthStatus.unlocked) {
      _startTimer();
    }
  }

  void _startTimer() {
    _cancelTimer();

    final timeout = _ref.read(lockTimeoutProvider);
    if (timeout == LockTimeout.never) return;

    final auth = _ref.read(authStateProvider);
    if (auth.status != AuthStatus.unlocked) return;

    _timer = Timer(timeout.duration, () {
      final currentAuth = _ref.read(authStateProvider);
      if (currentAuth.status == AuthStatus.unlocked) {
        _ref.read(authStateProvider.notifier).lock();
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
