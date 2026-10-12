import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

class OtaService {
  static const String api =
      'https://api.github.com/repos/trungto1528/ttcs-flutter/releases/latest';

  // Trang GitHub Release mở khi cập nhật trên Windows.
  static const String windowsReleaseUrl =
      'https://github.com/trungto1528/ttcs-flutter/releases/latest';

  Future<Map<String, dynamic>> getLocalVersion() async {
    final info = await PackageInfo.fromPlatform();

    return {
      'versionName': info.version,
      'buildNumber': int.tryParse(info.buildNumber) ?? 0,
    };
  }

  Map<String, dynamic> _parseTag(String tag) {
    final clean = tag.startsWith('v') ? tag.substring(1) : tag;
    final parts = clean.split('+');

    return {
      'versionName': parts[0],
      'buildNumber': parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    };
  }

  Future<Map<String, dynamic>?> checkUpdate() async {
    try {
      final res = await http.get(
        Uri.parse(api),
        headers: {'Accept': 'application/vnd.github+json'},
      );

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final parsed = _parseTag(data['tag_name']?.toString() ?? '');

      // Windows chỉ cần thông tin phiên bản và trang release.
      if (Platform.isWindows) {
        return {
          'versionName': parsed['versionName'],
          'buildNumber': parsed['buildNumber'],
          'releaseUrl': windowsReleaseUrl,
          'fileName': 'GitHub Release',
        };
      }

      // Android: tìm APK phù hợp với kiến trúc thiết bị.
      if (Platform.isAndroid) {
        final assets = data['assets'] as List? ?? [];

        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final supportedAbis = androidInfo.supportedAbis;

        dynamic selectedApk;

        for (final abi in supportedAbis) {
          selectedApk = assets.cast<dynamic>().firstWhere(
            (e) =>
                e['name'].toString().contains(abi.toString()) &&
                e['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );

          if (selectedApk != null) break;
        }

        selectedApk ??= assets.cast<dynamic>().firstWhere(
          (e) => e['name'].toString().endsWith('.apk'),
          orElse: () => null,
        );

        if (selectedApk == null) return null;

        return {
          'versionName': parsed['versionName'],
          'buildNumber': parsed['buildNumber'],
          'url': selectedApk['browser_download_url'],
          'fileName': selectedApk['name'],
          'releaseUrl': windowsReleaseUrl,
        };
      }

      return null;
    } catch (e) {
      debugPrint('Lỗi kiểm tra cập nhật: $e');
      return null;
    }
  }

  bool _isNewer(Map remote, Map local) {
    try {
      final remoteVersion = Version.parse(remote['versionName'].toString());
      final localVersion = Version.parse(local['versionName'].toString());

      if (remoteVersion > localVersion) return true;

      if (remoteVersion == localVersion) {
        return (remote['buildNumber'] as int) > (local['buildNumber'] as int);
      }

      return false;
    } catch (_) {
      return (remote['buildNumber'] as int) > (local['buildNumber'] as int);
    }
  }

  Future<void> checkAndUpdate(BuildContext context) async {
    final remote = await checkUpdate();
    final local = await getLocalVersion();

    if (!context.mounted) return;

    if (remote == null) {
      _showErrorDialog(
        context,
        'Không thể kiểm tra cập nhật. '
        'Vui lòng kiểm tra kết nối mạng hoặc GitHub Release.',
      );
      return;
    }

    if (!_isNewer(remote, local)) {
      _showNoUpdateDialog(context, local);
      return;
    }

    _showUpdateDialog(context, remote, local);
  }

  void _showNoUpdateDialog(BuildContext context, Map local) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kiểm tra cập nhật'),
        content: Text(
          'Ứng dụng đã ở phiên bản mới nhất.\n\n'
          'Phiên bản hiện tại: ${local['versionName']}'
          '+${local['buildNumber']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kiểm tra cập nhật'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, Map remote, Map local) {
    double progress = 0;
    bool downloading = false;
    String? errorMessage;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Có phiên bản mới'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phiên bản hiện tại: '
                  '${local['versionName']}+${local['buildNumber']}',
                ),
                const SizedBox(height: 8),
                Text(
                  'Phiên bản mới: '
                  '${remote['versionName']}+${remote['buildNumber']}',
                ),
                const SizedBox(height: 8),
                Text('Tệp: ${remote['fileName']}'),
                if (downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(0)}%'),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: downloading ? null : () => Navigator.pop(ctx),
                child: const Text('Để sau'),
              ),
              FilledButton(
                onPressed: downloading
                    ? null
                    : () async {
                        // Windows: mở trang release trên GitHub.
                        if (Platform.isWindows) {
                          final uri = Uri.parse(windowsReleaseUrl);
                          final opened = await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );

                          if (!opened && ctx.mounted) {
                            setDialogState(() {
                              errorMessage =
                                  'Không thể mở trình duyệt. '
                                  'Hãy truy cập: $windowsReleaseUrl';
                            });
                          }
                          return;
                        }

                        // Android: tải APK và mở trình cài đặt.
                        await _startDownload(
                          ctx,
                          remote['url'].toString(),
                          (value) {
                            if (ctx.mounted) {
                              setDialogState(() {
                                progress = value;
                              });
                            }
                          },
                          () {
                            if (ctx.mounted) {
                              setDialogState(() {
                                downloading = true;
                                errorMessage = null;
                              });
                            }
                          },
                          () {
                            if (ctx.mounted) {
                              setDialogState(() {
                                downloading = false;
                              });
                            }
                          },
                          (message) {
                            if (ctx.mounted) {
                              setDialogState(() {
                                downloading = false;
                                errorMessage = message;
                              });
                            }
                          },
                        );
                      },
                child: Text(downloading ? 'Đang tải...' : 'Cập nhật ngay'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startDownload(
    BuildContext context,
    String url,
    Function(double) onProgress,
    Function() onStart,
    Function() onDone,
    Function(String) onError,
  ) async {
    try {
      final status = await Permission.requestInstallPackages.request();

      if (!status.isGranted) {
        onError('Bạn cần cấp quyền cài đặt ứng dụng.');
        return;
      }

      onStart();

      final dir = await getExternalStorageDirectory();

      if (dir == null) {
        onDone();
        onError('Không tìm thấy thư mục tải tệp.');
        return;
      }

      final path = '${dir.path}/update.apk';
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
      }

      final dio = Dio();

      await dio.download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
      );

      onDone();
      await OpenFile.open(path);
    } catch (e) {
      onDone();
      onError('Lỗi cập nhật: $e');
    }
  }

  Future<void> cleanUpOldApk() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;

      final file = File('${dir.path}/update.apk');

      if (await file.exists()) {
        await file.delete();
        debugPrint('Đã xóa file APK cập nhật cũ.');
      }
    } catch (e) {
      debugPrint('Lỗi xóa APK cũ: $e');
    }
  }
}
