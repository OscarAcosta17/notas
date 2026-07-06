import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/notification_service.dart';

class UpdaterService {
  static const String repoOwner = 'OscarAcosta17';
  static const String repoName = 'notas';

  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      // 1. Get current version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., '1.0.0'

      // 2. Fetch latest release from GitHub
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestTag = data['tag_name']; // e.g., 'v1.1.0'
        
        // Clean tag name
        if (latestTag.startsWith('v')) {
          latestTag = latestTag.substring(1);
        }

        if (latestTag != currentVersion && _isNewer(currentVersion, latestTag)) {
          // 3. Find APK asset
          final assets = data['assets'] as List;
          String? downloadUrl;
          for (var asset in assets) {
            if (asset['name'].toString().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'];
              break;
            }
          }

          if (downloadUrl != null) {
            // Prompt user
            if (context.mounted) {
              _showUpdateDialog(context, latestTag, downloadUrl);
            }
          } else {
            if (context.mounted) _showNoUpdateDialog(context, "Nueva versión detectada, pero no hay APK adjunto en GitHub.");
          }
        } else {
          if (context.mounted) _showNoUpdateDialog(context, "Ya tienes la última versión instalada ($currentVersion).");
        }
      } else {
         if (context.mounted) _showNoUpdateDialog(context, "Error al consultar versiones. Revisa tu conexión a internet.");
      }
    } catch (e) {
       if (context.mounted) _showNoUpdateDialog(context, "Error buscando actualizaciones: $e");
    }
  }

  static Future<void> checkForUpdatesSilently() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestTag = data['tag_name'];
        if (latestTag.startsWith('v')) {
          latestTag = latestTag.substring(1);
        }

        if (latestTag != currentVersion && _isNewer(currentVersion, latestTag)) {
          // Trigger local notification
          await NotificationService.showInstantNotification(
            "Nueva Actualización",
            "La versión v$latestTag está disponible. Ve a configuración para instalarla."
          );
        }
      }
    } catch (e) {
      // Do nothing on silent fail
    }
  }

  static bool _isNewer(String current, String latest) {
    List<int> currParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    int maxLength = currParts.length > latestParts.length ? currParts.length : latestParts.length;
    
    for (int i = 0; i < maxLength; i++) {
      int c = i < currParts.length ? currParts[i] : 0;
      int l = i < latestParts.length ? latestParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static void _showNoUpdateDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Actualizaciones"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      )
    );
  }

  static void _showUpdateDialog(BuildContext context, String newVersion, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(version: newVersion, url: downloadUrl),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String version;
  final String url;

  const _UpdateDialog({required this.version, required this.url});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  String _status = 'Hay una nueva versión disponible. ¿Deseas actualizar?';

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _status = 'Descargando actualización...';
    });

    try {
      final request = http.Request('GET', Uri.parse(widget.url));
      final response = await http.Client().send(request);
      final contentLength = response.contentLength ?? 0;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/update_v${widget.version}.apk');

      List<int> bytes = [];
      response.stream.listen(
        (List<int> newBytes) {
          bytes.addAll(newBytes);
          final downloaded = bytes.length;
          if (contentLength > 0) {
            setState(() {
              _progress = downloaded / contentLength;
            });
          }
        },
        onDone: () async {
          await file.writeAsBytes(bytes);
          setState(() {
             _status = 'Descarga completa. Abriendo instalador...';
          });
          OpenFilex.open(file.path);
          if (mounted) Navigator.pop(context);
        },
        onError: (e) {
          setState(() {
            _status = 'Error en la descarga.';
            _isDownloading = false;
          });
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Nueva Versión v${widget.version}"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_status),
          if (_isDownloading) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 10),
            Text('${(_progress * 100).toStringAsFixed(1)}%')
          ]
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Más tarde"),
          ),
        if (!_isDownloading)
          ElevatedButton(
            onPressed: _downloadAndInstall,
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
            child: const Text("Actualizar Ahora"),
          ),
      ],
    );
  }
}
