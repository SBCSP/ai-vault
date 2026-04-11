import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'providers/lock_timeout_provider.dart';
import 'screens/lock_screen.dart';
import 'screens/shell_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: authState.status == AuthStatus.unlocked
            ? const ShellScreen()
            : const LockScreen(),
      ),
    );
  }
}
