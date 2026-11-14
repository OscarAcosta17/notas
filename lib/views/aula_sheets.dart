import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/aula_service.dart';

// ============================================================================
// 1. Folder Picker Dialog (Port exacto de Aula-Scrapt)
// ============================================================================

Future<String?> showFolderPickerDialog(
  BuildContext context,
  SettingsService settings, {
  String? initialPath,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FolderPickerSheet(
      settings: settings,
      initialPath: initialPath ?? settings.downloadRoot,
    ),
  );
}

class _FolderPickerSheet extends StatefulWidget {
  final SettingsService settings;
  final String initialPath;

  const _FolderPickerSheet({
    required this.settings,
    required this.initialPath,
  });

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  String _currentPath = '';
  String _externalRoot = '';
  List<String> _subdirs = [];
  bool _loading = true;
  bool _hasPermission = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _externalRoot = await widget.settings.getExternalRootPath();
    _hasPermission = await widget.settings.hasStoragePermission();
    var start = widget.initialPath.trim();
    if (start.isEmpty || !await Directory(start).exists()) {
      start = _externalRoot;
    }
    await _loadDir(start);
  }

  Future<void> _loadDir(String path) async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final list = <String>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (!name.startsWith('.')) {
            list.add(name);
          }
        }
      }
      list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _currentPath = dir.path;
        _subdirs = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentPath = path;
        _subdirs = [];
        _loading = false;
        _errorMsg = 'No se pudo listar esta carpeta ($e)';
      });
    }
  }

  Future<void> _createNewFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva carpeta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre de la carpeta',
            hintText: 'Ej: Obsidian USM',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (clean.isEmpty) return;
    final newPath = p.join(_currentPath, clean);
    try {
      await Directory(newPath).create(recursive: true);
      await _loadDir(newPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la carpeta: $e')),
      );
    }
  }

  Future<void> _pickWithSystemFileManager() async {
    final chosen = await widget.settings.pickFolderWithSystemPicker();
    if (chosen != null && chosen.trim().isNotEmpty && mounted) {
      Navigator.of(context).pop(chosen.trim());
    }
  }

  Future<void> _pickInternalAppFolder() async {
    final appDir = await getApplicationDocumentsDirectory();
    final aulaDir = Directory(p.join(appDir.path, 'Aula-USM'));
    if (!await aulaDir.exists()) {
      await aulaDir.create(recursive: true);
    }
    if (mounted) {
      Navigator.of(context).pop(aulaDir.path);
    }
  }

  Future<void> _jumpToQuick(List<String> segments) async {
    final base = _externalRoot.isNotEmpty
        ? _externalRoot
        : await widget.settings.getExternalRootPath();
    final target = p.joinAll([base, ...segments]);
    try {
      final dir = Directory(target);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _loadDir(dir.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo acceder a $target: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parent = p.dirname(_currentPath);
    final canGoUp =
        parent.isNotEmpty && parent != _currentPath && _currentPath.length > 3;

    return Container(
      height: MediaQuery.of(context).size.height * 0.84,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, color: cs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Carpeta destino (Obsidian / Archivos)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Navega y elige dónde guardar tus ramos',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Nueva carpeta',
                  onPressed: _createNewFolder,
                  icon: const Icon(Icons.create_new_folder_rounded),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (!_hasPermission && Platform.isAndroid)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, color: cs.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Falta permiso de archivos en Android para leer carpetas externas.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await widget.settings.requestStoragePermission();
                      _hasPermission =
                          await widget.settings.hasStoragePermission();
                      await _loadDir(_currentPath);
                    },
                    child: const Text('Permitir'),
                  ),
                ],
              ),
            ),
          // Quick shortcut chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ActionChip(
                  avatar: const Icon(Icons.auto_stories_rounded, size: 16),
                  label: const Text('Obsidian'),
                  onPressed: () => _jumpToQuick(
                    Platform.isAndroid ? ['Documents', 'Obsidian'] : ['Obsidian'],
                  ),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.school_rounded, size: 16),
                  label: const Text('Documents/Aula-USM'),
                  onPressed: () => _jumpToQuick(
                    Platform.isAndroid
                        ? ['Documents', 'Aula-USM']
                        : ['Aula-USM'],
                  ),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download/Aula-USM'),
                    onPressed: () => _jumpToQuick(['Download', 'Aula-USM']),
                  ),
                ],
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.drive_folder_upload_rounded, size: 16),
                  label: Text(
                    Platform.isAndroid ? 'Archivos Android' : 'Explorador PC',
                  ),
                  onPressed: _pickWithSystemFileManager,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('Carpeta interna'),
                  onPressed: _pickInternalAppFolder,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Current path bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (canGoUp)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Subir un nivel',
                    onPressed: () => _loadDir(parent),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  )
                else
                  Icon(Icons.sd_storage_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _currentPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMsg != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_off_rounded,
                                  size: 40, color: cs.error),
                              const SizedBox(height: 10),
                              Text(_errorMsg!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton.tonalIcon(
                                onPressed: _pickWithSystemFileManager,
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('Usar selector del sistema'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _subdirs.isEmpty
                        ? Center(
                            child: Text(
                              'Sin subcarpetas aquí.\nPuedes usar esta carpeta o crear una nueva arriba.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _subdirs.length,
                            itemBuilder: (_, i) {
                              final sub = _subdirs[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.folder_rounded,
                                    color: cs.primary),
                                title: Text(
                                  sub,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18),
                                onTap: () =>
                                    _loadDir(p.join(_currentPath, sub)),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _currentPath.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_currentPath),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    'Usar "${p.basename(_currentPath).isEmpty ? _currentPath : p.basename(_currentPath)}"',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. Token & Cookie Login Dialogs
// ============================================================================

Future<bool> showTokenLoginDialog(
  BuildContext context,
  MoodleService moodle,
) async {
  final ctrl = TextEditingController();
  var loading = false;
  String? errorMsg;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.vpn_key_rounded),
              SizedBox(width: 10),
              Text('Token de WebService'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pega tu token personal de Moodle desde Aula USM → Preferencias → Claves de seguridad (Moodle mobile web service).',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () {
                  launchUrl(
                    Uri.parse('${MoodleService.baseUrl}/user/managetoken.php'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Abrir claves de seguridad en navegador'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Token (wstoken)',
                  hintText: 'Ej: 3a9e8b...',
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorMsg!,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      setState(() {
                        loading = true;
                        errorMsg = null;
                      });
                      try {
                        await moodle.loginWithToken(ctrl.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setState(() {
                          loading = false;
                          errorMsg = e.toString();
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Validar'),
            ),
          ],
        );
      },
    ),
  );
  return result == true;
}

Future<bool> showCookieLoginDialog(
  BuildContext context,
  MoodleService moodle,
) async {
  final ctrl = TextEditingController();
  var loading = false;
  String? errorMsg;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cookie_rounded),
              SizedBox(width: 10),
              Text('Cookie MoodleSession'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Útil en PC o si prefieres iniciar sesión en tu navegador. Pega la cookie completa o solo el valor de MoodleSession.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Cookie / MoodleSession',
                  hintText: 'MoodleSession=abc123...',
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorMsg!,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      setState(() {
                        loading = true;
                        errorMsg = null;
                      });
                      try {
                        await moodle.loginWithCookie(ctrl.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setState(() {
                          loading = false;
                          errorMsg = e.toString();
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Conectar'),
            ),
          ],
        );
      },
    ),
  );
  return result == true;
}

// ============================================================================
// 3. WebView Login Screen & Authenticated Web Viewer
// ============================================================================

class WebViewLoginScreen extends StatefulWidget {
  final MoodleService moodle;

  const WebViewLoginScreen({super.key, required this.moodle});

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  static const MethodChannel _cookieChannel =
      MethodChannel('com.example.notas/aula_cookies');

  WebViewController? _controller;
  bool _isChecking = false;
  bool _captured = false;
  String _statusText = 'Cargando inicio de sesión USM...';

  bool get _supportsEmbeddedWebView =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_supportsEmbeddedWebView) {
      _initWebView();
    }
  }

  void _initWebView() {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            if (!mounted || _captured) return;
            setState(() => _statusText = url);
            if (url.startsWith(MoodleService.baseUrl) &&
                !url.contains('/login/')) {
              await _attemptCapture(url);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('${MoodleService.baseUrl}/login/index.php'));
    _controller = ctrl;
  }

  Future<void> _attemptCapture(String url) async {
    if (_isChecking || _captured) return;
    setState(() => _isChecking = true);
    try {
      var capturedCookie = '';

      // 1) Native Android CookieManager channel (includes HttpOnly MoodleSession)
      if (Platform.isAndroid) {
        try {
          final nativeCookies = await _cookieChannel.invokeMethod<String>(
            'getCookies',
            {'url': MoodleService.baseUrl},
          );
          if (nativeCookies != null && nativeCookies.trim().isNotEmpty) {
            capturedCookie = nativeCookies.trim();
          }
        } catch (_) {}
      }

      // 2) Fallback JS document.cookie
      if (capturedCookie.isEmpty && _controller != null) {
        final rawJs = await _controller!.runJavaScriptReturningResult(
          'document.cookie',
        );
        final jsStr = rawJs.toString().replaceAll('"', '').trim();
        if (jsStr.isNotEmpty) capturedCookie = jsStr;
      }

      if (capturedCookie.contains('MoodleSession')) {
        await widget.moodle.loginWithCookie(capturedCookie);
        _captured = true;
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      if (mounted) {
        setState(() => _isChecking = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsEmbeddedWebView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inicio de sesión Aula USM')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.desktop_windows_rounded, size: 54),
                  const SizedBox(height: 16),
                  const Text(
                    'En Windows usa Token de WebService o Cookie MoodleSession',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Puedes abrir Aula USM en tu navegador para obtener tu token o sincronizar directamente desde tu celular Android vía Google Drive.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('${MoodleService.baseUrl}/user/managetoken.php'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Abrir Aula USM en navegador'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aula USM · Navegador', style: TextStyle(fontSize: 16)),
            Text(
              _statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (_isChecking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: () => _attemptCapture('${MoodleService.baseUrl}/my/'),
              icon: const Icon(Icons.verified_user_rounded, size: 18),
              label: const Text('Ya inicié'),
            ),
        ],
      ),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller!),
    );
  }
}

class AuthenticatedWebViewerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String cookie;

  const AuthenticatedWebViewerScreen({
    super.key,
    required this.url,
    required this.title,
    this.cookie = '',
  });

  @override
  State<AuthenticatedWebViewerScreen> createState() =>
      _AuthenticatedWebViewerScreenState();
}

class _AuthenticatedWebViewerScreenState
    extends State<AuthenticatedWebViewerScreen> {
  WebViewController? _controller;
  bool _loading = true;

  bool get _supportsEmbeddedWebView =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_supportsEmbeddedWebView) {
      _initWebView();
    } else {
      _loading = false;
    }
  }

  Future<void> _initWebView() async {
    if (widget.cookie.isNotEmpty) {
      final manager = WebViewCookieManager();
      for (final part in widget.cookie.split(';')) {
        final eq = part.indexOf('=');
        if (eq > 0) {
          final name = part.substring(0, eq).trim();
          final value = part.substring(eq + 1).trim();
          if (name.isNotEmpty) {
            await manager.setCookie(WebViewCookie(
              name: name,
              value: value,
              domain: 'aula.usm.cl',
              path: '/',
            ));
          }
        }
      }
    }

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    if (mounted) {
      setState(() => _controller = ctrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Abrir en navegador externo',
            onPressed: () => launchUrl(
              Uri.parse(widget.url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: !_supportsEmbeddedWebView
          ? Center(
              child: FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(widget.url),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Abrir actividad en tu navegador'),
              ),
            )
          : Stack(
              children: [
                if (_controller != null)
                  WebViewWidget(controller: _controller!),
                if (_loading)
                  const LinearProgressIndicator(minHeight: 3),
              ],
            ),
    );
  }
}

// ============================================================================
// 4. PC Pairing Sheet (PIN / QR code -> GET /api/pair/claim?pin=...)
// ============================================================================

Future<bool> showPairingSheet(
  BuildContext context,
  MoodleService moodle,
  SettingsService settings,
) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PairingModalSheet(moodle: moodle, settings: settings),
  );
  return res == true;
}

class _PairingModalSheet extends StatefulWidget {
  final MoodleService moodle;
  final SettingsService settings;

  const _PairingModalSheet({
    required this.moodle,
    required this.settings,
  });

  @override
  State<_PairingModalSheet> createState() => _PairingModalSheetState();
}

class _PairingModalSheetState extends State<_PairingModalSheet> {
  final _urlCtrl = TextEditingController(text: '192.168.1.50:8000');
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final scanned = await widget.settings.scanQrCode();
    if (scanned == null || scanned.trim().isEmpty) return;

    final raw = scanned.trim();
    try {
      if (raw.startsWith('{')) {
        final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
        final u = (jsonMap['url'] ?? jsonMap['server'] ?? '').toString();
        final pin = (jsonMap['pin'] ?? '').toString();
        if (u.isNotEmpty) _urlCtrl.text = u;
        if (pin.isNotEmpty) _pinCtrl.text = pin;
      } else {
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.queryParameters.containsKey('pin')) {
          final hostUrl = uri.queryParameters['url'] ??
              '${uri.scheme.startsWith('http') ? uri.scheme : 'http'}://${uri.authority}';
          _urlCtrl.text = hostUrl;
          _pinCtrl.text = uri.queryParameters['pin'] ?? '';
        }
      }
      if (_pinCtrl.text.trim().isNotEmpty) {
        await _claim();
      }
    } catch (_) {}
  }

  Future<void> _claim() async {
    if (_urlCtrl.text.trim().isEmpty || _pinCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa dirección del PC y PIN.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.moodle.loginFromPairingClaim(
        _urlCtrl.text.trim(),
        _pinCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, color: cs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Vincular desde Aula-Scrapt PC',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                if (Platform.isAndroid)
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : _scanQr,
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: const Text('QR'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Importa tu sesión activa, ramos y mapeos de Obsidian desde el computador en la misma red Wi-Fi.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Dirección IP y puerto del PC',
                hintText: '192.168.1.50:8000',
                prefixIcon: Icon(Icons.lan_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'PIN de emparejamiento',
                hintText: 'Ej: 4F9A',
                prefixIcon: Icon(Icons.pin_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: cs.error, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _claim,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(_loading ? 'Conectando...' : 'Conectar con PC'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 5. Notifications Sheet (Port exacto de Aula-Scrapt)
// ============================================================================

Future<void> showNotificationsSheet(
  BuildContext context,
  SettingsService settings,
) async {
  await settings.markAllNotificationsRead();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotificationsSheetContent(settings: settings),
  );
}

class _NotificationsSheetContent extends StatefulWidget {
  final SettingsService settings;

  const _NotificationsSheetContent({required this.settings});

  @override
  State<_NotificationsSheetContent> createState() =>
      _NotificationsSheetContentState();
}

class _NotificationsSheetContentState
    extends State<_NotificationsSheetContent> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = widget.settings.notifications;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notificaciones (${list.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (list.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await widget.settings.clearNotifications();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Limpiar'),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 46,
                          color: cs.outline,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Sin notificaciones todavía',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Aquí verás archivos nuevos, entregas próximas y descargas.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = list[i];
                      final (icon, tint) = switch (n.type) {
                        'new_file' => (Icons.fiber_new_rounded, cs.primary),
                        'deadline' => (Icons.event_available_rounded, cs.error),
                        'download_done' => (
                            Icons.download_done_rounded,
                            Colors.green
                          ),
                        _ => (Icons.info_outline_rounded, cs.secondary),
                      };
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: tint.withValues(alpha: 0.14),
                              child: Icon(icon, size: 18, color: tint),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    n.body,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
