import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../pages/dashboard/dashboard_page.dart';
import '../../pages/login/login_page.dart';
import '../../pages/notifications/notifications_page.dart';
import '../../services/notification_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final NotificationService _notificationService = NotificationService.instance;

  String? _pendingPayload;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();

    _pendingPayload = _notificationService.notificationPayload.value;

    _notificationService.notificationPayload.addListener(
      _onNotificationPayload,
    );
  }

  @override
  void dispose() {
    _notificationService.notificationPayload.removeListener(
      _onNotificationPayload,
    );

    super.dispose();
  }

  void _onNotificationPayload() {
    final String? value = _notificationService.notificationPayload.value;

    if (!mounted || value == null || value.trim().isEmpty) {
      return;
    }

    setState(() {
      _pendingPayload = value.trim();
    });
  }

  void _intentarAbrirNotificacion(User? user) {
    if (user == null || _navigationScheduled) {
      return;
    }

    final String payload = _pendingPayload?.trim() ?? '';

    if (payload.isEmpty) {
      return;
    }

    _navigationScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      // Solo los recordatorios académicos tienen un destino
      // dentro de la app. Payloads de prueba/generales se
      // consumen sin abrir una pantalla extra.
      if (!payload.startsWith('academic|')) {
        _notificationService.consumirPayload(payload);

        if (mounted) {
          setState(() {
            _pendingPayload = null;
            _navigationScheduled = false;
          });
        }

        return;
      }

      _notificationService.consumirPayload(payload);

      setState(() {
        _pendingPayload = null;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotificationsPage(initialPayload: payload),
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _navigationScheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FB),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF5B5FEF)),
            ),
          );
        }

        if (snapshot.hasData) {
          _intentarAbrirNotificacion(snapshot.data);

          return const DashboardPage();
        }

        return const LoginPage();
      },
    );
  }
}
