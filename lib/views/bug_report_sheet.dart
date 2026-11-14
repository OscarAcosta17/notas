import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bug_report_service.dart';
import '../services/cloud_sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';

/// Opens the multiplatform Bug Report & GitHub Issue sheet.
Future<void> showBugReportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const BugReportSheet(),
  );
}

class BugReportSheet extends StatefulWidget {
  const BugReportSheet({super.key});

  @override
  State<BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<BugReportSheet> {
  String _category = 'bug';
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _stepsController = TextEditingController();
  bool _includeLogs = true;
  List<CapturedErrorLog> _logs = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final logs = await BugReportService.getErrorLogs();
    if (mounted) {
      setState(() => _logs = logs);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  bool _validateInputs() {
    if (_titleController.text.trim().isEmpty || _descController.text.trim().isEmpty) {
      _showMessage('Completa un título breve y una descripción antes de enviar.');
      return false;
    }
    return true;
  }

  Future<String> _buildReport({bool allowEmptyFallback = false}) {
    final titleText = _titleController.text.trim();
    final descText = _descController.text.trim();
    return BugReportService.buildDiagnosticReport(
      title: allowEmptyFallback && titleText.isEmpty ? 'Diagnóstico técnico' : titleText,
      description: allowEmptyFallback && descText.isEmpty
          ? 'Diagnóstico generado desde NotasApp.'
          : descText,
      stepsToReproduce: _stepsController.text,
      category: _category,
      includeLogs: _includeLogs,
    );
  }

  Future<void> _submitInBrowser() async {
    if (!_validateInputs() || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final report = await _buildReport();
      final opened = await BugReportService.openGitHubIssueInBrowser(
        title: _titleController.text,
        markdownBody: report,
        category: _category,
      );
      if (opened) {
        if (mounted) Navigator.pop(context);
      } else {
        await Clipboard.setData(ClipboardData(text: report));
        _showMessage('No se pudo abrir el navegador. Reporte copiado al portapapeles.');
      }
    } catch (e) {
      _showMessage('Error al preparar el ticket: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<String?> _promptGitHubToken(String? existingToken) async {
    final controller = TextEditingController(text: existingToken ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Token Personal de GitHub'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa un Personal Access Token (con permiso public_repo/issues) para crear el ticket directamente desde la app:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'GitHub Token',
                hintText: 'ghp_... o github_pat_...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Enviar Ticket'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _submitDirectWithToken() async {
    if (!_validateInputs() || _isSubmitting) return;

    String? savedToken;
    try {
      final cfg = await CloudSyncService.getConfig();
      savedToken = cfg.githubToken;
    } catch (_) {
      savedToken = null;
    }

    if (!mounted) return;
    final token = (savedToken != null && savedToken.trim().isNotEmpty)
        ? savedToken
        : await _promptGitHubToken(savedToken);

    if (token == null || token.trim().isEmpty || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final report = await _buildReport();
      final issue = await BugReportService.createGitHubIssueDirect(
        token: token,
        title: _titleController.text,
        markdownBody: report,
        category: _category,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Ticket #${issue.number} creado'),
          content: SelectableText(
            'Tu reporte se registró en GitHub correctamente.\n\nEnlace:\n${issue.htmlUrl}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showMessage('No se pudo enviar vía API (prueba abrir en navegador): $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _copyDiagnostic() async {
    final report = await _buildReport(allowEmptyFallback: true);
    await Clipboard.setData(ClipboardData(text: report));
    _showMessage('Diagnóstico Markdown copiado al portapapeles.');
  }

  void _showCapturedLogsDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Errores Capturados (${_logs.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _logs.map((log) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      '[${log.source}] ${log.timestampIso}\n${log.error}\n${log.stackTrace}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await BugReportService.clearErrorLogs();
              await _loadLogs();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Limpiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FrostedGlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusExtraLarge),
        ),
        baseColor: scheme.surfaceContainerHigh,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPadding),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const TonalIconBadge(icon: Icons.bug_report_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reportar Fallo o Sugerencia',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          'Levanta un ticket en GitHub (Android y Windows)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Fallo / Bug'),
                    selected: _category == 'bug',
                    onSelected: (_) => setState(() => _category = 'bug'),
                  ),
                  ChoiceChip(
                    label: const Text('Sugerencia'),
                    selected: _category == 'enhancement',
                    onSelected: (_) => setState(() => _category = 'enhancement'),
                  ),
                  ChoiceChip(
                    label: const Text('Visual / UI'),
                    selected: _category == 'ui',
                    onSelected: (_) => setState(() => _category = 'ui'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Título del ticket',
                  hintText: 'Ej: Error al importar horario en Windows',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '¿Qué ocurrió o qué te gustaría mejorar?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stepsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Pasos para reproducir (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Adjuntar diagnóstico y logs técnicos',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _logs.isEmpty
                      ? 'SO, versión, ajustes (0 errores recientes)'
                      : 'SO, versión, ajustes y ${_logs.length} error(es) capturado(s)',
                ),
                value: _includeLogs,
                onChanged: (value) => setState(() => _includeLogs = value),
              ),
              if (_logs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _showCapturedLogsDialog,
                        icon: const Icon(Icons.terminal_rounded, size: 18),
                        label: Text('Ver errores (${_logs.length})'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await BugReportService.clearErrorLogs();
                          await _loadLogs();
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Limpiar registro'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitInBrowser,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new_rounded),
                  label: const Text('Levantar Ticket en GitHub'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _submitDirectWithToken,
                      icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: const Text('Enviar con Token API'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _copyDiagnostic,
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: const Text('Copiar Diagnóstico'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
