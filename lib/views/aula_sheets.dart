import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/aula_course.dart';
import '../models/ramo.dart';
import '../services/aula_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';

/// Android-only interactive USM SSO WebView sheet that captures `MoodleSession`
/// via native CookieManager + optional `moodlemobile://token=` deep link.
class AulaWebViewLoginScreen extends StatefulWidget {
  const AulaWebViewLoginScreen({super.key});

  @override
  State<AulaWebViewLoginScreen> createState() => _AulaWebViewLoginScreenState();
}

class _AulaWebViewLoginScreenState extends State<AulaWebViewLoginScreen> {
  static const _cookieChannel = MethodChannel('com.example.notas/aula_cookies');
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _captured = false;
  String _currentUrl = AulaMoodleService.baseUrl;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _currentUrl = url;
              });
            }
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith('moodlemobile://token=')) {
              _handleMobileTokenRedirect(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
              });
            }
            await _tryCaptureSession(url);
          },
        ),
      )
      ..loadRequest(Uri.parse('${AulaMoodleService.baseUrl}/login/index.php'));
  }

  Future<void> _handleMobileTokenRedirect(String url) async {
    if (_captured) return;
    final raw = url.replaceFirst('moodlemobile://token=', '');
    try {
      final decoded = String.fromCharCodes(Uri.decodeComponent(raw).codeUnits);
      final normalized = decoded.contains(':::')
          ? decoded
          : String.fromCharCodes(Uri.decodeFull(raw).codeUnits);
      final parts = normalized.split(':::');
      if (parts.length >= 2 && parts[1].isNotEmpty) {
        _captured = true;
        if (mounted) {
          Navigator.of(context).pop(AulaSessionData(token: parts[1]));
        }
      }
    } catch (_) {}
  }

  Future<void> _tryCaptureSession(String url) async {
    if (_captured) return;
    if (!url.contains('aula.usm.cl') || url.contains('/login/')) return;

    try {
      final cookieStr = await _cookieChannel.invokeMethod<String>(
            'getCookies',
            {'url': AulaMoodleService.baseUrl},
          ) ??
          '';
      final match = RegExp(r'MoodleSession=([^;\s]+)').firstMatch(cookieStr);
      if (match == null) return;

      final moodleSession = match.group(1) ?? '';
      if (moodleSession.isEmpty) return;

      String sesskey = '';
      try {
        final rawJs = await _controller.runJavaScriptReturningResult(
          '(() => { try { return (window.M && M.cfg && M.cfg.sesskey) ? M.cfg.sesskey : ""; } catch(e) { return ""; } })()',
        );
        sesskey = rawJs.toString().replaceAll('"', '').trim();
      } catch (_) {}

      if (url.contains('/my') || url.contains('aula.usm.cl/?') || sesskey.isNotEmpty) {
        _captured = true;
        final session = AulaSessionData(
          moodleSession: moodleSession,
          sesskey: sesskey,
        );
        if (mounted) Navigator.of(context).pop(session);
      }
    } catch (_) {}
  }

  Future<void> _clearAndReload() async {
    try {
      await _cookieChannel.invokeMethod('clearCookies');
    } catch (_) {}
    await _controller.loadRequest(Uri.parse('${AulaMoodleService.baseUrl}/login/index.php'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: FrostedAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Acceso Institucional USM', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              _currentUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Capturar sesión ahora',
            onPressed: () => _tryCaptureSession('${AulaMoodleService.baseUrl}/my/'),
            icon: const Icon(Icons.check_circle_outline_rounded),
          ),
          IconButton(
            tooltip: 'Reiniciar sesión web',
            onPressed: _clearAndReload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(minHeight: 3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
            child: Text(
              'Inicia sesión con tu cuenta USM. Al llegar a tu Área personal la conexión se detectará automáticamente.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

/// Auth & PC pairing modal sheet supporting Token, MoodleSession cookie, PIN pairing, and local PC import.
class AulaAuthSheet extends StatefulWidget {
  final AulaSessionData currentSession;
  final AulaSettingsService settingsService;
  final Future<void> Function(AulaSessionData session, {Map<int, String>? extraFolders}) onAuthenticated;

  const AulaAuthSheet({
    super.key,
    required this.currentSession,
    required this.settingsService,
    required this.onAuthenticated,
  });

  @override
  State<AulaAuthSheet> createState() => _AulaAuthSheetState();
}

class _AulaAuthSheetState extends State<AulaAuthSheet> {
  late final TextEditingController _tokenController;
  late final TextEditingController _cookieController;
  late final TextEditingController _hostController;
  late final TextEditingController _pinController;

  int _mode = 0; // 0: Token/Cookie, 1: PIN Pairing
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.currentSession.token);
    _cookieController = TextEditingController(text: widget.currentSession.moodleSession);
    _hostController = TextEditingController(text: 'http://192.168.1.');
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _cookieController.dispose();
    _hostController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submitManual() async {
    final token = _tokenController.text.trim();
    final cookie = _cookieController.text.trim();
    if (token.isEmpty && cookie.isEmpty) {
      setState(() => _error = 'Ingresa un Token WebService o tu cookie MoodleSession.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final candidate = AulaSessionData(
        token: token,
        moodleSession: cookie,
      );
      final moodle = AulaMoodleService(session: candidate);
      final validated = await moodle.validateSession();
      await widget.onAuthenticated(validated);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _submitPairing() async {
    final host = _hostController.text.trim();
    final pin = _pinController.text.trim();
    if (host.isEmpty || pin.isEmpty) {
      setState(() => _error = 'Ingresa la IP:Puerto del servidor Aula-Scrapt y el PIN de 6 dígitos.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final moodle = AulaMoodleService(session: const AulaSessionData());
      final claimed = await moodle.claimPairingPin(serverUrl: host, pin: pin);
      final validated = await moodle.validateSession();
      await widget.onAuthenticated(validated, extraFolders: claimed.folders);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _importFromLocalDesktop() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final imported = await widget.settingsService.detectAndImportLocalDesktopData(
        overwriteExistingSession: true,
      );
      if (imported == null || !imported.foundSession) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'No se encontró session.json activo en tu carpeta local de Aula-Scrapt.';
          });
        }
        return;
      }
      final reloaded = await widget.settingsService.loadSession();
      final moodle = AulaMoodleService(session: reloaded);
      final validated = await moodle.validateSession();
      await widget.onAuthenticated(validated);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.visualTokens;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TonalIconBadge(icon: Icons.key_rounded, color: tokens.accentColor, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Conectar Aula USM',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        'Autenticación mediante Token, Cookie o Vinculación PC',
                        style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (Platform.isWindows) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _importFromLocalDesktop,
                  icon: const Icon(Icons.computer_rounded),
                  label: const Text('Importar sesión de Aula-Scrapt PC'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.vpn_key_rounded), label: Text('Token / Cookie')),
                ButtonSegment(value: 1, icon: Icon(Icons.phonelink_rounded), label: Text('Vincular PIN')),
              ],
              selected: {_mode},
              onSelectionChanged: (sel) => setState(() {
                _mode = sel.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_mode == 0) ...[
              TextField(
                controller: _tokenController,
                decoration: InputDecoration(
                  labelText: 'Token WebService (wstoken)',
                  hintText: 'Recomendado · encuéntralo en Aula -> Preferencias -> Claves de seguridad',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                  prefixIcon: const Icon(Icons.password_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cookieController,
                decoration: InputDecoration(
                  labelText: 'Cookie MoodleSession (opcional)',
                  hintText: 'Opcional para scraping de páginas web',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                  prefixIcon: const Icon(Icons.cookie_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('${AulaMoodleService.baseUrl}/user/managetoken.php'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Abrir Claves de Seguridad en aula.usm.cl'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: 'URL / IP de Aula-Scrapt PC',
                  hintText: 'Ej: http://192.168.1.45:5173',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                  prefixIcon: const Icon(Icons.wifi_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'PIN de vinculación (6 dígitos)',
                  hintText: 'Generado desde "Vincular Móvil" en Aula-Scrapt Web',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                  prefixIcon: const Icon(Icons.pin_rounded),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : (_mode == 0 ? _submitManual : _submitPairing),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_mode == 0 ? 'Validar y Conectar' : 'Reclamar Sesión por PIN'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Configure course folder mapping, section organization, visibility, and NotasApp Ramo link.
class AulaFolderConfigSheet extends StatefulWidget {
  final MoodleCourse course;
  final String currentFolder;
  final String currentSubfolder;
  final bool organizeBySections;
  final List<Ramo> availableRamos;
  final int? linkedRamoId;
  final Future<void> Function({
    required String folderName,
    required String subfolder,
    required bool orgBySections,
    required bool hidden,
    required int? linkedRamoId,
  }) onSave;

  const AulaFolderConfigSheet({
    super.key,
    required this.course,
    required this.currentFolder,
    required this.currentSubfolder,
    required this.organizeBySections,
    required this.availableRamos,
    required this.linkedRamoId,
    required this.onSave,
  });

  @override
  State<AulaFolderConfigSheet> createState() => _AulaFolderConfigSheetState();
}

class _AulaFolderConfigSheetState extends State<AulaFolderConfigSheet> {
  late final TextEditingController _folderCtrl;
  late final TextEditingController _subCtrl;
  late bool _orgSections;
  late bool _hidden;
  int? _linkedRamoId;

  @override
  void initState() {
    super.initState();
    _folderCtrl = TextEditingController(
      text: widget.currentFolder.isNotEmpty ? widget.currentFolder : widget.course.cleanName,
    );
    _subCtrl = TextEditingController(text: widget.currentSubfolder);
    _orgSections = widget.organizeBySections;
    _hidden = widget.course.isHidden;
    _linkedRamoId = widget.linkedRamoId;
  }

  @override
  void dispose() {
    _folderCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.visualTokens;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TonalIconBadge(icon: Icons.folder_copy_rounded, color: tokens.accentColor, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Configurar Curso',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        widget.course.cleanName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _folderCtrl,
              decoration: InputDecoration(
                labelText: 'Carpeta de descarga del curso',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: Text(widget.course.cleanName),
                  onPressed: () => setState(() => _folderCtrl.text = widget.course.cleanName),
                ),
                if (widget.course.courseCode != null)
                  ActionChip(
                    label: Text(widget.course.courseCode!),
                    onPressed: () => setState(() => _folderCtrl.text = widget.course.courseCode!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subCtrl,
              decoration: InputDecoration(
                labelText: 'Subcarpeta personalizada (opcional)',
                hintText: 'Ej: Material / 2026-2',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                prefixIcon: const Icon(Icons.create_new_folder_outlined),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.availableRamos.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: widget.availableRamos.any((r) => r.id == _linkedRamoId) ? _linkedRamoId : null,
                decoration: InputDecoration(
                  labelText: 'Ramo vinculado en NotasApp',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                  prefixIcon: const Icon(Icons.school_rounded),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Detección automática'),
                  ),
                  for (final ramo in widget.availableRamos)
                    DropdownMenuItem<int?>(
                      value: ramo.id,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: ramo.color != null ? Color(ramo.color!) : tokens.accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: Text(ramo.nombre, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _linkedRamoId = val),
              ),
              const SizedBox(height: 12),
            ],
            ExpressiveGroupedSection(
              margin: EdgeInsets.zero,
              children: [
                SwitchListTile(
                  title: const Text('Organizar en subcarpetas por sección'),
                  subtitle: const Text('Guarda cada archivo dentro de la carpeta de su semana/unidad'),
                  value: _orgSections,
                  onChanged: (v) => setState(() => _orgSections = v),
                ),
                SwitchListTile(
                  title: const Text('Ocultar curso de la lista principal'),
                  subtitle: const Text('Útil para cursos antiguos o coordinaciones'),
                  value: _hidden,
                  onChanged: (v) => setState(() => _hidden = v),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await widget.onSave(
                    folderName: _folderCtrl.text.trim(),
                    subfolder: _subCtrl.text.trim(),
                    orgBySections: _orgSections,
                    hidden: _hidden,
                    linkedRamoId: _linkedRamoId,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                },
                icon: const Icon(Icons.save_rounded),
                label: const Text('Guardar Configuración'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Global preferences sheet for Aula USM downloads, Obsidian Vault export, notifications, and logout.
class AulaGlobalSettingsSheet extends StatefulWidget {
  final AulaSettingsService settingsService;
  final String downloadRoot;
  final String? obsidianVaultPath;
  final bool notifyNewFiles;
  final bool notifyDeadlines;
  final int deadlineHours;
  final List<MoodleCourse> hiddenCourses;
  final Future<void> Function(int courseId) onUnhideCourse;
  final Future<void> Function() onLogout;
  final VoidCallback onSettingsChanged;

  const AulaGlobalSettingsSheet({
    super.key,
    required this.settingsService,
    required this.downloadRoot,
    required this.obsidianVaultPath,
    required this.notifyNewFiles,
    required this.notifyDeadlines,
    required this.deadlineHours,
    required this.hiddenCourses,
    required this.onUnhideCourse,
    required this.onLogout,
    required this.onSettingsChanged,
  });

  @override
  State<AulaGlobalSettingsSheet> createState() => _AulaGlobalSettingsSheetState();
}

class _AulaGlobalSettingsSheetState extends State<AulaGlobalSettingsSheet> {
  late String _dlRoot;
  String? _vaultPath;
  late bool _notifyNewFiles;
  late bool _notifyDeadlines;
  late int _deadlineHours;

  @override
  void initState() {
    super.initState();
    _dlRoot = widget.downloadRoot;
    _vaultPath = widget.obsidianVaultPath;
    _notifyNewFiles = widget.notifyNewFiles;
    _notifyDeadlines = widget.notifyDeadlines;
    _deadlineHours = widget.deadlineHours;
  }

  Future<void> _pickDownloadRoot() async {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta raíz de descargas de Aula USM',
      initialDirectory: _dlRoot,
    );
    if (picked != null && picked.isNotEmpty) {
      await widget.settingsService.setDownloadRoot(picked);
      setState(() => _dlRoot = picked);
      widget.onSettingsChanged();
    }
  }

  Future<void> _pickObsidianVault() async {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Seleccionar bóveda de Obsidian',
      initialDirectory: _vaultPath,
    );
    if (picked != null && picked.isNotEmpty) {
      await widget.settingsService.setObsidianVaultPath(picked);
      setState(() => _vaultPath = picked);
      widget.onSettingsChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.visualTokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TonalIconBadge(icon: Icons.tune_rounded, color: tokens.accentColor, size: 42),
                const SizedBox(width: 12),
                Text('Ajustes de Aula USM',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            ExpressiveGroupedSection(
              margin: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: TonalIconBadge(icon: Icons.folder_rounded, color: tokens.accentColor),
                  title: const Text('Carpeta de Descargas'),
                  subtitle: Text(_dlRoot, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.edit_rounded, size: 18),
                  onTap: _pickDownloadRoot,
                ),
                ListTile(
                  leading: TonalIconBadge(icon: Icons.hub_rounded, color: tokens.accentColor),
                  title: const Text('Bóveda de Obsidian (.md)'),
                  subtitle: Text(
                    _vaultPath ?? 'Usar subcarpeta dentro de Descargas',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _vaultPath != null
                      ? IconButton(
                          tooltip: 'Limpiar',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () async {
                            await widget.settingsService.setObsidianVaultPath(null);
                            setState(() => _vaultPath = null);
                            widget.onSettingsChanged();
                          },
                        )
                      : const Icon(Icons.edit_rounded, size: 18),
                  onTap: _pickObsidianVault,
                ),
              ],
            ),
            const SizedBox(height: 14),
            ExpressiveGroupedSection(
              margin: EdgeInsets.zero,
              children: [
                SwitchListTile(
                  title: const Text('Avisar archivos nuevos en Aula'),
                  value: _notifyNewFiles,
                  onChanged: (v) async {
                    setState(() => _notifyNewFiles = v);
                    await widget.settingsService.saveNotificationSettings(notifyNewFiles: v);
                    widget.onSettingsChanged();
                  },
                ),
                SwitchListTile(
                  title: const Text('Programar recordatorios al importar entregas'),
                  subtitle: Text('Con $_deadlineHours horas de anticipación'),
                  value: _notifyDeadlines,
                  onChanged: (v) async {
                    setState(() => _notifyDeadlines = v);
                    await widget.settingsService.saveNotificationSettings(notifyDeadlines: v);
                    widget.onSettingsChanged();
                  },
                ),
              ],
            ),
            if (widget.hiddenCourses.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Cursos ocultos (${widget.hiddenCourses.length})',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final c in widget.hiddenCourses)
                    InputChip(
                      label: Text(c.cleanName),
                      deleteIcon: const Icon(Icons.visibility_rounded, size: 16),
                      onDeleted: () async {
                        await widget.onUnhideCourse(c.id);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.45)),
                ),
                onPressed: () async {
                  await widget.onLogout();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión de Aula USM'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
