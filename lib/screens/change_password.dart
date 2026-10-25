import 'package:flutter/material.dart';
import '../services/auth.dart';
class ChangePasswordScreen extends StatefulWidget {
  final String username;
  const ChangePasswordScreen({super.key, required this.username});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}
class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final oldController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  bool isLoading = false;
  Future<void> _changePassword() async {
    final oldPass = oldController.text;
    final newPass = newController.text;
    final confirmPass = confirmController.text;
    if (newPass != confirmPass) {
      _showMessage("Mật khẩu xác nhận không khớp");
      return;
    }
    if (newPass.length < 6) {
      _showMessage("Mật khẩu phải >= 6 ký tự");
      return;
    }
    if(oldPass==newPass){
      _showMessage("Mật khẩu mới phải khác mật khẩu cũ");
      return;
    }
    setState(() => isLoading = true);
    final response = await Auth().changePassword(
      widget.username,
      oldPass,
      newPass,
    );
    if (response == "OK") {
      _showMessage("Đổi mật khẩu thành công");
      Navigator.pop(context);
    } else {
      _showMessage(response);
    }
    setState(() => isLoading = false);
  }
  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
  Widget _buildTextField(String hint, TextEditingController controller) {
    return TextField(
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đổi mật khẩu")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTextField("Mật khẩu cũ", oldController),
            const SizedBox(height: 16),
            _buildTextField("Mật khẩu mới", newController),
            const SizedBox(height: 16),
            _buildTextField("Xác nhận mật khẩu", confirmController),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _changePassword,
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Đổi mật khẩu"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
