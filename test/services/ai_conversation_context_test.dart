import 'package:eduflow_ai/models/ai_conversation.dart';
import 'package:eduflow_ai/services/ai_conversation_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AiChatMessage message(
    String id,
    AiChatRole role,
    String text, {
    bool error = false,
  }) => AiChatMessage(
    id: id,
    role: role,
    text: text,
    createdAt: DateTime(2026, 10, 27),
    isError: error,
  );

  test('incluye una respuesta local anterior sin duplicar el turno actual', () {
    final history = [
      message('1', AiChatRole.user, '¿Qué clases tengo hoy?'),
      message('2', AiChatRole.assistant, 'Matemáticas a las 9:00.'),
      message('3', AiChatRole.user, '¿Y en qué sala?'),
    ];
    final context = AiConversationContext.completedHistory(
      history,
      currentMessage: '¿Y en qué sala?',
    );
    expect(context.map((item) => item.id), ['1', '2']);
  });

  test('descarta errores y preguntas fallidas al reconstruir', () {
    final history = [
      message('1', AiChatRole.user, 'Hola'),
      message('2', AiChatRole.assistant, '¡Hola!'),
      message('3', AiChatRole.user, 'Consulta fallida'),
      message('4', AiChatRole.assistant, 'Sin conexión', error: true),
      message('5', AiChatRole.user, 'Nueva consulta'),
    ];
    final context = AiConversationContext.completedHistory(
      history,
      currentMessage: 'Nueva consulta',
    );
    expect(context.map((item) => item.id), ['1', '2']);
  });

  test('limita pares completos y nunca mezcla historiales distintos', () {
    final firstChat = [
      for (var i = 0; i < 20; i++) ...[
        message('u$i', AiChatRole.user, 'Pregunta $i'),
        message('a$i', AiChatRole.assistant, 'Respuesta $i'),
      ],
      message('current', AiChatRole.user, 'Seguimiento'),
    ];
    final secondChat = [
      message('other-u', AiChatRole.user, 'Otro usuario'),
      message('other-a', AiChatRole.assistant, 'Otra respuesta'),
      message('other-current', AiChatRole.user, 'Continuar'),
    ];
    final first = AiConversationContext.completedHistory(
      firstChat,
      currentMessage: 'Seguimiento',
    );
    final second = AiConversationContext.completedHistory(
      secondChat,
      currentMessage: 'Continuar',
    );
    expect(first, hasLength(24));
    expect(first.first.id, 'u8');
    expect(first.map((item) => item.id), isNot(contains('other-u')));
    expect(second.map((item) => item.id), ['other-u', 'other-a']);
  });
}
