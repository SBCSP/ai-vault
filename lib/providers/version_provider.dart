import 'package:flutter_riverpod/flutter_riverpod.dart';

const String appVersion = '1.3.3';

final appVersionProvider = Provider<String>((ref) => appVersion);
