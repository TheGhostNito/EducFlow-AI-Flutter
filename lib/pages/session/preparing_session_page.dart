import 'package:flutter/material.dart';

class PreparingSessionPage extends StatelessWidget {
  const PreparingSessionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B5FEF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.school_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 26),
                const CircularProgressIndicator(color: Color(0xFF5B5FEF)),
                const SizedBox(height: 22),
                Text(
                  'Preparando tu espacio…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Estamos cargando tu perfil y preferencias.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SessionPreparationErrorPage extends StatefulWidget {
  const SessionPreparationErrorPage({
    super.key,
    required this.onRetry,
    required this.onSignOut,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  @override
  State<SessionPreparationErrorPage> createState() =>
      _SessionPreparationErrorPageState();
}

class _SessionPreparationErrorPageState
    extends State<SessionPreparationErrorPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 54,
                    color: Color(0xFF5B5FEF),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'No pudimos preparar tu sesión',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Revisa tu conexión e inténtalo nuevamente. No necesitas volver a escribir tus credenciales.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _run(widget.onRetry),
                      child: const Text('Reintentar'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _run(widget.onSignOut),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
