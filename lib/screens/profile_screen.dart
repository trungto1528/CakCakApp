import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:novel_app/screens/user_management.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/User.dart';
import '../models/app_theme_mode.dart';
import '../services/auth.dart';
import '../services/ota.dart';
import 'admin_management.dart';
import 'change_password.dart';
import 'crawl_screen.dart';
import 'login_screen.dart';
import 'my_stories.dart';
import 'story_chapter_create.dart';

class ProfilePage extends StatefulWidget {
  final AppThemeMode currentMode;
  final Function(AppThemeMode) onThemeChanged;

  const ProfilePage({
    super.key,
    required this.currentMode,
    required this.onThemeChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');

      if (userStr == null) {
        if (!mounted) return;
        setState(() => user = null);
        return;
      }

      // Lấy ID từ thông tin user đã lưu.
      final savedUser = User.fromJson(jsonDecode(userStr));

      // Gọi API lấy thông tin mới nhất.
      final response = await Auth().fetchUser(savedUser.id);

      // Giải mã JSON từ backend.
      final Map<String, dynamic> userJson = jsonDecode(response);

      // Chuyển thành đối tượng User.
      final fetchedUser = User.fromJson(userJson);

      if (!mounted) return;

      setState(() {
        user = fetchedUser;
      });

      // Lưu thông tin mới nhất.
      await prefs.setString('user', jsonEncode(userJson));
    } catch (e) {
      debugPrint('Lỗi tải thông tin user: $e');
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');

    if (!mounted) return;

    setState(() {
      user = null;
    });
  }

  Future<void> _goLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );

    if (result == true) {
      await _loadUser();
    }
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Cài đặt',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),

              ListTile(
                leading: const Icon(Icons.dark_mode),
                title: const Text('Giao diện'),
                trailing: DropdownButton<AppThemeMode>(
                  value: widget.currentMode,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: AppThemeMode.light,
                      child: Text('Sáng'),
                    ),
                    DropdownMenuItem(
                      value: AppThemeMode.dark,
                      child: Text('Tối'),
                    ),
                    DropdownMenuItem(
                      value: AppThemeMode.system,
                      child: Text('Hệ thống'),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) {
                      widget.onThemeChanged(mode);
                    }
                  },
                ),
              ),

              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Đổi mật khẩu'),
                onTap: () {
                  final currentUser = user;
                  Navigator.pop(context);

                  if (currentUser == null) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChangePasswordScreen(username: currentUser.username),
                    ),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('Kiểm tra cập nhật'),
                onTap: () {
                  Navigator.pop(context);
                  OtaService().checkAndUpdate(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _changeAvatar() async {
    final currentUser = user;
    if (currentUser == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked == null || !mounted) return;

    final file = File(picked.path);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.api}/users/upload-avatar'),
      );

      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      request.fields['username'] = currentUser.username;

      final response = await request.send();

      if (response.statusCode == 200) {
        final fileName = await response.stream.bytesToString();

        currentUser.avatarUrl = '/$fileName';

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user', jsonEncode(currentUser.toJson()));

        if (!mounted) return;

        setState(() {
          user = currentUser;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật avatar thành công')),
        );
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lỗi upload avatar')));
    }
  }

  Future<void> _changeName() async {
    final currentUser = user;
    if (currentUser == null) return;

    final controller = TextEditingController(text: currentUser.displayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Đổi tên'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Tên hiển thị'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, controller.text);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName == null || newName.trim().isEmpty) return;

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.api}/users/${currentUser.id}/displayName'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'displayName': newName.trim()}),
      );

      if (res.statusCode == 200) {
        currentUser.displayName = newName.trim();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user', jsonEncode(currentUser.toJson()));

        if (!mounted) return;

        setState(() {
          user = currentUser;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đổi tên thành công')));
      } else {
        throw Exception(res.body);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }

  Widget _buildHeader() {
    final currentUser = user!;

    return Row(
      children: [
        GestureDetector(
          onTap: _changeAvatar,
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: '${ApiConfig.avatarImage}/${currentUser.avatarUrl}',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox(
                width: 72,
                height: 72,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => const Icon(Icons.person, size: 72),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      currentUser.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _changeName,
                    child: const Icon(Icons.edit, size: 18),
                  ),
                ],
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '@${currentUser.username}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getRoleColor(currentUser.role),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      currentUser.role,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.red),
          onPressed: logout,
        ),
      ],
    );
  }

  bool get isAdmin => user?.role.toUpperCase() == 'ADMIN';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài khoản'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user == null) ...[
            const SizedBox(height: 40),
            const Icon(Icons.person, size: 80),
            const SizedBox(height: 12),
            Center(
              child: ElevatedButton(
                onPressed: _goLogin,
                child: const Text('Đăng nhập'),
              ),
            ),
          ] else ...[
            _buildHeader(),
            const SizedBox(height: 20),

            _tile(Icons.add_box, 'Đăng nội dung', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StoryChapterScreen()),
              );
            }),

            _tile(Icons.menu_book, 'Truyện của tôi', () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MyStoriesScreen(userId: user!.id),
                ),
              );
            }),

            if (isAdmin)
              _tile(Icons.admin_panel_settings, 'Quản lý tất cả truyện', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminStoryManagerScreen(adminId: user!.id),
                  ),
                );
              }),

            if (isAdmin)
              _tile(Icons.people, 'Quản lý người dùng', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminUserManagerScreen(adminId: user!.id),
                  ),
                );
              }),

            if (isAdmin)
              _tile(Icons.cloud_download, 'Nhập truyện từ URL (Crawl)', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CrawlScreen(userId: user!.id),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}
