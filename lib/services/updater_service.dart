import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import 'notification_service.dart';

class ReleaseUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final int? apkSizeBytes;

  const ReleaseUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    this.apkSizeBytes,
  });
}

class _UpdateCheckResult {
  final ReleaseUpdateInfo? info;
  final String? message;

  const _UpdateCheckResult({this.info, this.message});
}

class UpdaterService {
  static const String repoOwner = 'OscarAcosta17';
  static const String repoName = 'notas';

  static bool _startupCheckDone = false;

  @visibleForTesting
  static void resetStartupCheck() {
    _startupCheckDone = false;
  }

  static String _sanitizeNotes(String? rawBody) {
    if (rawBody == null || rawBody.trim().isEmpty) {
      return 'Mejoras de rendimiento, correcciones y nuevas funciones disponibles.';
    }
    final filtered = rawBody
        .split('\n')
        .where((line) => !line.contains('Enlace de Descarga:'))
        .map((line) => line.replaceAll('**', '').trimRight())
        .join('\n')
        .trim();
    return filtered.isEmpty
        ? 'Mejoras de rendimiento, correcciones y nuevas funciones disponibles.'
        : filtered;
  }

  static Future<_UpdateCheckResult> _fetchLatestUpdateResult() async {
    final client = http.Client();
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await client.get(
        url,
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return const _UpdateCheckResult(
          message: 'Error al consultar versiones. Revisa tu conexión a internet.',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      String latestTag = (data['tag_name'] ?? '').toString().trim();
      if (latestTag.startsWith('v') || latestTag.startsWith('V')) {
        latestTag = latestTag.substring(1);
      }
      // Strip optional pre-release/build suffix when comparing X.Y.Z
      final cleanLatest = latestTag.split('+').first.split('-').first;

      if (cleanLatest != currentVersion && _isNewer(currentVersion, cleanLatest)) {
        final assets = (data['assets'] as List<dynamic>? ?? const []);
        String? downloadUrl;
        int? apkSize;
        for (final rawAsset in assets) {
          if (rawAsset is Map<String, dynamic>) {
            final name = (rawAsset['name'] ?? '').toString();
            if (name.toLowerCase().endsWith('.apk')) {
              downloadUrl = rawAsset['browser_download_url']?.toString();
              final sizeVal = rawAsset['size'];
              if (sizeVal is int) {
                apkSize = sizeVal;
              } else if (sizeVal is num) {
                apkSize = sizeVal.toInt();
              }
              break;
            }
          }
        }

        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          return _UpdateCheckResult(
            info: ReleaseUpdateInfo(
              currentVersion: currentVersion,
              latestVersion: latestTag,
              downloadUrl: downloadUrl,
              releaseNotes: _sanitizeNotes(data['body']?.toString()),
              apkSizeBytes: apkSize,
            ),
          );
        }

        return const _UpdateCheckResult(
          message: 'Nueva versión detectada, pero no hay APK adjunto en GitHub.',
        );
      }

      return _UpdateCheckResult(
        message: 'Ya tienes la última versión instalada ($currentVersion).',
      );
    } catch (e) {
      return _UpdateCheckResult(
        message: 'Error buscando actualizaciones: $e',
      );
    } finally {
      client.close();
    }
  }

  static Future<void> checkForUpdatesOnStartup(BuildContext context) async {
    if (_startupCheckDone) return;
    _startupCheckDone = true;

    try {
      final result = await _fetchLatestUpdateResult();
      final info = result.info;
      if (info == null) return;

      try {
        await NotificationService.showInstantNotification(
          'Nueva Actualización',
          'La versión v${info.latestVersion} está disponible para instalar.',
        );
      } catch (_) {
        // Ignore notification errors in headless/test or restricted environments
      }

      if (context.mounted) {
        await _openUpdateScreen(context, info);
      }
    } catch (_) {
      // Startup update check must never crash app startup
    }
  }

  static Future<void> checkForUpdates(BuildContext context) async {
    final result = await _fetchLatestUpdateResult();
    if (!context.mounted) return;

    if (result.info != null) {
      await _openUpdateScreen(context, result.info!);
    } else {
      _showNoUpdateDialog(
        context,
        result.message ?? 'Error al consultar versiones. Revisa tu conexión a internet.',
      );
    }
  }

  static Future<void> checkForUpdatesSilently() async {
    try {
      final result = await _fetchLatestUpdateResult();
      final info = result.info;
      if (info != null) {
        await NotificationService.showInstantNotification(
          'Nueva Actualización',
          'La versión v${info.latestVersion} está disponible. Ve a configuración para instalarla.',
        );
      }
    } catch (_) {
      // Do nothing on silent fail
    }
  }

  static Future<void> _openUpdateScreen(BuildContext context, ReleaseUpdateInfo info) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => UpdateScreen(info: info),
      ),
    );
  }

  static bool _isNewer(String current, String latest) {
    final currParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLength = currParts.length > latestParts.length ? currParts.length : latestParts.length;

    for (int i = 0; i < maxLength; i++) {
      final c = i < currParts.length ? currParts[i] : 0;
      final l = i < latestParts.length ? latestParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static void _showNoUpdateDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizaciones'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class UpdateScreen extends StatefulWidget {
  final ReleaseUpdateInfo info;

  const UpdateScreen({super.key, required this.info});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  bool _isDownloading = false;
  bool _isPaused = false;
  bool _isCompleted = false;
  bool _hasError = false;

  int _downloadedBytes = 0;
  int _totalBytes = 0;
  double _progress = 0.0;
  String _status = 'Hay una nueva versión disponible lista para descargar.';

  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  IOSink? _sink;
  int _sessionId = 0;

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.info.apkSizeBytes ?? 0;
    _inspectExistingFiles();
  }

  @override
  void dispose() {
    _sessionId++;
    _subscription?.cancel();
    _subscription = null;
    _closeSinkSyncSafe();
    _client?.close();
    _client = null;
    super.dispose();
  }

  void _closeSinkSyncSafe() {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      unawaited(
        sink.flush().catchError((_) {}).whenComplete(() => sink.close().catchError((_) {})),
      );
    }
  }

  Future<(File partFile, File finalFile)> _resolveApkFiles() async {
    final dir = await getTemporaryDirectory();
    final safeVersion = widget.info.latestVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return (
      File('${dir.path}/update_v$safeVersion.apk.part'),
      File('${dir.path}/update_v$safeVersion.apk'),
    );
  }

  Future<void> _inspectExistingFiles() async {
    try {
      final (partFile, finalFile) = await _resolveApkFiles();
      if (!mounted) return;

      if (await finalFile.exists()) {
        final len = await finalFile.length();
        final expectedSize = widget.info.apkSizeBytes;
        if (len > 0 && (expectedSize == null || len == expectedSize)) {
          if (!mounted) return;
          setState(() {
            _isCompleted = true;
            _downloadedBytes = len;
            _totalBytes = expectedSize ?? len;
            _progress = 1.0;
            _status = 'Actualización descargada y lista para instalar.';
          });
          return;
        }
        await finalFile.delete();
      }

      if (await partFile.exists()) {
        final partLen = await partFile.length();
        if (partLen > 0 && mounted) {
          final total = widget.info.apkSizeBytes ?? 0;
          setState(() {
            _isPaused = true;
            _downloadedBytes = partLen;
            _totalBytes = total;
            _progress = total > 0 ? (partLen / total).clamp(0.0, 1.0) : 0.0;
            _status = 'Descarga en pausa (${_formatBytes(partLen)} descargados).';
          });
        }
      }
    } catch (_) {
      // Headless VM widget tests or uninitialized path_provider fall back cleanly to idle
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _startOrResumeDownload() async {
    if (_isDownloading) return;

    AppHaptics.light(context);
    final currentSession = ++_sessionId;

    setState(() {
      _isDownloading = true;
      _isPaused = false;
      _hasError = false;
      _status = _downloadedBytes > 0 ? 'Reanudando descarga...' : 'Conectando con GitHub...';
    });

    try {
      final (partFile, finalFile) = await _resolveApkFiles();
      if (!mounted || currentSession != _sessionId) return;

      int existingBytes = 0;
      if (await partFile.exists()) {
        existingBytes = await partFile.length();
      }

      if (widget.info.apkSizeBytes != null &&
          existingBytes > 0 &&
          existingBytes == widget.info.apkSizeBytes) {
        if (await finalFile.exists()) await finalFile.delete();
        await partFile.rename(finalFile.path);
        if (!mounted || currentSession != _sessionId) return;
        setState(() {
          _isDownloading = false;
          _isPaused = false;
          _isCompleted = true;
          _downloadedBytes = existingBytes;
          _totalBytes = existingBytes;
          _progress = 1.0;
          _status = 'Descarga completada. Abriendo instalador...';
        });
        await _installApk();
        return;
      }

      final client = http.Client();
      _client = client;

      final request = http.Request('GET', Uri.parse(widget.info.downloadUrl));
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await client.send(request);
      if (!mounted || currentSession != _sessionId) {
        client.close();
        return;
      }

      if (response.statusCode == 416) {
        if (await partFile.exists()) await partFile.delete();
        client.close();
        _client = null;
        setState(() {
          _downloadedBytes = 0;
          _progress = 0.0;
          _isDownloading = false;
        });
        await _startOrResumeDownload();
        return;
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final isResumed = response.statusCode == 206 && existingBytes > 0;
      final sink = partFile.openWrite(mode: isResumed ? FileMode.append : FileMode.write);
      _sink = sink;

      final contentLen = response.contentLength ?? 0;
      int startBytes = isResumed ? existingBytes : 0;
      int totalBytes = isResumed
          ? (contentLen > 0 ? existingBytes + contentLen : (widget.info.apkSizeBytes ?? 0))
          : (contentLen > 0 ? contentLen : (widget.info.apkSizeBytes ?? 0));

      setState(() {
        _downloadedBytes = startBytes;
        _totalBytes = totalBytes;
        _progress = totalBytes > 0 ? (startBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        _status = isResumed ? 'Descarga reanudada...' : 'Descargando actualización...';
      });

      _subscription = response.stream.listen(
        (List<int> chunk) {
          if (currentSession != _sessionId) return;
          sink.add(chunk);
          _downloadedBytes += chunk.length;
          if (mounted) {
            setState(() {
              if (_totalBytes > 0) {
                _progress = (_downloadedBytes / _totalBytes).clamp(0.0, 1.0);
              }
              _status = 'Descargando actualización...';
            });
          }
        },
        onDone: () async {
          if (currentSession != _sessionId || _isPaused) return;
          try {
            await sink.flush();
            await sink.close();
            if (_sink == sink) _sink = null;
            if (_client == client) {
              client.close();
              _client = null;
            }
            if (await finalFile.exists()) await finalFile.delete();
            await partFile.rename(finalFile.path);
            if (!mounted || currentSession != _sessionId) return;
            setState(() {
              _isDownloading = false;
              _isPaused = false;
              _isCompleted = true;
              _progress = 1.0;
              _status = 'Descarga completada. Abriendo instalador...';
            });
            await _installApk();
          } catch (e) {
            if (!mounted || currentSession != _sessionId) return;
            setState(() {
              _isDownloading = false;
              _hasError = true;
              _status = 'Error preparando el archivo de instalación: $e';
            });
          }
        },
        onError: (Object error) async {
          if (currentSession != _sessionId || _isPaused) return;
          await sink.flush().catchError((_) {});
          await sink.close().catchError((_) {});
          if (_sink == sink) _sink = null;
          if (_client == client) {
            client.close();
            _client = null;
          }
          if (!mounted) return;
          setState(() {
            _isDownloading = false;
            _hasError = true;
            _isPaused = _downloadedBytes > 0;
            _status = _downloadedBytes > 0
                ? 'Conexión interrumpida (${_formatBytes(_downloadedBytes)} guardados). Pulsa Reanudar.'
                : 'Error en la descarga. Revisa tu conexión e intenta de nuevo.';
          });
        },
        cancelOnError: true,
      );
    } catch (e) {
      _client?.close();
      _client = null;
      if (!mounted || currentSession != _sessionId) return;
      setState(() {
        _isDownloading = false;
        _hasError = true;
        _isPaused = _downloadedBytes > 0;
        _status = _downloadedBytes > 0
            ? 'No se pudo continuar (${_formatBytes(_downloadedBytes)} guardados). Intenta Reanudar.'
            : 'Error iniciando la descarga: $e';
      });
    }
  }

  Future<void> _pauseDownload() async {
    AppHaptics.selection(context);
    _sessionId++;
    final sub = _subscription;
    _subscription = null;
    final sink = _sink;
    _sink = null;
    final client = _client;
    _client = null;

    setState(() {
      _isDownloading = false;
      _isPaused = _downloadedBytes > 0;
      _status = _downloadedBytes > 0
          ? 'Descarga pausada (${_formatBytes(_downloadedBytes)} guardados).'
          : 'Descarga detenida.';
    });

    await sub?.cancel();
    if (sink != null) {
      await sink.flush().catchError((_) {});
      await sink.close().catchError((_) {});
    }
    client?.close();
  }

  Future<void> _cancelDownload() async {
    AppHaptics.selection(context);
    await _pauseDownload();
    try {
      final (partFile, finalFile) = await _resolveApkFiles();
      if (await partFile.exists()) await partFile.delete();
      if (await finalFile.exists()) await finalFile.delete();
    } catch (_) {
      // Ignore cleanup errors
    }
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _isPaused = false;
      _isCompleted = false;
      _hasError = false;
      _downloadedBytes = 0;
      _progress = 0.0;
      _status = 'Descarga cancelada.';
    });
  }

  Future<void> _installApk() async {
    AppHaptics.light(context);
    try {
      final (_, finalFile) = await _resolveApkFiles();
      if (!await finalFile.exists()) {
        if (!mounted) return;
        setState(() {
          _isCompleted = false;
          _downloadedBytes = 0;
          _progress = 0.0;
          _hasError = true;
          _status = 'El archivo APK no se encuentra en caché. Descárgalo nuevamente.';
        });
        return;
      }

      if (Platform.isAndroid) {
        var permStatus = await Permission.requestInstallPackages.status;
        if (!permStatus.isGranted) {
          permStatus = await Permission.requestInstallPackages.request();
        }
        if (!mounted) return;
        if (!permStatus.isGranted) {
          setState(() {
            _hasError = true;
            _status =
                'Permiso requerido: habilita "Instalar apps desconocidas" para NotasApp y vuelve a pulsar Instalar Ahora.';
          });
          return;
        }
      }

      final result = await OpenFilex.open(
        finalFile.path,
        type: 'application/vnd.android.package-archive',
      );
      if (!mounted) return;

      if (result.type != ResultType.done) {
        setState(() {
          _hasError = true;
          _status = 'No se pudo abrir el instalador (${result.message}). Pulsa Instalar Ahora para reintentar.';
        });
      } else {
        setState(() {
          _hasError = false;
          _status = 'Instalador abierto. Si cancelaste la ventana de Android, puedes pulsar Instalar Ahora de nuevo.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _status = 'Error al lanzar el instalador: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final percentText = '${(_progress * 100).clamp(0, 100).toStringAsFixed(1)}%';
    final sizeLabel = widget.info.apkSizeBytes != null ? _formatBytes(widget.info.apkSizeBytes!) : null;
    final progressCounter = _totalBytes > 0
        ? '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}'
        : _formatBytes(_downloadedBytes);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: const FrostedAppBar(
        title: Text('Actualización Disponible'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 28 + bottomInset),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              border: Border.all(color: tokens.accentColor.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: [
                TonalIconBadge(
                  icon: Icons.system_update_rounded,
                  color: tokens.accentColor,
                  size: 64,
                ),
                const SizedBox(height: 14),
                Text(
                  'Nueva versión v${widget.info.latestVersion}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: tokens.accentContainer,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        'v${widget.info.currentVersion}  ➔  v${widget.info.latestVersion}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.onAccentContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (sizeLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        ),
                        child: Text(
                          sizeLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.new_releases_rounded, size: 19, color: tokens.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'Novedades de la versión',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.info.releaseNotes,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              border: Border.all(
                color: _hasError
                    ? scheme.error.withValues(alpha: 0.45)
                    : scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _hasError ? scheme.error : scheme.onSurface,
                  ),
                ),
                if (_isDownloading || _isPaused || _isCompleted) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    child: LinearProgressIndicator(
                      value: (_isDownloading && _totalBytes == 0) ? null : _progress,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: tokens.accentColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        progressCounter,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        percentText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.accentColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: _buildActionButtons(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActionButtons(BuildContext context) {
    if (_isDownloading) {
      return [
        TextButton(
          onPressed: _cancelDownload,
          child: const Text('Cancelar'),
        ),
        const Spacer(),
        FilledButton.tonalIcon(
          onPressed: _pauseDownload,
          icon: const Icon(Icons.pause_rounded),
          label: const Text('Pausar'),
        ),
      ];
    }

    if (_isCompleted) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _installApk,
          icon: const Icon(Icons.install_mobile_rounded),
          label: const Text('Instalar Ahora'),
        ),
      ];
    }

    if (_isPaused) {
      return [
        TextButton(
          onPressed: _cancelDownload,
          child: const Text('Cancelar'),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _startOrResumeDownload,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Reanudar'),
        ),
      ];
    }

    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Más tarde'),
      ),
      const Spacer(),
      FilledButton.icon(
        onPressed: _startOrResumeDownload,
        icon: const Icon(Icons.download_rounded),
        label: const Text('Actualizar Ahora'),
      ),
    ];
  }
}
