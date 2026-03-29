import 'package:flutter_riverpod/flutter_riverpod.dart';

const String appVersion = '1.2.0';

final appVersionProvider = Provider<String>((ref) => appVersion);
