import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Trạng thái Online/Offline dùng chung cho toàn ứng dụng.
///
/// Mặc định isOffline = false, nghĩa là Online.
class OfflineModeService {
  OfflineModeService._();

  static const String _preferenceKey = 'offlineMode';

  static final ValueNotifier<bool> isOffline = ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    // Chưa có thiết lập thì mặc định tắt Offline.
    isOffline.value = prefs.getBool(_preferenceKey) ?? false;
  }

  static Future<void> setOffline(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey, enabled);
    isOffline.value = enabled;
  }
}
