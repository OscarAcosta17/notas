import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_cache_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../theme/expressive_widgets.dart';
import '../../viewmodels/categoria_provider.dart';
import '../../viewmodels/ramo_provider.dart';
import '../../viewmodels/semestre_provider.dart';
import '../../viewmodels/settings_provider.dart';

class DataSettingsView extends ConsumerStatefulWidget {
  final bool openDriveRenewalOnStart;

  const DataSettingsView({
    super.key,
    this.openDriveRenewalOnStart = false,
  });

  @override
  ConsumerState<DataSettingsView> createState() => _DataSettingsViewState();
}

class _DataSettingsViewState extends ConsumerState<DataSettingsView> {
  String _cacheSizeStr = 'Calculando...';
  CloudSyncConfig _syncConfig = const CloudSyncConfig();
  bool _isSyncBusy = false;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
    _loadSyncConfig();
    if (widget.openDriveRenewalOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openGoogleDriveSetupDialog(
            isRenewal: true,
            expiredMessage:
                CloudSyncService.driveStatusNotifier.value.message,
          );
        }
      });
    }
  }

  Future<void> _loadSyncConfig() async {
    try {
      final cfg = await CloudSyncService.getConfig();
      await CloudSyncService.refreshStatusNotifier();
      if (mounted) {
        setState(() => _syncConfig = cfg);
      }
    } catch (_) {
      // Ignore in mocked/headless tests
    }
  }

  Future<void> _refreshAppStateAfterRestore() async {
    await ref.read(settingsProvider.notifier).reloadSettings();
    ref.invalidate(semestreProvider);
    ref.invalidate(ramoProvider);
    ref.invalidate(categoriaProvider);
    await _loadSyncConfig();
  }

  String _formatLastSync(String? iso) {
    if (iso == null || iso.isEmpty) return 'Aún no sincronizado';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return 'Sincronizado';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return 'Última sinc: $d/$m $hh:$mm';
  }

  Future<void> _calculateCacheSize() async {
    try {
      final totalSize = await AppCacheService.calculateCacheSizeBytes();

      if (mounted) {
        setState(() {
          if (totalSize < 1024) {
            _cacheSizeStr = '$totalSize B';
          } else if (totalSize < 1024 * 1024) {
            _cacheSizeStr = '${(totalSize / 1024).toStringAsFixed(1)} KB';
          } else {
            _cacheSizeStr = '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cacheSizeStr = 'Desconocido');
      }
    }
  }

  Future<void> _clearCache() async {
    try {
      await AppCacheService.clearAppCache();
      await _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caché limpiada correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al limpiar caché: $e')),
        );
      }
    }
  }

  Future<void> _pickSyncFolder() async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Selecciona carpeta sincronizada (Drive / OneDrive / Local)',
      );
      if (selected == null || selected.trim().isEmpty) return;
      if (selected.trim() == '/') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Android restringió esa ruta raíz. Elige una carpeta dentro de Documentos/Descargas o usa el paquete JSON con Drive.'),
            ),
          );
        }
        return;
      }
      await CloudSyncService.setFolderPath(selected);
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Carpeta vinculada: $selected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar carpeta: $e')),
        );
      }
    }
  }

  Future<void> _syncToFolderNow() async {
    if (_isSyncBusy) return;
    setState(() => _isSyncBusy = true);
    try {
      final file = await CloudSyncService.syncToFolder();
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Guardado en carpeta: ${p.basename(file.path)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar en carpeta: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _restoreFromFolderNow() async {
    if (_isSyncBusy) return;
    setState(() => _isSyncBusy = true);
    try {
      await CloudSyncService.restoreFromFolder();
      await _refreshAppStateAfterRestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos y apariencia restaurados desde carpeta sincronizada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar desde carpeta: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _openGoogleDriveSetupDialog({
    bool isRenewal = false,
    String? expiredMessage,
  }) async {
    final tokenController = TextEditingController(
      text: isRenewal ? '' : (_syncConfig.googleDriveRefreshToken ?? ''),
    );
    final clientIdController = TextEditingController(
      text: _syncConfig.googleDriveClientId ?? '',
    );
    final clientSecretController = TextEditingController(
      text: _syncConfig.googleDriveClientSecret ?? '',
    );
    final tokenUrlController = TextEditingController(
      text: _syncConfig.googleDriveTokenUrl ?? '',
    );

    bool isVerifying = false;
    String? errorMsg;
    final showExpiredBanner =
        isRenewal || CloudSyncService.driveStatusNotifier.value.isExpired;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final scheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: Text(
              showExpiredBanner
                  ? 'Renovar token de Google Drive'
                  : 'Conectar Google Drive',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showExpiredBanner) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: scheme.onErrorContainer,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              expiredMessage ??
                                  'Tu Refresh Token de Google Drive expiró o fue revocado. Inicia sesión nuevamente en ogd y pega el nuevo token.',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'Sincroniza igual que el plugin de comunidad Obsidian Google Drive, sin configurar Google Cloud:',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: isVerifying
                          ? null
                          : () async {
                              final uri = Uri.parse(CloudSyncService.ogdAuthPortalUrl);
                              final launched = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!launched && dialogContext.mounted) {
                                await Clipboard.setData(
                                  const ClipboardData(
                                    text: CloudSyncService.ogdAuthPortalUrl,
                                  ),
                                );
                                setDialogState(() {
                                  errorMsg =
                                      'No se pudo abrir el navegador. Enlace copiado: ${CloudSyncService.ogdAuthPortalUrl}';
                                });
                              }
                            },
                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: const Text('1. Iniciar sesión en Google (ogd)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '2. Presiona "Sign In" arriba a la derecha en esa web, autoriza Google Drive y copia el Refresh Token que aparece.\n'
                    '3. Pégalo aquí abajo:',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tokenController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Google Drive Refresh Token',
                      hintText: '1//0...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Pegar',
                        icon: const Icon(Icons.content_paste_rounded),
                        onPressed: () async {
                          final clip = await Clipboard.getData('text/plain');
                          final pasted = clip?.text?.trim() ?? '';
                          if (pasted.isNotEmpty) {
                            tokenController.text = pasted;
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Opciones avanzadas (OAuth propio / servidor propio)',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    children: [
                      const SizedBox(height: 6),
                      TextField(
                        controller: tokenUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Token Server URL (opcional)',
                          hintText: CloudSyncService.ogdDefaultTokenServerUrl,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: clientIdController,
                        decoration: const InputDecoration(
                          labelText: 'Client ID personalizado (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: clientSecretController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Client Secret personalizado (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMsg!,
                      style: TextStyle(color: scheme.error, fontSize: 12.5),
                    ),
                  ],
                  if (isVerifying) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                ],
              ),
            ),
            actions: [
              if (_syncConfig.hasGoogleDriveAuth)
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          await CloudSyncService.setGoogleDriveCredentials(
                            refreshToken: null,
                            clientId: '',
                            clientSecret: '',
                            tokenUrl: '',
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, false);
                          }
                        },
                  child: const Text('Desconectar'),
                ),
              TextButton(
                onPressed: isVerifying
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isVerifying
                    ? null
                    : () async {
                        final rawToken = tokenController.text.trim();
                        if (rawToken.isEmpty) {
                          setDialogState(() {
                            errorMsg = 'Pega tu Refresh Token antes de guardar.';
                          });
                          return;
                        }
                        setDialogState(() {
                          isVerifying = true;
                          errorMsg = null;
                        });
                        try {
                          await CloudSyncService.setGoogleDriveCredentials(
                            refreshToken: rawToken,
                            clientId: clientIdController.text.trim(),
                            clientSecret: clientSecretController.text.trim(),
                            tokenUrl: tokenUrlController.text.trim(),
                          );
                          await CloudSyncService.refreshGoogleDriveAccessToken();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          setDialogState(() {
                            isVerifying = false;
                            errorMsg = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: const Text('Conectar y Guardar'),
              ),
            ],
          );
        },
      ),
    );

    tokenController.dispose();
    clientIdController.dispose();
    clientSecretController.dispose();
    tokenUrlController.dispose();

    await _loadSyncConfig();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Drive conectado correctamente (carpeta NotasApp).'),
        ),
      );
    }
  }

  Future<void> _pushGoogleDriveNow() async {
    if (_isSyncBusy) return;
    if (!_syncConfig.hasGoogleDriveAuth) {
      await _openGoogleDriveSetupDialog();
      return;
    }
    setState(() => _isSyncBusy = true);
    try {
      await CloudSyncService.uploadToGoogleDrive();
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Datos y ajustes subidos a tu carpeta NotasApp en Google Drive.'),
          ),
        );
      }
    } on GoogleDriveTokenExpiredException catch (e) {
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            action: SnackBarAction(
              label: 'Renovar',
              onPressed: () => _openGoogleDriveSetupDialog(
                isRenewal: true,
                expiredMessage: e.message,
              ),
            ),
          ),
        );
        await _openGoogleDriveSetupDialog(
          isRenewal: true,
          expiredMessage: e.message,
        );
      }
    } catch (e) {
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir a Google Drive: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _pullGoogleDriveNow() async {
    if (_isSyncBusy) return;
    if (!_syncConfig.hasGoogleDriveAuth) {
      await _openGoogleDriveSetupDialog();
      return;
    }
    setState(() => _isSyncBusy = true);
    try {
      await CloudSyncService.downloadFromGoogleDrive();
      await _refreshAppStateAfterRestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notas y apariencia descargadas desde Google Drive.'),
          ),
        );
      }
    } on GoogleDriveTokenExpiredException catch (e) {
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            action: SnackBarAction(
              label: 'Renovar',
              onPressed: () => _openGoogleDriveSetupDialog(
                isRenewal: true,
                expiredMessage: e.message,
              ),
            ),
          ),
        );
        await _openGoogleDriveSetupDialog(
          isRenewal: true,
          expiredMessage: e.message,
        );
      }
    } catch (e) {
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al descargar de Google Drive: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _openGithubSyncSetupDialog() async {
    final tokenController = TextEditingController(text: _syncConfig.githubToken ?? '');
    final gistIdController = TextEditingController(text: _syncConfig.gistId ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizar con GitHub Gist'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guarda tus notas y configuración en un Gist secreto privado de tu cuenta de GitHub (estilo Obsidian Git, sin OAuth de Google).',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Text(
                '1. En GitHub ➔ Settings ➔ Developer settings ➔ Tokens (classic), genera un token solo con el permiso "gist".\n'
                '2. Pégalo aquí abajo. La app detectará o creará tu Gist privado automáticamente.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: tokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Token Personal de GitHub (scope: gist)',
                  hintText: 'ghp_... o github_pat_...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gistIdController,
                decoration: const InputDecoration(
                  labelText: 'ID del Gist (opcional, se auto-detecta)',
                  hintText: 'Déjalo vacío para buscar o crear uno',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_syncConfig.hasGistAuth)
            TextButton(
              onPressed: () async {
                await CloudSyncService.setGithubCredentials(token: null, gistId: '');
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('Desconectar'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await CloudSyncService.setGithubCredentials(
                token: tokenController.text.trim(),
                gistId: gistIdController.text.trim(),
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    tokenController.dispose();
    gistIdController.dispose();

    await _loadSyncConfig();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credenciales de GitHub Gist guardadas.')),
      );
    }
  }

  Future<void> _pushGistNow() async {
    if (_isSyncBusy) return;
    if (!_syncConfig.hasGistAuth) {
      await _openGithubSyncSetupDialog();
      return;
    }
    setState(() => _isSyncBusy = true);
    try {
      final id = await CloudSyncService.uploadToGist();
      await _loadSyncConfig();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subido a GitHub Gist privado (${id.substring(0, id.length > 8 ? 8 : id.length)}...).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir a la nube: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _pullGistNow() async {
    if (_isSyncBusy) return;
    if (!_syncConfig.hasGistAuth) {
      await _openGithubSyncSetupDialog();
      return;
    }
    setState(() => _isSyncBusy = true);
    try {
      await CloudSyncService.downloadFromGist();
      await _refreshAppStateAfterRestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos y ajustes sincronizados desde la nube.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al descargar de la nube: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncBusy = false);
    }
  }

  Future<void> _exportPortableBundle() async {
    try {
      final bundle = await CloudSyncService.buildSyncBundle();
      const encoder = JsonEncoder.withIndent('  ');
      final jsonStr = encoder.convert(bundle);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final target = await FilePicker.saveFile(
          dialogTitle: 'Guardar Paquete de Sincronización',
          fileName: CloudSyncService.bundleFileName,
          bytes: bytes,
        );
        if (target != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Paquete guardado en $target')),
          );
        }
        return;
      }

      final dir = await AppCacheService.getCacheDirectory();
      final tempFile = File(p.join(dir.path, CloudSyncService.bundleFileName));
      await tempFile.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'Paquete completo NotasApp (datos + ajustes)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar paquete JSON: $e')),
        );
      }
    }
  }

  Future<void> _exportBackup() async {
    try {
      final path = await DatabaseHelper.instance.exportDatabase();
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final bytes = await File(path).readAsBytes();
        final savedPath = await FilePicker.saveFile(
          dialogTitle: 'Guardar Copia SQLite (.db)',
          fileName: 'NotasDB_backup.db',
          bytes: bytes,
        );
        if (savedPath != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copia guardada en $savedPath')),
          );
        }
        return;
      }

      await Share.shareXFiles([XFile(path)], text: 'Copia de Seguridad de NotasApp');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Menú para compartir o guardar abierto.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles();
      if (result != null) {
        String? filePath = result.files.single.path;
        if (filePath != null) {
          if (filePath.toLowerCase().endsWith('.json')) {
            final raw = await File(filePath).readAsString(encoding: utf8);
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            await CloudSyncService.applySyncBundle(decoded);
          } else {
            await DatabaseHelper.instance.importDatabase(filePath);
          }
          await _refreshAppStateAfterRestore();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copia restaurada y aplicada en vivo.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final tokens = context.visualTokens;
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: const FrostedAppBar(
        title: Text('Datos y Almacenamiento'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 8, 0, 28 + bottomInset),
        children: [
          const ExpressiveSectionHeader(title: 'Sincronización Multiplataforma (Android y PC)'),
          ExpressiveGroupedSection(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: TonalIconBadge(icon: Icons.sync_rounded, color: tokens.accentColor),
                title: const Text('Sincronización automática', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_formatLastSync(_syncConfig.lastSyncIso)),
                value: _syncConfig.autoSyncEnabled,
                onChanged: (val) async {
                  await CloudSyncService.setAutoSyncEnabled(val);
                  await _loadSyncConfig();
                  if (val) {
                    CloudSyncService.scheduleAutoSync();
                  }
                },
              ),
              ValueListenableBuilder<DriveSyncStatus>(
                valueListenable: CloudSyncService.driveStatusNotifier,
                builder: (context, driveStatus, _) {
                  final (pillLabel, pillBg, pillFg, pillIcon) =
                      switch (driveStatus.state) {
                    DriveSyncState.unconfigured => (
                        'Sin configurar',
                        scheme.surfaceContainerHighest,
                        scheme.onSurfaceVariant,
                        Icons.cloud_queue_rounded,
                      ),
                    DriveSyncState.syncing => (
                        'Sincronizando...',
                        scheme.primaryContainer,
                        scheme.onPrimaryContainer,
                        Icons.cloud_sync_rounded,
                      ),
                    DriveSyncState.synced => (
                        driveStatus.lastSyncIso != null
                            ? 'Sincronizado'
                            : 'Conectado',
                        Colors.green.withValues(alpha: 0.16),
                        Colors.green.shade800,
                        Icons.cloud_done_rounded,
                      ),
                    DriveSyncState.tokenExpired => (
                        'Token expirado',
                        scheme.errorContainer,
                        scheme.onErrorContainer,
                        Icons.cloud_off_rounded,
                      ),
                    DriveSyncState.error => (
                        'Error de sync',
                        Colors.amber.withValues(alpha: 0.2),
                        Colors.amber.shade900,
                        Icons.warning_amber_rounded,
                      ),
                  };

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            TonalIconBadge(
                              icon: Icons.add_to_drive_rounded,
                              color: driveStatus.isExpired
                                  ? scheme.error
                                  : tokens.accentColor,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Google Drive (Obsidian Sync)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: pillBg,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (driveStatus.state ==
                                                DriveSyncState.syncing)
                                              SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 1.8,
                                                  color: pillFg,
                                                ),
                                              )
                                            else
                                              Icon(pillIcon,
                                                  size: 13, color: pillFg),
                                            const SizedBox(width: 4),
                                            Text(
                                              pillLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: pillFg,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        _syncConfig.hasGoogleDriveAuth
                                            ? 'Carpeta NotasApp'
                                            : 'ogd.richardxiong.com',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_rounded),
                              tooltip: 'Configurar Google Drive',
                              onPressed: () => _openGoogleDriveSetupDialog(),
                            ),
                          ],
                        ),
                        if (driveStatus.isExpired || driveStatus.isError) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: driveStatus.isExpired
                                  ? scheme.errorContainer
                                  : Colors.amber.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  driveStatus.isExpired
                                      ? Icons.vpn_key_off_rounded
                                      : Icons.error_outline_rounded,
                                  size: 18,
                                  color: driveStatus.isExpired
                                      ? scheme.onErrorContainer
                                      : Colors.amber.shade900,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    driveStatus.message ??
                                        'La sesión de Google Drive necesita renovación.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: driveStatus.isExpired
                                          ? scheme.onErrorContainer
                                          : Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: () =>
                                      _openGoogleDriveSetupDialog(
                                    isRenewal: true,
                                    expiredMessage: driveStatus.message,
                                  ),
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('Renovar Token'),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!_syncConfig.hasGoogleDriveAuth)
                              FilledButton.tonalIcon(
                                onPressed: _isSyncBusy
                                    ? null
                                    : () => _openGoogleDriveSetupDialog(),
                                icon: const Icon(Icons.login_rounded, size: 18),
                                label: const Text('Obtener Token Web'),
                              ),
                            FilledButton.tonalIcon(
                              onPressed:
                                  _isSyncBusy ? null : _pushGoogleDriveNow,
                              icon: const Icon(Icons.cloud_upload_rounded,
                                  size: 18),
                              label: const Text('Subir a Google Drive'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _isSyncBusy ? null : _pullGoogleDriveNow,
                              icon: const Icon(Icons.cloud_download_rounded,
                                  size: 18),
                              label: const Text('Descargar de Google Drive'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TonalIconBadge(icon: Icons.cloud_queue_rounded, color: tokens.accentColor),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Nube Privada (GitHub Gist)',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                              Text(
                                _syncConfig.hasGistAuth
                                    ? (_syncConfig.gistId != null && _syncConfig.gistId!.isNotEmpty
                                        ? 'Conectado (Gist ${_syncConfig.gistId!.substring(0, _syncConfig.gistId!.length > 8 ? 8 : _syncConfig.gistId!.length)}...)'
                                        : 'Token listo (creará Gist al subir)')
                                    : 'Estilo Obsidian: sin configuración de Google Cloud',
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_rounded),
                          tooltip: 'Configurar Token GitHub',
                          onPressed: _openGithubSyncSetupDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _isSyncBusy ? null : _pushGistNow,
                          icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                          label: const Text('Subir a la Nube'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSyncBusy ? null : _pullGistNow,
                          icon: const Icon(Icons.cloud_download_rounded, size: 18),
                          label: const Text('Descargar de la Nube'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TonalIconBadge(icon: Icons.folder_shared_rounded, color: tokens.accentColor),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Carpeta Sincronizada (Drive / OneDrive)',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                              Text(
                                _syncConfig.hasFolder
                                    ? _syncConfig.folderPath!
                                    : 'Vincula una carpeta de Google Drive o OneDrive en tu PC',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (_syncConfig.hasFolder)
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Desvincular carpeta',
                            onPressed: () async {
                              await CloudSyncService.setFolderPath(null);
                              await _loadSyncConfig();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isSyncBusy ? null : _pickSyncFolder,
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: Text(_syncConfig.hasFolder ? 'Cambiar Carpeta' : 'Vincular Carpeta'),
                        ),
                        if (_syncConfig.hasFolder) ...[
                          FilledButton.tonalIcon(
                            onPressed: _isSyncBusy ? null : _syncToFolderNow,
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Guardar Aquí'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isSyncBusy ? null : _restoreFromFolderNow,
                            icon: const Icon(Icons.restore_page_rounded, size: 18),
                            label: const Text('Cargar de Aquí'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (_isSyncBusy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
            ],
          ),

          const ExpressiveSectionHeader(title: 'Sistema de Notas'),
          RadioGroup<String>(
            groupValue: settings.escalaNotas,
            onChanged: (String? value) {
              if (value != null) {
                ref.read(settingsProvider.notifier).setEscalaNotas(value);
              }
            },
            child: const ExpressiveGroupedSection(
              children: [
                RadioListTile<String>(
                  title: Text('Escala 1 al 7', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Nota mínima sugerida: 4.0'),
                  value: '1 a 7',
                ),
                RadioListTile<String>(
                  title: Text('Escala 0 al 100', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Nota mínima sugerida: 55.0'),
                  value: '0 a 100',
                ),
              ],
            ),
          ),

          const ExpressiveSectionHeader(title: 'Copias de Seguridad Locales'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: TonalIconBadge(icon: Icons.data_object_rounded, color: tokens.accentColor),
                title: const Text('Exportar Paquete Completo (.json)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Ideal para subir directo a Google Drive desde el móvil o PC'),
                onTap: _exportPortableBundle,
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.upload_file_rounded),
                title: const Text('Exportar Base SQLite (.db)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Guardar archivo bruto NotasDB_backup.db'),
                onTap: _exportBackup,
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.download_rounded),
                title: const Text('Importar Datos (.json o .db)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Restaurar desde Drive o almacenamiento y aplicar al instante'),
                onTap: _importBackup,
              ),
            ],
          ),

          const ExpressiveSectionHeader(title: 'Almacenamiento'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.cleaning_services_rounded),
                title: const Text('Limpiar Caché', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Archivos temporales (imágenes, actualizadores): $_cacheSizeStr'),
                onTap: _clearCache,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
