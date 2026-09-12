import 'package:flutter/material.dart';

class FormulaEditorDialog extends StatefulWidget {
  final String initialFormula;
  final int autoCreateCount;
  final List<String> existingVariables;

  const FormulaEditorDialog({
    super.key,
    required this.initialFormula,
    this.autoCreateCount = 0,
    this.existingVariables = const [],
  });

  @override
  State<FormulaEditorDialog> createState() => _FormulaEditorDialogState();
}

class _FormulaEditorDialogState extends State<FormulaEditorDialog> {
  late String _formula;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _formula = widget.initialFormula;
  }

  void _onKeyPress(String key) {
    setState(() {
      _formula += key;
    });
    _scrollToEnd();
  }

  void _onBackspace() {
    if (_formula.isNotEmpty) {
      setState(() {
        _formula = _formula.substring(0, _formula.length - 1);
      });
      _scrollToEnd();
    }
  }

  void _onClear() {
    setState(() {
      _formula = '';
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildKey(String label, {Color? color, VoidCallback? onPressed, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor: color != null ? Colors.white : Theme.of(context).colorScheme.onSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: EdgeInsets.zero,
          ),
          onPressed: onPressed ?? () => _onKeyPress(label),
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> variables = [];
    if (widget.existingVariables.isNotEmpty) {
      variables = widget.existingVariables;
    } else if (widget.autoCreateCount > 0) {
      variables = List.generate(widget.autoCreateCount, (i) => 'e${i + 1}');
    } else {
      variables = ['e1', 'e2', 'e3', 'e4'];
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Editor de Fórmula', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Text(
                  _formula.isEmpty ? 'Escribe aquí...' : _formula,
                  style: TextStyle(
                    fontSize: 24,
                    fontFamily: 'monospace',
                    color: _formula.isEmpty ? Colors.grey : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (variables.isNotEmpty) ...[
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: variables.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                        label: Text(variables[index], style: const TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _onKeyPress(variables[index]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            Column(
              children: [
                Row(
                  children: [
                    _buildKey('sqrt(', color: Colors.deepPurpleAccent),
                    _buildKey('^', color: Colors.deepPurpleAccent),
                    _buildKey('abs(', color: Colors.deepPurpleAccent),
                    _buildKey('C', color: Colors.redAccent, onPressed: _onClear),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('min(', color: Colors.blueAccent),
                    _buildKey('max(', color: Colors.blueAccent),
                    _buildKey(','),
                    _buildKey('⌫', onPressed: _onBackspace),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('7'),
                    _buildKey('8'),
                    _buildKey('9'),
                    _buildKey('/'),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('4'),
                    _buildKey('5'),
                    _buildKey('6'),
                    _buildKey('*'),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('1'),
                    _buildKey('2'),
                    _buildKey('3'),
                    _buildKey('-'),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('.'),
                    _buildKey('0', flex: 2),
                    _buildKey('+'),
                  ],
                ),
                Row(
                  children: [
                    _buildKey('('),
                    _buildKey(')'),
                    _buildKey('Guardar', color: Theme.of(context).colorScheme.primary, flex: 2, onPressed: () {
                      Navigator.pop(context, _formula);
                    }),
                  ],
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
