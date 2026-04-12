import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';

import 'providers/auth_provider.dart';
import 'providers/lock_timeout_provider.dart';
import 'screens/lock_screen.dart';
import 'screens/shell_screen.dart';
import 'src/rust/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise the Rust bridge.  If the native dylib is not found (e.g. the
  // crate hasn't been compiled yet), we continue in SQLite-only mode.
  try {
    await RustLib.init();
  } catch (e) {
    debugPrint('[LanceDB] Rust bridge unavailable — SQLite fallback active: $e');
  }
  runApp(const ProviderScope(child: AiVaultApp()));
}

class AiVaultApp extends ConsumerStatefulWidget {
  const AiVaultApp({super.key});

  @override
  ConsumerState<AiVaultApp> createState() => _AiVaultAppState();
}

class _AiVaultAppState extends ConsumerState<AiVaultApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // Initialize the lock timer provider so it starts observing
    ref.watch(lockTimerProvider);

    // When vault locks, pop all routes back to root so the lock screen shows
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.status == AuthStatus.unlocked &&
          next.status != AuthStatus.unlocked) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => ref.read(lockTimerProvider.notifier).resetTimer(),
      onPanDown: (_) => ref.read(lockTimerProvider.notifier).resetTimer(),
      child: MaterialApp(
        title: 'AI VaultIO',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: authState.status == AuthStatus.unlocked
            ? const ShellScreen()
            : const LockScreen(),
      ),
    );
  }
}
