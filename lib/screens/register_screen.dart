import 'package:flutter/material.dart';
import '../services/auth.dart';
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}
class _RegisterScreenState extends State<RegisterScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final displayNameController = TextEditingController();
  String? error;
  bool isLoading = false;
  Future<void> _register() async {
    setState(() {
      error = null;
    });
    if (displayNameController.text.isEmpty ||
        usernameController.text.isEmpty ||
        passwordController.text.isEmpty) {
      setState(() {
        error = "Vui lòng nhập đầy đủ thông tin";
      });
      return;
    }
    if (passwordController.text != confirmController.text) {
      setState(() {
        error = "Mật khẩu không khớp";
      });
      return;
    }
    setState(() {
      isLoading = true;
    });
    try {
      final res = await Auth().register(
        usernameController.text,
        passwordController.text,
        displayNameController.text,
      );
      if (res == "OK") {
        if (!mounted) return;
        Navigator.pop(context,true);
      } else {
        setState(() {
          error = res;
        });
      }
    } catch (e) {
      setState(() {
        error = "Lỗi kết nối server";
      });
    }
    setState(() {
      isLoading = false;
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đăng ký")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const SizedBox(height: 20),
            const Text(
              "Tạo tài khoản",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(
                labelText: "Tên hiển thị",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: "Tên đăng nhập",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Mật khẩu",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Xác nhận mật khẩu",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: isLoading ? null : _register,
              child: isLoading
                  ? const CircularProgressIndicator()
                  : const Text("Đăng ký"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // quay lại login
              },
              child: const Text("Đã có tài khoản? Đăng nhập"),
            ),
          ],
        ),
      ),
    );
  }
}
