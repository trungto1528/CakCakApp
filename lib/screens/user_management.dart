import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:novel_app/config/api_config.dart';
import '../services/user_service.dart';
class AdminUserManagerScreen extends StatefulWidget {
  final int adminId;
  const AdminUserManagerScreen({
    super.key,
    required this.adminId,
  });
  @override
  State<AdminUserManagerScreen> createState() =>
      _AdminUserManagerScreenState();
}
class _AdminUserManagerScreenState
    extends State<AdminUserManagerScreen> {
  List users = [];
  bool isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadUsers();
  }
  Future<void> _loadUsers() async {
    try {
      final data =
      await UserFetcher().getAllUsers(widget.adminId);
      setState(() {
        users = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e")),
        );
      }
    }
  }
  Future<void> _changeRole(
      int userId,
      String role,
      ) async {
    try {
      await UserFetcher().changeRole(
        widget.adminId,
        userId,
        role,
      );
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Đổi role thành công"),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e")),
      );
    }
  }
  Future<void> _toggleApprove(int userId) async {
    try {
      await UserFetcher().toggleApprove(
        widget.adminId,
        userId,
      );
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cập nhật thành công"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e")),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Quản lý người dùng"),
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: _loadUsers,
        child: ListView.builder(
          itemCount: users.length,
          itemBuilder: (_, index) {
            final user = users[index];
            return Card(
              margin: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: CachedNetworkImageProvider(
                        "${ApiConfig.avatarImage}/${user['avatarUrl']}",
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['displayName'] ?? user['username'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user['username'],
                            style: TextStyle(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text("Role: "),
                              DropdownButton<String>(
                                value: user['role'],
                                underline: const SizedBox(),
                                items: const [
                                  DropdownMenuItem(
                                    value: "USER",
                                    child: Text("USER"),
                                  ),
                                  DropdownMenuItem(
                                    value: "ADMIN",
                                    child: Text("ADMIN"),
                                  ),
                                ],
                                onChanged: user['userId'] == widget.adminId
                                    ? null
                                    : (value) {
                                  if (value != null) {
                                    _changeRole(
                                      user['userId'],
                                      value,
                                    );
                                  }
                                },
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: user['isApproved']
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                          user['userId'] != widget.adminId?(
                            user['isApproved']
                                ? "Đã duyệt"
                                : "Chờ duyệt"):"",
                            style: TextStyle(
                              color: user['isApproved']
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Chính mình
                        if (user['userId'] == widget.adminId)
                          const Chip(
                            label: Text("Bản thân"),
                          )
                        // User thường
                        else if (user['role'] == 'USER')
                          SizedBox(
                            height: 36,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _toggleApprove(user['userId']),
                              icon: Icon(
                                user['isApproved']
                                    ? Icons.lock
                                    : Icons.verified_user,
                                size: 16,
                              ),
                              label: Text(
                                user['isApproved']
                                    ? "Thu hồi"
                                    : "Duyệt",
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                            ),
                          )
                        // Admin khác
                        else
                          const Chip(
                            label: Text("ADMIN"),
                          ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}