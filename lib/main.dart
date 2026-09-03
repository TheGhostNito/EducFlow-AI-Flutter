import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/auth/auth_gate.dart';
import 'firebase_options.dart';
import 'services/academic_notification_scheduler.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'services/time_format_service.dart';
import 'services/translation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAppCheck.instance.activate(
    providerWeb: kDebugMode
        ? WebDebugProvider()
        : ReCaptchaEnterpriseProvider(
            '6LdGGaYtAAAAAGORi9HkV80j_msD4ew0hj6GhSfy',
          ),
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidReCaptchaProvider(
            '6LemJJktAAAAAPrGBEktKtMQTFzvD2mzBZy70wUB',
          ),
  );

  await TranslationService.instance.initialize();
  await ThemeService.instance.initialize();
  await TimeFormatService.instance.initialize();

  await NotificationService.instance.inicializar();

  // Mantiene sincronizados los recordatorios locales con
  // clases, tareas y evaluaciones de la cuenta autenticada.
  AcademicNotificationScheduler.instance.start();

  runApp(const EducFlowApp());
}

class EducFlowApp extends StatelessWidget {
  const EducFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'EducFlow AI',
          debugShowCheckedModeBanner: false,

          locale: TranslationService.instance.isSpanish
              ? const Locale('es', 'CL')
              : const Locale('en', 'US'),

          supportedLocales: const [Locale('es', 'CL'), Locale('en', 'US')],

          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          // Tema actualmente seleccionado.
          themeMode: ThemeService.instance.themeMode,

          // MODO CLARO
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F7FB),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF5B5FEF),
              brightness: Brightness.light,
            ),
          ),

          // MODO OSCURO
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,

            scaffoldBackgroundColor: const Color(0xFF0D0D10),

            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6C70FF),
              onPrimary: Colors.white,

              secondary: Color(0xFFB8BBFF),
              onSecondary: Color(0xFF11131A),

              surface: Color(0xFF191F29),
              onSurface: Color(0xFFF8FAFC),

              surfaceContainerLowest: Color(0xFF0D0D10),
              surfaceContainerLow: Color(0xFF131316),
              surfaceContainer: Color(0xFF191F29),
              surfaceContainerHigh: Color(0xFF202631),
              surfaceContainerHighest: Color(0xFF252C37),

              outline: Color(0xFF343C48),
              outlineVariant: Color(0xFF2B323E),

              error: Color(0xFFEF4444),
              onError: Colors.white,

              scrim: Colors.black,
            ),

            // =========================================================
            // DIÁLOGOS
            // =========================================================
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF191F29),
              surfaceTintColor: Colors.transparent,
              barrierColor: Colors.black.withValues(alpha: 0.78),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),

            // =========================================================
            // BOTTOM SHEETS
            // =========================================================
            bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: const Color(0xFF171C25),
              modalBackgroundColor: const Color(0xFF171C25),
              surfaceTintColor: Colors.transparent,
              modalBarrierColor: Colors.black.withValues(alpha: 0.78),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
            ),

            // =========================================================
            // MENÚS EMERGENTES
            // =========================================================
            popupMenuTheme: PopupMenuThemeData(
              color: const Color(0xFF202631),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),

            // =========================================================
            // SELECTOR DE HORA
            // =========================================================
            timePickerTheme: TimePickerThemeData(
              backgroundColor: const Color(0xFF1B1D22),

              hourMinuteColor: const Color(0xFF30313A),

              hourMinuteTextColor: const Color(0xFFF1F2F6),

              dialBackgroundColor: const Color(0xFF303137),

              dialHandColor: const Color(0xFF777BFF),

              dialTextColor: const Color(0xFFE7E9F1),

              entryModeIconColor: const Color(0xFFD3D5FF),

              dayPeriodColor: const Color(0xFF30313A),

              dayPeriodTextColor: const Color(0xFFF1F2F6),

              helpTextStyle: const TextStyle(color: Color(0xFFB8BEC9)),

              cancelButtonStyle: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC4C6FF),
              ),

              confirmButtonStyle: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC4C6FF),
              ),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),

            // =========================================================
            // INPUTS
            // =========================================================
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF202631),
              labelStyle: const TextStyle(color: Color(0xFFA9B1BF)),
              hintStyle: const TextStyle(color: Color(0xFF7F899A)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: Color(0xFF343C48)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(
                  color: Color(0xFF6C70FF),
                  width: 1.3,
                ),
              ),
            ),
          ),

          home: const AuthGate(),
        );
      },
    );
  }
}
