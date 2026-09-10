import 'package:flutter/material.dart';

import '../../pages/login/login_page.dart';
import '../../pages/session/preparing_session_page.dart';
import '../navigation/main_navigation.dart';
import 'session_controller.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.sessionController,
    this.loginBuilder,
    this.preparingBuilder,
    this.readyBuilder,
    this.errorBuilder,
  });

  final SessionController? sessionController;
  final WidgetBuilder? loginBuilder;
  final WidgetBuilder? preparingBuilder;
  final WidgetBuilder? readyBuilder;
  final WidgetBuilder? errorBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final SessionController _sessionController =
      widget.sessionController ?? SessionController.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sessionController,
      builder: (context, _) {
        final status = _sessionController.status;
        if (status == SessionStatus.unauthenticated ||
            status == SessionStatus.preparing) {
          final login =
              widget.loginBuilder?.call(context) ??
              LoginPage(sessionController: _sessionController);
          return Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: status == SessionStatus.preparing,
                child: TickerMode(
                  enabled: status == SessionStatus.unauthenticated,
                  child: login,
                ),
              ),
              if (status == SessionStatus.preparing)
                widget.preparingBuilder?.call(context) ??
                    const PreparingSessionPage(),
            ],
          );
        }

        return switch (_sessionController.status) {
          SessionStatus.unauthenticated ||
          SessionStatus.preparing => const SizedBox.shrink(),
          SessionStatus.ready =>
            widget.readyBuilder?.call(context) ?? const MainNavigation(),
          SessionStatus.error =>
            widget.errorBuilder?.call(context) ??
                SessionPreparationErrorPage(
                  onRetry: _sessionController.retry,
                  onSignOut: _sessionController.signOut,
                ),
        };
      },
    );
  }
}
