import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
class OtaService {
  static const String api =
      'https://api.github.com/repos/trungto1528/ttcs-flutter/releases?per_page=100';
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
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'novel-app-ota',
        },
      );
      if (res.statusCode != 200) return null;
      final List releases = jsonDecode(res.body) as List;
      final parsedReleases = <Map<String, dynamic>>[];
      for (final item in releases) {
        if (item is! Map) continue;
        final parsed = _parseTag(item['tag_name']?.toString() ?? '');
        parsedReleases.add({
          ...parsed,
          'body': item['body']?.toString() ?? '',
          'tag_name': item['tag_name']?.toString() ?? '',
          'html_url': item['html_url']?.toString() ?? '',
          'assets': item['assets'] ?? [],
        });
      }
      if (parsedReleases.isEmpty) return null;
      // Sắp xếp theo build number giảm dần, phần tử đầu là phiên bản mới nhất.
      parsedReleases.sort(
          (a, b) => (b['buildNumber'] as int).compareTo(a['buildNumber'] as int));
      final remote = parsedReleases.first;
      final local = await getLocalVersion();
      // Tổng hợp changelog từ build sau bản đã cài đặt lên đến bản mới nhất.
      String combinedChangelog = '';
      final localBuild = local['buildNumber'] as int;
      final remoteBuild = remote['buildNumber'] as int;
      if (remoteBuild > localBuild) {
        final relevant = parsedReleases
            .where((r) {
              final bn = r['buildNumber'] as int;
              return bn > localBuild && bn <= remoteBuild;
            })
            .toList()
          ..sort((a, b) => (a['buildNumber'] as int).compareTo(b['buildNumber'] as int));
        for (final r in relevant) {
          final body = r['body'] as String?;
          if (body != null && body.isNotEmpty) {
            combinedChangelog += '### Build ${r['buildNumber']}\n$body\n\n';
          }
        }
      }
      // Windows chỉ cần thông tin phiên bản và trang release.
      if (Platform.isWindows) {
        return {
          'versionName': remote['versionName'],
          'buildNumber': remote['buildNumber'],
          'releaseUrl': windowsReleaseUrl,
          'fileName': 'GitHub Release',
          'changelog': combinedChangelog,
        };
      }
      // Android: tìm APK phù hợp với kiến trúc thiết bị.
      if (Platform.isAndroid) {
        final assets = remote['assets'] as List? ?? [];
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
          'versionName': remote['versionName'],
          'buildNumber': remote['buildNumber'],
          'url': selectedApk['browser_download_url'],
          'fileName': selectedApk['name'],
          'releaseUrl': windowsReleaseUrl,
          'changelog': combinedChangelog,
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
      return (remote['buildNumber'] as int) > (local['buildNumber'] as int);
    } catch (_) {
      return false;
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
                if (remote['changelog'] != null &&
                    (remote['changelog'] as String).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Lịch sử thay đổi:',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 200,
                    child: SingleChildScrollView(
                      child: Markdown(
                        data: remote['changelog'] as String,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(fontSize: 12),
                          h1: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          h2: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          h3: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
