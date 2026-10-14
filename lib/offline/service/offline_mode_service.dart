
import 'package:flutter/foundation.dart';

import '../../services/app_preference.dart';

class OfflineModeService {
  OfflineModeService._();

  static const String _preferenceKey = 'offlineMode';

  static final ValueNotifier<bool> isOffline =
  ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    final prefs = await AppPreferences.getInstance();

    isOffline.value = prefs.getBool(_preferenceKey) ?? false;
  }

  static Future<void> setOffline(bool enabled) async {
    final prefs = await AppPreferences.getInstance();

    await prefs.setBool(_preferenceKey, enabled);
    isOffline.value = enabled;
  }
}
