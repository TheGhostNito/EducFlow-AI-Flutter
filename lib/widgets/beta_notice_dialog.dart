import 'package:flutter/material.dart';

import '../services/beta_notice_service.dart';

Future<void> showBetaNoticeDialog(
  BuildContext context, {
  required bool spanish,
  required BetaNoticeKind kind,
}) async {
  final bool dark = Theme.of(context).brightness == Brightness.dark;

  final bool welcome = kind == BetaNoticeKind.welcome;

  final String title = welcome
      ? (spanish ? 'Bienvenido a EducFlow AI' : 'Welcome to EducFlow AI')
      : (spanish ? 'EducFlow AI está en beta' : 'EducFlow AI is in beta');

  final String description = welcome
      ? (spanish
            ? 'Estás usando la Beta 0.1 de la aplicación. Algunas funciones pueden fallar, cambiar o comportarse de forma inesperada durante las pruebas.'
            : 'You are using version 0.1 Beta of the app. Some features may fail, change, or behave unexpectedly during testing.')
      : (spanish
            ? 'Durante la Beta 0.1, las consultas de IA tienen una cuota limitada. Evita enviar muchas preguntas seguidas: si se alcanza el límite, tendrás que esperar antes de volver a consultar.'
            : 'During Beta 0.1, AI requests have a limited quota. Avoid sending many questions in a row: if the limit is reached, you will need to wait before asking again.');

  final String secondary = welcome
      ? (spanish
            ? 'Si encuentras algún problema, anótalo para que podamos corregirlo antes de una versión pública.'
            : 'If you find an issue, keep note of it so it can be fixed before a public release.')
      : (spanish
            ? 'El límite es temporal y no afecta tus datos guardados en EduFlow.'
            : 'The limit is temporary and does not affect your saved EduFlow data.');

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF18181D) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: dark ? const Color(0xFF303038) : const Color(0xFFE3E6ED),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5B5FEF)
                          .withValues(alpha: dark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      welcome
                          ? Icons.auto_awesome_rounded
                          : Icons.smart_toy_outlined,
                      color: const Color(0xFF5B5FEF),
                      size: 24,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5B5FEF)
                                .withValues(alpha: dark ? 0.18 : 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'BETA ${BetaNoticeService.betaVersion}',
                            style: const TextStyle(
                              color: Color(0xFF777BFF),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),

                        const SizedBox(height: 7),

                        Text(
                          title,
                          style: TextStyle(
                            color: dark
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF111827),
                            fontSize: 20,
                            height: 1.18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 17),

              Text(
                description,
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFD5D8E0)
                      : const Color(0xFF374151),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 11),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF222229)
                      : const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF303038)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      welcome
                          ? Icons.bug_report_outlined
                          : Icons.hourglass_top_rounded,
                      size: 18,
                      color: const Color(0xFF777BFF),
                    ),

                    const SizedBox(width: 9),

                    Expanded(
                      child: Text(
                        secondary,
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFAEB4C0)
                              : const Color(0xFF6B7280),
                          fontSize: 12.5,
                          height: 1.42,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5B5FEF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    spanish ? 'Entendido' : 'Got it',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
