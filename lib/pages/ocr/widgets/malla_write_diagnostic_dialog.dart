import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/malla_multimodal_write_diagnostic_service.dart';

class MallaWriteDiagnosticDialog extends StatefulWidget {
  const MallaWriteDiagnosticDialog({
    super.key,
    required this.ownMallaId,
    required this.diagnostic,
    required this.spanish,
  });

  final String ownMallaId;
  final MallaWriteDiagnosticGateway diagnostic;
  final bool spanish;

  @override
  State<MallaWriteDiagnosticDialog> createState() =>
      _MallaWriteDiagnosticDialogState();
}

class _MallaWriteDiagnosticDialogState
    extends State<MallaWriteDiagnosticDialog> {
  final TextEditingController _foreignMallaController = TextEditingController();
  bool _running = false;
  String? _error;
  MallaWriteDiagnosticResult? _result;

  String _t(String es, String en) => widget.spanish ? es : en;

  @override
  void dispose() {
    _foreignMallaController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final value = await widget.diagnostic.run(_foreignMallaController.text);
      if (!mounted) return;
      setState(() => _result = value);
    } on MallaWriteDiagnosticException catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.safeMessage);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = _t(
          'No fue posible completar el diagnóstico de escritura.',
          'The write diagnostics could not be completed.',
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: Text(_t('Validar escritura Firebase', 'Validate Firebase write')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(
                'Repite una decisión aceptada solo si puede demostrar que la malla quedará idéntica. También comprueba UID y malla ajena sin modificarlos.',
                'Repeats an accepted decision only when it can prove the curriculum remains identical. It also checks an incorrect UID and a foreign curriculum without modifying them.',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              _t(
                'UUID propia: ${widget.ownMallaId}',
                'Own UUID: ${widget.ownMallaId}',
              ),
              key: const Key('malla-write-own-id'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.ownMallaId));
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(_t('Copiar UUID propia', 'Copy own UUID')),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('malla-write-foreign-id'),
              controller: _foreignMallaController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _t(
                  'UUID de la malla de la otra cuenta',
                  'Other account curriculum UUID',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('malla-write-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                result.safeReport(spanish: widget.spanish),
                key: const Key('malla-write-result'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: result.safeReport(spanish: widget.spanish),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(_t('Copiar resultado', 'Copy result')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('malla-close-write-diagnostic'),
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: Text(_t('Cerrar', 'Close')),
        ),
        FilledButton.icon(
          key: const Key('malla-run-write-diagnostic'),
          onPressed: _running ? null : _run,
          icon: _running
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rule_outlined),
          label: Text(_t('Comprobar', 'Check')),
        ),
      ],
    );
  }
}
