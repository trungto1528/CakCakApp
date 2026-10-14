import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'windows_storage_manager.dart';

class WindowsStorageSetupScreen extends StatefulWidget {
  final Future<void> Function() onConfigured;

  const WindowsStorageSetupScreen({super.key, required this.onConfigured});

  @override
  State<WindowsStorageSetupScreen> createState() =>
      _WindowsStorageSetupScreenState();
}

class _WindowsStorageSetupScreenState extends State<WindowsStorageSetupScreen> {
  bool _isSelecting = false;
  String? _errorMessage;

  Future<void> _selectDirectory() async {
    if (_isSelecting) return;

    setState(() {
      _isSelecting = true;
      _errorMessage = null;
    });

    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Chọn thư mục lưu trữ dữ liệu Novel App',
      );

      // Người dùng đóng hộp thoại hoặc bấm Cancel.
      if (selectedPath == null) return;

      await WindowsStorageManager.configureRoot(selectedPath);

      if (!mounted) return;

      await widget.onConfigured();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Không thể sử dụng thư mục đã chọn.\n'
            'Hãy chọn thư mục khác hoặc kiểm tra quyền ghi.\n\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSelecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_open, size: 72),
                const SizedBox(height: 24),
                Text(
                  'Chọn thư mục lưu trữ',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Chọn một thư mục để lưu cài đặt, dữ liệu '
                  'và truyện tải offline của ứng dụng.\n\n'
                  'Bạn nên chọn một thư mục có quyền đọc và ghi, '
                  'ví dụ D:\\NovelAppData. '
                  'Không nên chọn thư mục cài đặt Windows.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSelecting ? null : _selectDirectory,
                    icon: _isSelecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder),
                    label: Text(
                      _isSelecting ? 'Đang thiết lập...' : 'Chọn thư mục',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
