import 'dart:async';
import 'dart:io';

import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/models/ai_conversation.dart';
import 'package:eduflow_ai/pages/ai/ai_chat_page.dart';
import 'package:eduflow_ai/services/ai_chat_history_service.dart';
import 'package:eduflow_ai/services/ai_function_calling_flow.dart';
import 'package:eduflow_ai/services/ai_service.dart';
import 'package:eduflow_ai/services/beta_notice_service.dart';
import 'package:firebase_ai/firebase_ai.dart';
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

  testWidgets('I4: chat e historial usan el repositorio inyectado', (
    tester,
  ) async {
    final history = _FakeAiHistory();
    await history.createConversation('Título del repositorio inyectado');
    final ai = _FakeAiAssistant((_) async => 'Respuesta ficticia');
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Título del repositorio inyectado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'fallo de almacenamiento no se atribuye a Gemini y conserva el reintento',
    (tester) async {
      final history = _FakeAiHistory();
      var writes = 0;
      history.beforeAdd = (role, _) async {
        if (role == AiChatRole.user && writes++ == 0) {
          throw const SocketException('red de prueba desconectada');
        }
      };
      final ai = _FakeAiAssistant((_) async => 'Respuesta ficticia.');
      final session = _readyController();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });

      await _pumpChat(tester, session.controller, ai, history);
      await _send(tester, 'Pregunta ficticia');
      await tester.pumpAndSettle();
      expect(find.textContaining('confirmar el chat'), findsOneWidget);
      expect(find.textContaining('Gemini'), findsNothing);
      expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
      expect(ai.histories, isEmpty);

      await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
      await tester.pumpAndSettle();
      expect(history.messages.where((message) => message.isUser), hasLength(1));
      expect(history.messages.where((message) => message.isError), isEmpty);
      expect(find.text('Respuesta ficticia.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'al volver al chat actual recupera mensajes remotos sin duplicarlos',
    (tester) async {
      final history = _FakeAiHistory();
      final chat = await history.createConversation('Chat de prueba');
      await history.addMessage(
        chatId: chat.id,
        role: AiChatRole.user,
        text: 'Mensaje inicial',
      );
      final ai = _FakeAiAssistant((_) async => 'Respuesta ficticia.');
      final session = _readyController();
      await session.controller.requestPreparation();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AiChatPage(
            sessionController: session.controller,
            betaNoticeService: _NoBetaNotice(),
            aiService: ai,
            historyService: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mensaje inicial'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.history_rounded));
      await tester.pumpAndSettle();
      await history.addMessage(
        chatId: chat.id,
        role: AiChatRole.assistant,
        text: 'Mensaje llegado desde Android',
      );
      await tester.tap(find.text('Chat de prueba'));
      await tester.pumpAndSettle();
      expect(find.text('Mensaje llegado desde Android'), findsOneWidget);
      expect(
        history.messages.where(
          (message) => message.text == 'Mensaje llegado desde Android',
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'al recuperar foco actualiza chat y contexto sin reconsultar Gemini',
    (tester) async {
      final history = _FakeAiHistory();
      final chat = await history.createConversation('Chat de prueba');
      await history.addMessage(
        chatId: chat.id,
        role: AiChatRole.user,
        text: 'Mensaje inicial',
      );
      final ai = _FakeAiAssistant((_) async => 'Respuesta ficticia.');
      final session = _readyController();
      await session.controller.requestPreparation();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AiChatPage(
            sessionController: session.controller,
            betaNoticeService: _NoBetaNotice(),
            aiService: ai,
            historyService: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await history.addMessage(
        chatId: chat.id,
        role: AiChatRole.assistant,
        text: 'Respuesta remota',
      );

      _simulateFocusReturn(tester);
      await tester.pumpAndSettle();
      expect(find.text('Respuesta remota'), findsOneWidget);
      expect(ai.histories, isEmpty);
      await _send(tester, 'Seguimiento');
      await tester.pumpAndSettle();
      expect(ai.histories.single.map((message) => message.text), [
        'Mensaje inicial',
        'Respuesta remota',
        'Seguimiento',
      ]);
      Supabase.instance.client.auth.stopAutoRefresh();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('actualización de foco conserva un envío pendiente', (
    tester,
  ) async {
    final history = _FakeAiHistory();
    final pending = Completer<String>();
    final ai = _FakeAiAssistant((_) => pending.future);
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Pregunta pendiente');
    expect(find.text('Pensando'), findsOneWidget);

    _simulateFocusReturn(tester);
    await tester.pump();
    expect(find.text('Pensando'), findsOneWidget);
    pending.complete('Respuesta confirmada');
    await tester.pumpAndSettle();
    expect(history.messages.where((message) => message.isUser), hasLength(1));
    expect(
      history.messages.where(
        (message) => message.text == 'Respuesta confirmada',
      ),
      hasLength(1),
    );
    Supabase.instance.client.auth.stopAutoRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lista del historial se actualiza al recuperar foco', (
    tester,
  ) async {
    final history = _FakeAiHistory();
    await history.createConversation('Chat inicial');
    final ai = _FakeAiAssistant((_) async => 'Respuesta ficticia.');
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await tester.tap(find.byIcon(Icons.history_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Chat inicial'), findsOneWidget);

    await history.createConversation('Chat llegado desde Android');
    _simulateFocusReturn(tester);
    await tester.pumpAndSettle();
    expect(find.text('Chat llegado desde Android'), findsOneWidget);
    Supabase.instance.client.auth.stopAutoRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'fallo de actualización conserva el chat y permite otro intento',
    (tester) async {
      final history = _FakeAiHistory();
      final chat = await history.createConversation('Chat de prueba');
      await history.addMessage(
        chatId: chat.id,
        role: AiChatRole.user,
        text: 'Mensaje inicial',
      );
      final ai = _FakeAiAssistant((_) async => 'Respuesta ficticia.');
      final session = _readyController();
      await session.controller.requestPreparation();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AiChatPage(
            sessionController: session.controller,
            betaNoticeService: _NoBetaNotice(),
            aiService: ai,
            historyService: history,
          ),
        ),
      );
      await tester.pumpAndSettle();
      history.beforeGetMessages = (_) async =>
          throw const SocketException('red de prueba desconectada');
      _simulateFocusReturn(tester);
      await tester.pumpAndSettle();
      expect(find.text('Mensaje inicial'), findsOneWidget);

      history.beforeGetMessages = null;
      await history.addMessage(
        chatId: chat.id,
        role: AiChatRole.assistant,
        text: 'Respuesta posterior',
      );
      _simulateFocusReturn(tester);
      await tester.pumpAndSettle();
      expect(find.text('Respuesta posterior'), findsOneWidget);
      Supabase.instance.client.auth.stopAutoRefresh();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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

  testWidgets('un fallo Gemini no inutiliza el siguiente mensaje local', (
    tester,
  ) async {
    int attempts = 0;
    final _FakeAiAssistant ai = _FakeAiAssistant((message) async {
      attempts += 1;
      if (message.contains('Big Data')) {
        throw QuotaExceeded('detalle interno de cuota');
      }
      return '¡Hola! Respuesta local disponible.';
    });
    final _FakeAiHistory history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Explícame qué es Big Data');
    await tester.pumpAndSettle();

    expect(find.textContaining('cuota de Gemini'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);

    await _send(tester, 'Hola');
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('¡Hola! Respuesta local disponible.'), findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('incluye intercambios locales anteriores en el siguiente turno', (
    tester,
  ) async {
    final ai = _FakeAiAssistant(
      (message) async => message == 'Hola'
          ? '¡Hola! Respuesta local.'
          : 'Seguimiento atendido.',
    );
    final history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Hola');
    await tester.pumpAndSettle();
    await _send(tester, '¿Y qué más?');
    await tester.pumpAndSettle();
    expect(ai.histories, hasLength(2));
    expect(ai.histories[1].map((item) => item.text), [
      'Hola',
      '¡Hola! Respuesta local.',
      '¿Y qué más?',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('nuevo chat no entrega mensajes del chat anterior', (
    tester,
  ) async {
    final ai = _FakeAiAssistant((_) async => 'Respuesta.');
    final history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Primera pregunta');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_square));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo chat').last);
    await tester.pumpAndSettle();
    await _send(tester, 'Segunda pregunta');
    await tester.pumpAndSettle();
    expect(ai.histories[1].map((item) => item.text), ['Segunda pregunta']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reanudar chat entrega solo su historial al siguiente turno', (
    tester,
  ) async {
    final ai = _FakeAiAssistant((_) async => 'Continuación.');
    final history = _FakeAiHistory();
    final previous = await history.createConversation('Consulta anterior');
    await history.addMessage(
      chatId: previous.id,
      role: AiChatRole.user,
      text: '¿Qué clases tengo hoy?',
    );
    await history.addMessage(
      chatId: previous.id,
      role: AiChatRole.assistant,
      text: 'Matemáticas a las 9:00.',
    );
    final session = _readyController();
    await session.controller.requestPreparation();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          sessionController: session.controller,
          betaNoticeService: _NoBetaNotice(),
          aiService: ai,
          historyService: history,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _send(tester, '¿Y en qué sala?');
    await tester.pumpAndSettle();
    expect(ai.histories.single.map((item) => item.text), [
      '¿Qué clases tengo hoy?',
      'Matemáticas a las 9:00.',
      '¿Y en qué sala?',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cambio de usuario descarta la respuesta pendiente', (
    tester,
  ) async {
    final pending = Completer<String>();
    final ai = _FakeAiAssistant((_) => pending.future);
    final history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Pregunta pendiente');
    session.auth.add(null);
    await tester.pump();
    pending.complete('Respuesta de otro usuario');
    await tester.pumpAndSettle();
    expect(
      history.messages.where((item) => item.role == AiChatRole.assistant),
      isEmpty,
    );
    expect(find.text('Respuesta de otro usuario'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Firestore pendiente no activa la consulta ni confirma el mensaje',
    (tester) async {
      final pendingWrite = Completer<void>();
      final ai = _FakeAiAssistant(
        (message) async =>
            message == 'Hola' ? 'Saludo inicial.' : 'Respuesta académica.',
      );
      final history = _FakeAiHistory();
      final session = _readyController();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });
      await _pumpChat(tester, session.controller, ai, history);
      await _send(tester, 'Hola');
      await tester.pumpAndSettle();
      history.beforeAdd = (role, _) =>
          role == AiChatRole.user ? pendingWrite.future : Future<void>.value();

      const prompt = '¿Qué tareas tengo pendientes?';
      await _send(tester, prompt);
      expect(find.text('Pensando'), findsOneWidget);
      expect(ai.histories, hasLength(1));
      expect(history.messages.where((item) => item.text == prompt), isEmpty);

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.text('Pensando'), findsNothing);
      expect(find.textContaining('confirmar el mensaje'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
      expect(ai.histories, hasLength(1));
      expect(history.messages.where((item) => item.text == prompt), isEmpty);

      history.beforeAdd = null;
      pendingWrite.complete();
      await tester.pump();
      expect(ai.histories, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
      await tester.pumpAndSettle();
      expect(
        history.messages.where((item) => item.text == prompt),
        hasLength(1),
      );
      expect(
        history.messages.where((item) => item.text == 'Respuesta académica.'),
        hasLength(1),
      );
      expect(ai.histories, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('creación pendiente se reintenta con el mismo chat', (
    tester,
  ) async {
    final pendingCreate = Completer<void>();
    final createdIds = <String?>[];
    final ai = _FakeAiAssistant((_) async => 'Chat recuperado.');
    final history = _FakeAiHistory();
    history.beforeCreate = (id) {
      createdIds.add(id);
      return createdIds.length == 1
          ? pendingCreate.future
          : Future<void>.value();
    };
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, '¿Qué tareas tengo pendientes?');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
    expect(history.conversation, isNull);
    expect(ai.histories, isEmpty);

    pendingCreate.complete();
    await tester.pump();
    expect(ai.histories, isEmpty);
    await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
    await tester.pumpAndSettle();
    expect(createdIds, hasLength(2));
    expect(createdIds[0], createdIds[1]);
    expect(history.conversationsById, hasLength(1));
    expect(history.messages.where((item) => item.isUser), hasLength(1));
    expect(find.text('Chat recuperado.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('respuesta Firestore tardía no se duplica al reintentar', (
    tester,
  ) async {
    final pendingAnswer = Completer<void>();
    var assistantWrites = 0;
    final ai = _FakeAiAssistant((_) async => 'Respuesta confirmada.');
    final history = _FakeAiHistory();
    history.beforeAdd = (role, _) {
      if (role == AiChatRole.assistant && assistantWrites++ == 0) {
        return pendingAnswer.future;
      }
      return Future<void>.value();
    };
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, '¿Qué tareas tengo pendientes?');
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
    expect(
      history.messages.where((item) => item.text == 'Respuesta confirmada.'),
      isEmpty,
    );

    pendingAnswer.complete();
    await tester.pump();
    history.beforeAdd = null;
    await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
    await tester.pumpAndSettle();
    expect(ai.histories, hasLength(1));
    expect(history.messages.where((item) => item.isUser), hasLength(1));
    expect(
      history.messages.where((item) => item.text == 'Respuesta confirmada.'),
      hasLength(1),
    );
    expect(find.text('Respuesta confirmada.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('respuesta tardía tras timeout no aparece en un chat nuevo', (
    tester,
  ) async {
    final pendingAnswer = Completer<String>();
    final ai = _FakeAiAssistant(
      (message) => message == 'Pregunta anterior'
          ? pendingAnswer.future
          : Future<String>.value('Respuesta nueva.'),
    );
    final history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Pregunta anterior');
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_square));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo chat').last);
    await tester.pumpAndSettle();
    await _send(tester, 'Pregunta nueva');
    await tester.pumpAndSettle();
    pendingAnswer.complete('Respuesta tardía del chat anterior');
    await tester.pumpAndSettle();
    expect(find.text('Respuesta nueva.'), findsOneWidget);
    expect(find.text('Respuesta tardía del chat anterior'), findsNothing);
    expect(
      history.messages.where(
        (item) => item.text == 'Respuesta tardía del chat anterior',
      ),
      isEmpty,
    );
    expect(ai.histories.last.map((item) => item.text), ['Pregunta nueva']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lectura de historial pendiente permite reintentar sin mezclar', (
    tester,
  ) async {
    final pendingRead = Completer<void>();
    final ai = _FakeAiAssistant((_) async => 'Continuación correcta.');
    final history = _FakeAiHistory();
    final previous = await history.createConversation('Anterior');
    await history.addMessage(
      chatId: previous.id,
      role: AiChatRole.user,
      text: 'Pregunta anterior',
    );
    await history.addMessage(
      chatId: previous.id,
      role: AiChatRole.assistant,
      text: 'Respuesta anterior',
    );
    history.beforeGetMessages = (_) => pendingRead.future;
    final session = _readyController();
    await session.controller.requestPreparation();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          sessionController: session.controller,
          betaNoticeService: _NoBetaNotice(),
          aiService: ai,
          historyService: history,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry-ai-history')), findsOneWidget);
    expect(find.text('Pregunta anterior'), findsNothing);

    history.beforeGetMessages = null;
    pendingRead.complete();
    await tester.tap(find.byKey(const ValueKey('retry-ai-history')));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta anterior'), findsOneWidget);
    await _send(tester, 'Seguimiento');
    await tester.pumpAndSettle();
    expect(ai.histories.single.map((item) => item.text), [
      'Pregunta anterior',
      'Respuesta anterior',
      'Seguimiento',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cambio de usuario invalida una escritura pendiente', (
    tester,
  ) async {
    final pendingWrite = Completer<void>();
    final ai = _FakeAiAssistant((_) async => 'Respuesta que no corresponde.');
    final history = _FakeAiHistory();
    history.beforeAdd = (role, _) =>
        role == AiChatRole.user ? pendingWrite.future : Future<void>.value();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Pregunta en curso');
    session.auth.add(null);
    await tester.pump();
    pendingWrite.complete();
    await tester.pumpAndSettle();
    expect(ai.histories, isEmpty);
    expect(find.text('Respuesta que no corresponde.'), findsNothing);
    expect(
      history.messages.where((item) => item.role == AiChatRole.assistant),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'fallos sucesivos de una pregunta usan un solo error y reintento',
    (tester) async {
      var userWrites = 0;
      var aiAttempts = 0;
      final ai = _FakeAiAssistant((_) async {
        aiAttempts++;
        if (aiAttempts == 1) throw StateError('fallo remoto');
        if (aiAttempts == 2) throw QuotaExceeded('cuota');
        return 'Tienes una tarea pendiente.';
      });
      final history = _FakeAiHistory();
      history.beforeAdd = (role, _) async {
        if (role == AiChatRole.user && userWrites++ == 0) {
          throw const AiChatUnconfirmedDataException();
        }
      };
      final session = _readyController();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });
      const prompt = 'que tares tengo pendientes?';
      await _pumpChat(tester, session.controller, ai, history);
      await _send(tester, prompt);
      await tester.pumpAndSettle();
      expect(find.textContaining('confirmar el chat'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
      expect(history.messages.where((item) => item.isUser), isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        prompt,
      );

      await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
      await tester.pumpAndSettle();
      expect(find.textContaining('confirmar el chat'), findsNothing);
      expect(find.textContaining('No pude responder'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
      expect(history.messages.where((item) => item.isError), hasLength(1));
      expect(history.messages.where((item) => item.isUser), hasLength(1));
      expect(
        history.messagesByChat[history.conversation!.id]!.map(
          (item) => item.role,
        ),
        [AiChatRole.user, AiChatRole.assistant],
      );
      expect(find.text(prompt), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );

      await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No pude responder'), findsNothing);
      expect(find.textContaining('cuota de Gemini'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
      expect(history.messages.where((item) => item.isError), hasLength(1));
      expect(history.messages.where((item) => item.isUser), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
      await tester.pumpAndSettle();
      expect(aiAttempts, 3);
      expect(find.text('Tienes una tarea pendiente.'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-ai-message')), findsNothing);
      expect(history.messages.where((item) => item.isError), isEmpty);
      expect(history.messages.where((item) => item.isUser), hasLength(1));
      expect(
        history.messages.where(
          (item) => item.text == 'Tienes una tarea pendiente.',
        ),
        hasLength(1),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('error anterior no reintenta la pregunta más reciente', (
    tester,
  ) async {
    final sent = <String>[];
    final ai = _FakeAiAssistant((message) async {
      sent.add(message);
      throw StateError('fallo');
    });
    final history = _FakeAiHistory();
    final session = _readyController();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });
    await _pumpChat(tester, session.controller, ai, history);
    await _send(tester, 'Primera pregunta');
    await tester.pumpAndSettle();
    await _send(tester, 'Segunda pregunta');
    await tester.pumpAndSettle();
    expect(history.messages.where((item) => item.isError), hasLength(2));
    expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
    await tester.pumpAndSettle();
    expect(sent.last, 'Segunda pregunta');
    expect(history.messages.where((item) => item.isUser), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'seleccionar chat actual refresca mensajes remotos con reintento pendiente',
    (tester) async {
      var failures = 0;
      final ai = _FakeAiAssistant((message) async {
        if (message == 'Pregunta con error' && failures++ == 0) {
          throw StateError('App Check');
        }
        return 'Respuesta inicial';
      });
      final history = _FakeAiHistory();
      final session = _readyController();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });
      await _pumpChat(tester, session.controller, ai, history);
      await _send(tester, 'Pregunta inicial');
      await tester.pumpAndSettle();
      await _send(tester, 'Pregunta con error');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);

      final chatId = history.conversation!.id;
      await history.addMessage(
        chatId: chatId,
        role: AiChatRole.user,
        text: 'Pregunta desde Android',
      );
      await history.addMessage(
        chatId: chatId,
        role: AiChatRole.assistant,
        text: 'Respuesta desde Android',
      );

      await tester.tap(find.byIcon(Icons.history_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pregunta inicial').last);
      await tester.pumpAndSettle();

      expect(find.text('Respuesta desde Android'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-ai-message')), findsOneWidget);
      expect(history.messages.where((item) => item.isUser), hasLength(3));
      await tester.tap(find.byKey(const ValueKey('retry-ai-message')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('retry-ai-message')), findsNothing);
      expect(
        history.messages.where((item) => item.text == 'Pregunta con error'),
        hasLength(1),
      );
      expect(find.text('Respuesta desde Android'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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

void _simulateFocusReturn(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
  final List<List<AiChatMessage>> histories = [];

  @override
  Future<String> enviarMensaje(
    String mensaje, {
    required List<AiChatMessage> history,
  }) {
    histories.add(List<AiChatMessage>.of(history));
    return send(mensaje);
  }

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
  final Map<String, List<AiChatMessage>> messagesByChat = {};
  AiConversation? conversation;
  int nextMessageId = 0;
  int nextChatId = 0;
  Future<void> Function(AiChatRole role, String? messageId)? beforeAdd;
  Future<void> Function(String? conversationId)? beforeCreate;
  Future<void> Function(String chatId)? beforeGetMessages;
  final Map<String, AiConversation> conversationsById = {};

  @override
  Future<List<AiConversation>> getConversations() async =>
      conversationsById.values.toList();

  @override
  Future<void> deleteConversation(String chatId) async {
    conversationsById.remove(chatId);
    messagesByChat.remove(chatId);
  }

  @override
  Future<AiChatMessage> addMessage({
    required String chatId,
    required AiChatRole role,
    required String text,
    bool isError = false,
    String? messageId,
    String? clearErrorMessageId,
  }) async {
    await beforeAdd?.call(role, messageId);
    if (messageId != null) {
      for (final existing in messagesByChat[chatId] ?? <AiChatMessage>[]) {
        if (existing.id == messageId) {
          if (isError && existing.isError) {
            final updated = AiChatMessage(
              id: messageId,
              role: role,
              text: text,
              createdAt: DateTime(2026, 10, 5),
              isError: true,
            );
            messagesByChat[chatId]!.remove(existing);
            messagesByChat[chatId]!.add(updated);
            messages.remove(existing);
            messages.add(updated);
            return updated;
          }
          if (clearErrorMessageId != null) {
            messages.removeWhere((item) => item.id == clearErrorMessageId);
            messagesByChat[chatId]?.removeWhere(
              (item) => item.id == clearErrorMessageId,
            );
          }
          return existing;
        }
      }
    }
    final message = AiChatMessage(
      id: messageId ?? 'message-${nextMessageId++}',
      role: role,
      text: text,
      createdAt: DateTime(2026, 10, 5),
      isError: isError,
    );
    messages.add(message);
    messagesByChat.putIfAbsent(chatId, () => []).add(message);
    if (clearErrorMessageId != null) {
      messages.removeWhere((item) => item.id == clearErrorMessageId);
      messagesByChat[chatId]?.removeWhere(
        (item) => item.id == clearErrorMessageId,
      );
    }
    return message;
  }

  @override
  Future<void> archiveConversation(String chatId) async {
    if (conversation?.id == chatId) conversation = null;
  }

  @override
  Future<AiConversation> createConversation(
    String firstMessage, {
    String? conversationId,
  }) async {
    await beforeCreate?.call(conversationId);
    final previous = conversationsById[conversationId];
    if (previous != null) return previous;
    final now = DateTime(2026, 10, 5);
    final created = AiConversation(
      id: conversationId ?? 'chat-test-${nextChatId++}',
      title: firstMessage,
      createdAt: now,
      updatedAt: now,
      lastMessageAt: now,
      messageCount: 0,
      archived: false,
    );
    conversationsById[created.id] = created;
    return conversation ??= created;
  }

  @override
  Future<AiConversation?> getConversationToResume() async => conversation;

  @override
  Future<List<AiChatMessage>> getMessages(String chatId) async {
    await beforeGetMessages?.call(chatId);
    return List<AiChatMessage>.of(messagesByChat[chatId] ?? const []);
  }

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
