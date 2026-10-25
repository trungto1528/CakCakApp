import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
class UserFetcher {
  Future<List<dynamic>> getAllUsers(int adminId) async {
    final response = await http.get(
      Uri.parse("${ApiConfig.api}/users/all"),
      headers: {"userId": "$adminId"},
    );
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
    return jsonDecode(response.body);
  }
  Future<void> toggleApprove(int adminId, int userId) async {
    final response = await http.put(
      Uri.parse("${ApiConfig.api}/users/$userId/toggle-approve"),
      headers: {"userId": "$adminId"},
    );
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }
  Future<void> changeRole(
      int adminId,
      int userId,
      String role,
      ) async {
    final response = await http.put(
      Uri.parse("${ApiConfig.api}/users/$userId/role"),
      headers: {
        "Content-Type": "application/json",
        "adminId": adminId.toString(),
      },
      body: jsonEncode({
        "role": role,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }
}
