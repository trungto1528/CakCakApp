
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

  static const String windowsReleaseUrl =
      'https://github.com/trungto1528/ttcs-flutter/releases/latest';

  static const Duration requestTimeout = Duration(seconds: 20);

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
      'buildNumber': parts.length > 1
          ? int.tryParse(parts[1]) ?? 0
          : 0,
    };
  }

  Future<Map<String, dynamic>?> checkUpdate() async {
    try {
      debugPrint('[OTA] Bắt đầu gọi GitHub API');

      final res = await http
          .get(
        Uri.parse(api),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'novel-app-ota',
        },
      )
          .timeout(requestTimeout);

      debugPrint('[OTA] GitHub API status: ${res.statusCode}');

      if (res.statusCode != 200) {
        debugPrint('[OTA] GitHub API error: ${res.body}');
        return null;
      }

      final List releases = jsonDecode(res.body) as List;

      final parsedReleases = <Map<String, dynamic>>[];

      for (final item in releases) {
        if (item is! Map) continue;

        final tagName = item['tag_name']?.toString() ?? '';

        if (tagName.isEmpty) continue;

        final parsed = _parseTag(tagName);

        parsedReleases.add({
          ...parsed,
          'body': item['body']?.toString() ?? '',
          'tag_name': tagName,
          'html_url': item['html_url']?.toString() ?? '',
          'assets': item['assets'] ?? [],
        });
      }

      if (parsedReleases.isEmpty) {
        debugPrint('[OTA] Không tìm thấy release hợp lệ');
        return null;
      }

      // Sắp xếp release theo build number giảm dần.
      parsedReleases.sort(
            (a, b) => (b['buildNumber'] as int)
            .compareTo(a['buildNumber'] as int),
      );

      final remote = parsedReleases.first;

      debugPrint(
        '[OTA] Phiên bản GitHub: '
            '${remote['versionName']}+${remote['buildNumber']}',
      );

      final local = await getLocalVersion();

      final localBuild = local['buildNumber'] as int;
      final remoteBuild = remote['buildNumber'] as int;

      // Lấy changelog của tất cả build mới hơn bản hiện tại.
      // Sắp xếp từ mới nhất đến cũ nhất.
      final List<Map<String, dynamic>> changelogs = [];

      if (remoteBuild > localBuild) {
        final relevant = parsedReleases.where((release) {
          final buildNumber = release['buildNumber'] as int;
          return buildNumber > localBuild &&
              buildNumber <= remoteBuild;
        }).toList();

        relevant.sort(
              (a, b) => (b['buildNumber'] as int)
              .compareTo(a['buildNumber'] as int),
        );

        for (final release in relevant) {
          final body = (release['body'] as String?)?.trim() ?? '';

          if (body.isEmpty) continue;

          changelogs.add({
            'versionName': release['versionName'],
            'buildNumber': release['buildNumber'],
            'tagName': release['tag_name'],
            'body': body,
          });
        }
      }

      // Windows chỉ cần thông tin phiên bản và trang release.
      if (Platform.isWindows) {
        return {
          'versionName': remote['versionName'],
          'buildNumber': remote['buildNumber'],
          'releaseUrl': windowsReleaseUrl,
          'fileName': 'GitHub Release',
          'changelogs': changelogs,
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

        // Nếu không có APK đúng ABI, lấy APK đầu tiên.
        selectedApk ??= assets.cast<dynamic>().firstWhere(
              (e) => e['name'].toString().endsWith('.apk'),
          orElse: () => null,
        );

        if (selectedApk == null) {
          debugPrint('[OTA] Không tìm thấy APK trong release');
          return null;
        }

        return {
          'versionName': remote['versionName'],
          'buildNumber': remote['buildNumber'],
          'url': selectedApk['browser_download_url'],
          'fileName': selectedApk['name'],
          'releaseUrl': windowsReleaseUrl,
          'changelogs': changelogs,
        };
      }

      debugPrint('[OTA] Nền tảng không được hỗ trợ');
      return null;
    } catch (e, s) {
      debugPrint('[OTA] Lỗi checkUpdate: $e');
      debugPrint('[OTA] Stack trace: $s');
      return null;
    }
  }

  bool _isNewer(Map remote, Map local) {
    try {
      return (remote['buildNumber'] as int) >
          (local['buildNumber'] as int);
    } catch (e) {
      debugPrint('[OTA] Lỗi so sánh phiên bản: $e');
      return false;
    }
  }

  Future<void> checkAndUpdate(BuildContext context) async {
    debugPrint('[OTA] Bắt đầu kiểm tra cập nhật');

    try {
      debugPrint('[OTA] Đang lấy thông tin phiên bản GitHub');

      final remote = await checkUpdate().timeout(requestTimeout);

      debugPrint('[OTA] Remote: $remote');

      debugPrint('[OTA] Đang lấy phiên bản hiện tại');

      final local = await getLocalVersion();

      debugPrint('[OTA] Local: $local');

      if (!context.mounted) {
        debugPrint('[OTA] Context không còn tồn tại');
        return;
      }

      if (remote == null) {
        debugPrint('[OTA] Không lấy được thông tin cập nhật');

        _showErrorDialog(
          context,
          'Không thể kiểm tra cập nhật.\n\n'
              'Vui lòng kiểm tra kết nối mạng hoặc GitHub Release.',
        );

        return;
      }

      if (!_isNewer(remote, local)) {
        debugPrint('[OTA] Ứng dụng đã ở phiên bản mới nhất');

        _showNoUpdateDialog(context, local);

        return;
      }

      debugPrint('[OTA] Phát hiện phiên bản mới');

      _showUpdateDialog(context, remote, local);
    } catch (e, s) {
      debugPrint('[OTA] Lỗi checkAndUpdate: $e');
      debugPrint('[OTA] Stack trace: $s');

      if (!context.mounted) return;

      _showErrorDialog(
        context,
        'Đã xảy ra lỗi khi kiểm tra cập nhật:\n\n$e',
      );
    }
  }

  void _showNoUpdateDialog(BuildContext context, Map local) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kiểm tra cập nhật'),
        content: Text(
          'Ứng dụng đã ở phiên bản mới nhất.\n\n'
              'Phiên bản hiện tại: '
              '${local['versionName']}+${local['buildNumber']}',
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
        content: SingleChildScrollView(
          child: Text(message),
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

  Widget _buildChangelog(List changelogs) {
    if (changelogs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Không có chi tiết lịch sử thay đổi.',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
      );
    }

    // Changelog đã được sắp xếp giảm dần.
    // Phần tử đầu tiên là bản mới nhất và tự động mở.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < changelogs.length; i++)
          ExpansionTile(
            key: PageStorageKey(
              'ota_changelog_${changelogs[i]['buildNumber']}',
            ),
            initiallyExpanded: i == 0,
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              'Build ${changelogs[i]['buildNumber']}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${changelogs[i]['versionName']}',
              style: const TextStyle(fontSize: 11),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: MarkdownBody(
                  data: changelogs[i]['body']?.toString() ?? '',
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
            ],
          ),
      ],
    );
  }

  void _showUpdateDialog(
      BuildContext context,
      Map remote,
      Map local,
      ) {
    double progress = 0;
    bool downloading = false;
    String? errorMessage;

    final List changelogs = remote['changelogs'] as List? ?? [];

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Có phiên bản mới'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 550,
                maxWidth: 500,
              ),
              child: Column(
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
                  const SizedBox(height: 12),
                  const Text(
                    'Lịch sử thay đổi:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Vùng changelog có chiều cao cố định và cuộn riêng.
                  Flexible(
                    child: SingleChildScrollView(
                      child: _buildChangelog(changelogs),
                    ),
                  ),

                  if (downloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                    ),
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
            ),
            actions: [
              TextButton(
                onPressed: downloading
                    ? null
                    : () => Navigator.pop(ctx),
                child: const Text('Để sau'),
              ),
              FilledButton(
                onPressed: downloading
                    ? null
                    : () async {
                  // Windows: mở trang GitHub Release.
                  if (Platform.isWindows) {
                    try {
                      final uri = Uri.parse(windowsReleaseUrl);

                      final opened = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );

                      if (!opened && ctx.mounted) {
                        setDialogState(() {
                          errorMessage =
                          'Không thể mở trình duyệt.\n'
                              'Hãy truy cập: $windowsReleaseUrl';
                        });
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        setDialogState(() {
                          errorMessage =
                          'Lỗi mở GitHub Release: $e';
                        });
                      }
                    }

                    return;
                  }

                  // Android: tải APK và mở trình cài đặt.
                  final downloadUrl =
                  remote['url']?.toString();

                  if (downloadUrl == null ||
                      downloadUrl.isEmpty) {
                    setDialogState(() {
                      errorMessage =
                      'Không tìm thấy đường dẫn APK.';
                    });
                    return;
                  }

                  await _startDownload(
                    ctx,
                    downloadUrl,
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
                child: Text(
                  downloading ? 'Đang tải...' : 'Cập nhật ngay',
                ),
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
      final status =
      await Permission.requestInstallPackages.request();

      if (!status.isGranted) {
        onError('Bạn cần cấp quyền cài đặt ứng dụng.');

        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }

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
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 2),
        ),
      );

      onDone();

      debugPrint('[OTA] Tải APK thành công: $path');

      await OpenFile.open(path);
    } catch (e, s) {
      debugPrint('[OTA] Lỗi tải/cài APK: $e');
      debugPrint('[OTA] Stack trace: $s');

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
        debugPrint('[OTA] Đã xóa file APK cập nhật cũ.');
      }
    } catch (e) {
      debugPrint('[OTA] Lỗi xóa APK cũ: $e');
    }
  }
}
