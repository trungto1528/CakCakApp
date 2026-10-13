import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineModeService {
  OfflineModeService._();

  static const String _preferenceKey = 'offlineMode';

  /// false = Online, true = Offline.
  /// Mặc định ứng dụng chạy Online.
  static final ValueNotifier<bool> isOffline =
  ValueNotifier<bool>(false);

  /// Khôi phục trạng thái khi mở ứng dụng.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    isOffline.value = prefs.getBool(_preferenceKey) ?? false;
  }

  /// Cập nhật và lưu trạng thái.
  static Future<void> setOffline(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_preferenceKey, enabled);
    isOffline.value = enabled;
  }
}