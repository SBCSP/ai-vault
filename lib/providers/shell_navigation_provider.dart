import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the active sidebar section.
/// 0=Dashboard, 1=Secrets, 2=Notes, 3=Ideas, 4=Documents,
/// 5=AI Chat, 6=Chat History, 7=Servers, 8=Wiki, 9=Settings
final shellNavigationProvider = StateProvider<int>((ref) => 0);
