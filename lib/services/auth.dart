import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'app_preference.dart';
class Auth {
  Future<String> login(String username, String password) async {
    final res = await http.post(
      Uri.parse(
          "${ApiConfig.api}/auth/login"
      ),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );
    if (res.statusCode == 200) {
      final prefs = await AppPreferences.getInstance();
      await prefs.setString("user", res.body);
      return "Logged In";
    } else {
      return res.body;
    }
  }
  Future<String> register(
    String username,
    String password,
    String displayName,
  ) async {
    final res = await http.post(
      Uri.parse("${ApiConfig.api}/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": username,
        "password": password,
        'displayName': displayName,
      }),
    );
    if (res.statusCode == 200) {
      return "OK";
    } else {
      return res.body;
    }
  }
  Future<String> changePassword(
    String username,
    String oldPass,
    String newPass,
  ) async {
    final uri =
        Uri.parse(
          "${ApiConfig.api}/users/change-password",
        ).replace(
          queryParameters: {
            "username": username,
            "oldPassword": oldPass,
            "newPassword": newPass,
          },
        );
    final res = await http.post(uri);
    return res.body;
  }
  Future<String> fetchUser(int userId) async {
    final res = await http.get(
      Uri.parse("${ApiConfig.api}/auth/fetch/$userId"),
    );
    return res.body;
  }
  Future<String> updateDisplayName(int userId, String newName) async {
    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.api}/users/$userId/displayName"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "displayName": newName,
        }),
      );
      if (response.statusCode == 200) {
        return "OK";
      } else {
        return jsonDecode(response.body)["message"] ?? "Lỗi server";
      }
    } catch (e) {
      return "Lỗi kết nối";
    }
  }
}
