import 'dart:async';

import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/models/ai_conversation.dart';
import 'package:eduflow_ai/pages/ai/ai_chat_page.dart';
import 'package:eduflow_ai/services/ai_chat_history_service.dart';
import 'package:eduflow_ai/services/ai_function_calling_flow.dart';
import 'package:eduflow_ai/services/ai_service.dart';
import 'package:eduflow_ai/services/beta_notice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await FirebaseAuthTestHost().initialize();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'https://ubjmdfwkjgblnjgmufpc.supabase.co',
      publishableKey: 'sb_publishable_DmUj02VfZSkZOzoR11oq5A_TumX6rfA',
    );
  });

  testWidgets('limpia Pensando cuando la respuesta termina correctamente', (
    tester,
  ) async {
    final Completer<String> response = Completer<String>();
    final _FakeAiAssistant ai = _FakeAiAssistant((_) => response.future);
    final _FakeAiHistory history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, '¿Cómo voy en Big Data?');

    expect(find.text('Pensando'), findsOneWidget);

    response.complete('Vas bien en Big Data.');
    await tester.pumpAndSettle();

    expect(find.text('Pensando'), findsNothing);
    expect(find.text('Vas bien en Big Data.'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-ai-message')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('limpia Pensando y permite reintentar tras error remoto', (
    tester,
  ) async {
    int attempts = 0;
    final _FakeAiAssistant ai = _FakeAiAssistant((_) async {
      attempts += 1;
      if (attempts == 1) throw StateError('fallo remoto controlado');
      return 'Respuesta recuperada.';
    });
    final _FakeAiHistory history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    const prompt = '¿Qué nota necesito en Big Data?';
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, prompt);
    await tester.pumpAndSettle();

    expect(find.text('Pensando'), findsNothing);
    expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
    expect(find.text(prompt), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Pensando'), findsNothing);
    expect(find.text(prompt), findsOneWidget);
    expect(find.text('Respuesta recuperada.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('limpia Pensando y conserva el mensaje tras timeout', (
    tester,
  ) async {
    final _FakeAiAssistant ai = _FakeAiAssistant((_) async {
      throw const AiRequestTimeoutException(
        timeout: Duration(seconds: 45),
        stage: 'envio_prompt',
      );
    });
    final _FakeAiHistory history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    const prompt =
        '¿Qué nota necesito en el examen de Big Data para terminar con 4,0?';
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, prompt);
    await tester.pumpAndSettle();

    expect(find.text('Pensando'), findsNothing);
    expect(find.textContaining('45 segundos'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
    expect(find.text(prompt), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  SessionController sessionController,
  AiAssistantClient ai,
  AiChatHistoryRepository history,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AiChatPage(
        sessionController: sessionController,
        betaNoticeService: _NoBetaNotice(),
        initialConversationLoadOverride: () async {},
        aiService: ai,
        historyService: history,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _send(WidgetTester tester, String message) async {
  await tester.enterText(find.byType(TextField), message);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
}

({SessionController controller, StreamController<SessionUserIdentity?> auth})
_readyController() {
  const current = SessionUserIdentity(
    uid: 'ai-test-user',
    email: 'ai@example.com',
    displayName: 'AI Test',
  );
  final auth = StreamController<SessionUserIdentity?>();
  final controller = SessionController(
    currentUserProvider: () => current,
    authChanges: auth.stream,
    sessionPreparation: (_, _, _) async {},
    signOutAction: () async {},
  );
  return (controller: controller, auth: auth);
}

class _FakeAiAssistant implements AiAssistantClient {
  _FakeAiAssistant(this.send);

  final Future<String> Function(String message) send;

  @override
  Future<String> enviarMensaje(String mensaje) => send(mensaje);

  @override
  void iniciarConversacion({
    required String conversationId,
    List<AiChatMessage> history = const [],
  }) {}

  @override
  void iniciarNuevoChat() {}
}

class _FakeAiHistory implements AiChatHistoryRepository {
  final List<AiChatMessage> messages = <AiChatMessage>[];
  AiConversation? conversation;
  int nextMessageId = 0;

  @override
  Future<AiChatMessage> addMessage({
    required String chatId,
    required AiChatRole role,
    required String text,
    bool isError = false,
  }) async {
    final message = AiChatMessage(
      id: 'message-${nextMessageId++}',
      role: role,
      text: text,
      createdAt: DateTime(2026, 10, 5),
      isError: isError,
    );
    messages.add(message);
    return message;
  }

  @override
  Future<void> archiveConversation(String chatId) async {}

  @override
  Future<AiConversation> createConversation(String firstMessage) async {
    final now = DateTime(2026, 10, 5);
    return conversation ??= AiConversation(
      id: 'chat-test',
      title: firstMessage,
      createdAt: now,
      updatedAt: now,
      lastMessageAt: now,
      messageCount: 0,
      archived: false,
    );
  }

  @override
  Future<AiConversation?> getConversationToResume() async => conversation;

  @override
  Future<List<AiChatMessage>> getMessages(String chatId) async =>
      List<AiChatMessage>.of(messages);

  @override
  Future<void> markEntered(String chatId) async {}

  @override
  Future<void> markExited(String chatId) async {}

  @override
  Future<AiConversation> reactivateConversation(
    AiConversation conversation,
  ) async => conversation;
}

class _NoBetaNotice implements BetaNoticeCoordinator {
  @override
  Future<bool> markShown(
    BetaNoticeReservation reservation, {
    required bool Function() isValid,
  }) async => false;

  @override
  void release(BetaNoticeReservation reservation) {}

  @override
  Future<BetaNoticeReservation?> reserveIfShouldShow(
    String uid,
    BetaNoticeKind kind,
  ) async => null;
}
