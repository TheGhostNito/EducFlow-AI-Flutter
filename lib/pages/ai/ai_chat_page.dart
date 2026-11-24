import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/navigation/main_navigation.dart';

import '../../models/ai_conversation.dart';
import '../../models/plan_estudio.dart';
import '../../services/ai_chat_history_service.dart';
import '../../services/supabase_ai_chat_history_repository.dart';
import '../../services/ai_function_calling_flow.dart';
import '../../services/ai_failure_diagnostics.dart';
import '../../services/ai_service.dart';
import '../../services/ai_study_plan_message_codec.dart';
import '../../services/beta_notice_service.dart';
import '../../services/plan_estudio_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_status_snackbar.dart';
import '../../widgets/beta_notice_dialog.dart';
import '../../core/auth/session_controller.dart';
import 'ai_chat_history_page.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({
    super.key,
    this.sessionController,
    this.betaNoticeService,
    this.betaDialogPresenter,
    this.initialConversationLoadOverride,
    this.aiService,
    this.historyService,
    this.planEstudioPersistence,
  });

  final SessionController? sessionController;
  final BetaNoticeCoordinator? betaNoticeService;
  final BetaNoticeDialogPresenter? betaDialogPresenter;
  final Future<void> Function()? initialConversationLoadOverride;
  final AiAssistantClient? aiService;
  final AiChatHistoryRepository? historyService;
  final PlanEstudioPersistence? planEstudioPersistence;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> with WidgetsBindingObserver {
  static const Color _primaryColor = Color(0xFF5B5FEF);
  static const Duration _historyTimeout = Duration(seconds: 10);
  static const Duration _conversationWriteTimeout = Duration(seconds: 10);
  static const Duration _messageWriteTimeout = Duration(seconds: 8);
  static const Duration _assistantTimeout = Duration(seconds: 60);
  static const Duration _errorWriteTimeout = Duration(seconds: 3);

  late final AiAssistantClient _aiService;
  late final AiChatHistoryRepository _historyService;
  late final PlanEstudioPersistence _planEstudioPersistence;
  late final BetaNoticeCoordinator _betaNoticeService;
  late final SessionController _sessionController;
  final TranslationService _translationService = TranslationService.instance;

  final TextEditingController _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final FocusNode _focusNode = FocusNode();

  final List<AiChatMessage> _messages = [];
  final Map<String, PlanEstudioPropuesto> _studyPlansByMessage = {};
  final Set<String> _savingStudyPlans = {};
  final Set<String> _savedStudyPlans = {};
  final Set<String> _cancelledStudyPlans = {};
  String? _activeStudyPlanMessageId;

  AiConversation? _conversation;
  bool _loadingConversation = true;
  bool _historyLoadError = false;
  bool _sending = false;
  bool _betaDialogInProgress = false;
  bool _betaDialogInvalidated = false;
  String? _lastFailedMessage;
  _AiPendingSend? _pendingSend;
  int _requestGeneration = 0;
  bool _refreshingHistory = false;
  GlobalKey? _betaDialogKey;

  bool get _spanish => _translationService.isSpanish;

  @override
  void initState() {
    super.initState();

    _sessionController = widget.sessionController ?? SessionController.instance;
    _betaNoticeService = widget.betaNoticeService ?? BetaNoticeService.instance;
    _aiService = widget.aiService ?? AiService.instance;
    _historyService =
        widget.historyService ?? SupabaseAiChatHistoryRepository.instance;
    _planEstudioPersistence =
        widget.planEstudioPersistence ?? PlanEstudioService.instance;

    _translationService.addListener(_refreshLanguage);
    _focusNode.addListener(_refreshFocus);
    WidgetsBinding.instance.addObserver(this);

    _loadInitialConversation();
  }

  @override
  void dispose() {
    _invalidateBetaDialog();
    final String? conversationId = _conversation?.id;

    if (conversationId != null) {
      unawaited(
        _historyService.markExited(conversationId).catchError((Object _) {}),
      );
    }

    _translationService.removeListener(_refreshLanguage);
    _focusNode.removeListener(_refreshFocus);
    WidgetsBinding.instance.removeObserver(this);

    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  Future<void> _mostrarAvisoBetaIA() async {
    final session = _sessionController;
    final ticket = session.captureTicket();
    if (!mounted ||
        ticket == null ||
        _loadingConversation ||
        _betaDialogInProgress ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    BetaNoticeReservation? reservation;
    VoidCallback? sessionListener;
    try {
      reservation = await _betaNoticeService.reserveIfShouldShow(
        ticket.uid,
        BetaNoticeKind.ai,
      );
      if (reservation == null ||
          !mounted ||
          !session.isCurrentTicket(ticket) ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      _betaDialogInProgress = true;
      _betaDialogInvalidated = false;
      _betaDialogKey = GlobalKey();
      sessionListener = () {
        if (!session.isCurrentTicket(ticket)) _invalidateBetaDialog();
      };
      session.addListener(sessionListener);

      await (widget.betaDialogPresenter ?? showBetaNoticeDialog)(
        context,
        spanish: _spanish,
        kind: BetaNoticeKind.ai,
        dialogKey: _betaDialogKey,
        onInvalidated: () => _betaDialogInvalidated = true,
      );

      bool remainsValid() {
        return mounted &&
            !_betaDialogInvalidated &&
            session.isCurrentTicket(ticket) &&
            ModalRoute.of(context)?.isCurrent == true;
      }

      if (!remainsValid()) return;
      await _betaNoticeService.markShown(reservation, isValid: remainsValid);
    } catch (error) {
      debugPrint('No se pudo completar el aviso Beta de IA: $error');
    } finally {
      if (sessionListener != null) session.removeListener(sessionListener);
      if (reservation != null) _betaNoticeService.release(reservation);
      _betaDialogInProgress = false;
      _betaDialogKey = null;
    }
  }

  void _invalidateBetaDialog() {
    _betaDialogInvalidated = true;
    final dialogContext = _betaDialogKey?.currentContext;
    final route = dialogContext == null ? null : ModalRoute.of(dialogContext);
    if (route == null || !route.isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  Future<void> _loadInitialConversation() async {
    final int loadGeneration = ++_requestGeneration;
    final sessionTicket = _sessionController.captureTicket();
    if (mounted) {
      setState(() {
        _loadingConversation = true;
        _historyLoadError = false;
      });
    }
    final override = widget.initialConversationLoadOverride;
    if (override != null) {
      try {
        await override();
      } catch (_) {
        // El override solo permite aislar la carga inicial en pruebas.
      } finally {
        if (mounted) {
          setState(() => _loadingConversation = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mostrarAvisoBetaIA();
          });
        }
      }
      return;
    }
    try {
      final AiConversation? conversation = await _awaitStage(
        _historyService.getConversationToResume(),
        _historyTimeout,
        'recuperar_chat',
      );
      if (sessionTicket == null ||
          !_sessionController.isCurrentTicket(sessionTicket) ||
          loadGeneration != _requestGeneration) {
        return;
      }

      if (conversation == null) {
        _aiService.iniciarNuevoChat();

        if (!mounted) {
          return;
        }

        setState(() {
          _conversation = null;
          _messages.clear();
          _clearStudyPlans();
        });

        return;
      }

      final List<AiChatMessage> messages = await _awaitStage(
        _historyService.getMessages(conversation.id),
        _historyTimeout,
        'leer_historial',
      );
      final restored = await _restoreStudyPlanHistory(messages);
      if (!_sessionController.isCurrentTicket(sessionTicket) ||
          loadGeneration != _requestGeneration) {
        return;
      }

      _aiService.iniciarConversacion(
        conversationId: conversation.id,
        history: restored.messages,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _conversation = conversation;
        _messages
          ..clear()
          ..addAll(restored.messages);
        _applyRestoredStudyPlans(restored);
      });

      _scrollToBottom();
    } catch (error, stackTrace) {
      if (sessionTicket == null ||
          !_sessionController.isCurrentTicket(sessionTicket) ||
          loadGeneration != _requestGeneration) {
        return;
      }
      debugPrint(
        'EducFlow AI history error: ${AiFailureDiagnostics.from(error).toSafeLog()}',
      );

      debugPrintStack(
        label: 'EducFlow AI history stack trace',
        stackTrace: stackTrace,
      );

      if (mounted) {
        setState(() => _historyLoadError = true);
        showAppStatusSnackBar(
          context,
          message: _spanish
              ? 'No pudimos recuperar el chat anterior.'
              : 'We could not restore the previous chat.',
          type: AppStatusType.error,
        );
      }
    } finally {
      if (mounted &&
          loadGeneration == _requestGeneration &&
          sessionTicket != null &&
          _sessionController.isCurrentTicket(sessionTicket)) {
        setState(() {
          _loadingConversation = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mostrarAvisoBetaIA();
        });
      }
    }
  }

  Future<T> _awaitStage<T>(Future<T> future, Duration timeout, String stage) =>
      future.timeout(
        timeout,
        onTimeout: () =>
            throw AiRequestTimeoutException(timeout: timeout, stage: stage),
      );

  void _refreshLanguage() {
    if (mounted) {
      setState(() {});
    }
  }

  void _refreshFocus() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCurrentConversation());
    }
  }

  Future<void> _refreshCurrentConversation({bool fromHistory = false}) async {
    final conversation = _conversation;
    final ticket = _sessionController.captureTicket();
    if (!mounted ||
        _refreshingHistory ||
        _sending ||
        _loadingConversation ||
        _historyLoadError ||
        (!fromHistory && _pendingSend != null) ||
        conversation == null ||
        ticket == null ||
        (!fromHistory && ModalRoute.of(context)?.isCurrent != true)) {
      return;
    }

    final generation = _requestGeneration;
    _refreshingHistory = true;
    try {
      final messages = await _awaitStage(
        _historyService.getMessages(conversation.id),
        _historyTimeout,
        'leer_historial',
      );
      final restored = await _restoreStudyPlanHistory(messages);
      if (!mounted ||
          generation != _requestGeneration ||
          !_sessionController.isCurrentTicket(ticket) ||
          _conversation?.id != conversation.id ||
          _sending ||
          (!fromHistory && _pendingSend != null) ||
          (!fromHistory && ModalRoute.of(context)?.isCurrent != true)) {
        return;
      }

      final pending = _pendingSend;
      final refreshed = List<AiChatMessage>.of(restored.messages);
      if (fromHistory && pending != null) {
        final ids = refreshed.map((message) => message.id).toSet();
        for (final local in _messages) {
          if ((local.id == pending.userMessageId ||
                  local.id == pending.errorMessageId) &&
              ids.add(local.id)) {
            refreshed.add(local);
          }
        }
      }

      var unchanged = refreshed.length == _messages.length;
      if (unchanged) {
        for (var index = 0; index < refreshed.length; index++) {
          final local = _messages[index];
          final remote = refreshed[index];
          if (local.id != remote.id ||
              local.role != remote.role ||
              local.text != remote.text ||
              local.isError != remote.isError) {
            unchanged = false;
            break;
          }
        }
      }
      _aiService.iniciarConversacion(
        conversationId: conversation.id,
        history: refreshed,
      );
      setState(() {
        _messages
          ..clear()
          ..addAll(refreshed);
        _applyRestoredStudyPlans(restored);
      });
      if (!unchanged) _scrollToBottom();
    } catch (error) {
      debugPrint(
        'EducFlow AI history refresh error: '
        '${AiFailureDiagnostics.from(error, chatStorage: true).toSafeLog()}',
      );
    } finally {
      _refreshingHistory = false;
    }
  }

  void _back() {
    HapticFeedback.selectionClick();
    MainNavigation.goTo(context, SeccionPrincipal.inicio);
  }

  Future<void> _openHistory() async {
    if (_sending || _loadingConversation || _historyLoadError) {
      return;
    }
    final ticket = _sessionController.captureTicket();
    if (ticket == null) return;
    bool currentSession() =>
        mounted && _sessionController.isCurrentTicket(ticket);

    HapticFeedback.selectionClick();

    final AiConversation? current = _conversation;

    try {
      if (current != null) {
        await _awaitStage(
          _historyService.markExited(current.id),
          _conversationWriteTimeout,
          'salir_chat',
        );
      }

      if (!mounted || !currentSession()) {
        return;
      }

      final AiConversation? selected = await Navigator.of(context)
          .push<AiConversation>(
            MaterialPageRoute(
              builder: (_) => AiChatHistoryPage(
                currentConversationId: current?.id,
                historyService: _historyService,
              ),
            ),
          );

      if (!currentSession()) {
        return;
      }

      if (selected != null) {
        if (selected.id != current?.id) {
          final AiConversation active = await _awaitStage(
            _historyService.reactivateConversation(selected),
            _conversationWriteTimeout,
            'reactivar_chat',
          );

          final List<AiChatMessage> messages = await _awaitStage(
            _historyService.getMessages(active.id),
            _historyTimeout,
            'leer_historial',
          );
          final restored = await _restoreStudyPlanHistory(messages);

          _aiService.iniciarConversacion(
            conversationId: active.id,
            history: restored.messages,
          );

          if (!currentSession()) {
            return;
          }

          setState(() {
            ++_requestGeneration;
            _conversation = active;
            _messages
              ..clear()
              ..addAll(restored.messages);
            _applyRestoredStudyPlans(restored);
            _pendingSend = null;
            _lastFailedMessage = null;
          });

          _scrollToBottom();

          return;
        }

        await _awaitStage(
          _historyService.markEntered(selected.id),
          _conversationWriteTimeout,
          'entrar_chat',
        );
        await _refreshCurrentConversation(fromHistory: true);
        return;
      }

      // Si solo abrió el historial y volvió,
      // comprobamos nuevamente la ventana
      // de 30 minutos.
      final AiConversation? resumed = await _awaitStage(
        _historyService.getConversationToResume(),
        _historyTimeout,
        'recuperar_chat',
      );

      if (!currentSession()) {
        return;
      }

      if (resumed == null) {
        _aiService.iniciarNuevoChat();

        setState(() {
          ++_requestGeneration;
          _conversation = null;
          _messages.clear();
          _clearStudyPlans();
          _pendingSend = null;
          _lastFailedMessage = null;
        });

        return;
      }

      if (resumed.id == current?.id) {
        await _refreshCurrentConversation(fromHistory: true);
        return;
      }

      final List<AiChatMessage> messages = await _awaitStage(
        _historyService.getMessages(resumed.id),
        _historyTimeout,
        'leer_historial',
      );
      final restored = await _restoreStudyPlanHistory(messages);
      if (!currentSession()) return;

      _aiService.iniciarConversacion(
        conversationId: resumed.id,
        history: restored.messages,
      );

      setState(() {
        ++_requestGeneration;
        _conversation = resumed;
        _messages
          ..clear()
          ..addAll(restored.messages);
        _applyRestoredStudyPlans(restored);
        _pendingSend = null;
        _lastFailedMessage = null;
      });

      _scrollToBottom();
    } catch (error) {
      if (!mounted || !currentSession()) return;
      showAppStatusSnackBar(
        context,
        message: _spanish
            ? 'No pude confirmar el cambio de chat. Revisa tu conexión e inténtalo nuevamente.'
            : 'I could not confirm the chat change. Check your connection and retry.',
        type: AppStatusType.error,
      );
    }
  }

  Future<void> _newChat() async {
    if (_sending || _loadingConversation || _historyLoadError) {
      return;
    }
    final ticket = _sessionController.captureTicket();
    if (ticket == null) return;

    HapticFeedback.selectionClick();

    if (_messages.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (dialogContext) {
        final bool dark = Theme.of(dialogContext).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: dark ? const Color(0xFF18181D) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(_spanish ? '¿Nuevo chat?' : 'New chat?'),
          content: Text(
            _spanish
                ? 'La conversación actual se guardará en tu historial y comenzará una nueva.'
                : 'The current conversation will be saved to your history and a new one will start.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_spanish ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(_spanish ? 'Nuevo chat' : 'New chat'),
            ),
          ],
        );
      },
    );

    if (confirm != true ||
        !mounted ||
        !_sessionController.isCurrentTicket(ticket)) {
      return;
    }

    final String? currentId = _conversation?.id;

    if (currentId != null) {
      try {
        await _awaitStage(
          _historyService.archiveConversation(currentId),
          _conversationWriteTimeout,
          'archivar_chat',
        );
      } catch (_) {
        if (mounted) {
          showAppStatusSnackBar(
            context,
            message: _spanish
                ? 'No pude confirmar el nuevo chat. Revisa tu conexión e inténtalo nuevamente.'
                : 'I could not confirm the new chat. Check your connection and retry.',
            type: AppStatusType.error,
          );
        }
        return;
      }
    }

    if (!mounted || !_sessionController.isCurrentTicket(ticket)) return;

    _aiService.iniciarNuevoChat();

    setState(() {
      ++_requestGeneration;
      _conversation = null;
      _messages.clear();
      _clearStudyPlans();
      _messageController.clear();
      _pendingSend = null;
      _lastFailedMessage = null;
    });

    _focusNode.requestFocus();
  }

  Future<void> _sendSuggestion(String text) async {
    _messageController.text = text;
    await _sendMessage();
  }

  Future<void> _sendMessage({String? retryText}) async {
    final String text = (retryText ?? _messageController.text).trim();

    if (text.isEmpty || _sending || _loadingConversation || _historyLoadError) {
      return;
    }
    final sessionTicket = _sessionController.captureTicket();
    if (sessionTicket == null) return;
    final _AiPendingSend pending =
        _pendingSend != null &&
            _lastFailedMessage == text &&
            (_conversation == null ||
                _conversation!.id == _pendingSend!.conversationId)
        ? _pendingSend!
        : _AiPendingSend(
            text: text,
            conversationId: _conversation?.id ?? _newRequestId(),
            userMessageId: _newRequestId(),
            assistantMessageId: _newRequestId(),
            errorMessageId: _newRequestId(),
          );
    _pendingSend = pending;
    pending.attempts++;
    final int generation = ++_requestGeneration;
    String stage = 'crear_chat';

    bool isCurrent() =>
        mounted &&
        generation == _requestGeneration &&
        _sessionController.isCurrentTicket(sessionTicket) &&
        (_conversation == null || _conversation!.id == pending.conversationId);

    HapticFeedback.selectionClick();

    setState(() {
      if (retryText == null || _messageController.text.trim() == text) {
        _messageController.clear();
      }
      _sending = true;
      _lastFailedMessage = null;
    });

    try {
      AiConversation? conversation = _conversation;
      if (conversation == null) {
        conversation = await _awaitStage(
          _historyService.createConversation(
            text,
            conversationId: pending.conversationId,
          ),
          _conversationWriteTimeout,
          'crear_chat',
        );
        if (!isCurrent()) return;
        _aiService.iniciarConversacion(conversationId: conversation!.id);
        setState(() => _conversation = conversation);
      }

      if (!_messages.any((message) => message.id == pending.userMessageId)) {
        stage = 'guardar_pregunta';
        final AiChatMessage userMessage = await _awaitStage(
          _historyService.addMessage(
            chatId: conversation.id,
            role: AiChatRole.user,
            text: text,
            messageId: pending.userMessageId,
          ),
          _messageWriteTimeout,
          'guardar_pregunta',
        );
        if (!isCurrent()) return;
        setState(() {
          if (!_messages.any((message) => message.id == userMessage.id)) {
            _messages.add(userMessage);
          }
          if (_messageController.text.trim() == text) {
            _messageController.clear();
          }
        });
      }
      _scrollToBottom();

      stage = 'consultar_asistente';
      final String response =
          pending.response ??
          await _awaitStage(
            _aiService.enviarMensaje(
              text,
              history: List<AiChatMessage>.of(_messages),
            ),
            _assistantTimeout,
            'consultar_asistente',
          );
      if (!isCurrent()) return;
      pending.response = response;

      pending.planProposal ??= _aiService is AiStudyPlanProposalSource
          ? (_aiService as AiStudyPlanProposalSource)
                .tomarUltimaPropuestaPlanEstudio()
          : null;
      final storedResponse = pending.planProposal == null
          ? response
          : AiStudyPlanMessageCodec.encodeProposal(
              response,
              pending.planProposal!,
            );

      stage = 'guardar_respuesta';
      final AiChatMessage storedAssistantMessage = await _awaitStage(
        _historyService.addMessage(
          chatId: conversation.id,
          role: AiChatRole.assistant,
          text: storedResponse,
          messageId: pending.assistantMessageId,
          clearErrorMessageId: pending.errorMessageId,
        ),
        _messageWriteTimeout,
        'guardar_respuesta',
      );
      if (!isCurrent()) return;
      final decoded = AiStudyPlanMessageCodec.decode(
        storedAssistantMessage.text,
      );
      final assistantMessage = storedAssistantMessage.copyWith(
        text: decoded.visibleText,
      );
      final planProposal = pending.planProposal ?? decoded.proposal;

      setState(() {
        if (!_messages.any((message) => message.id == assistantMessage.id)) {
          _messages.add(assistantMessage);
        }
        if (planProposal != null) {
          _studyPlansByMessage[assistantMessage.id] = planProposal;
          _activeStudyPlanMessageId = assistantMessage.id;
        }
        _messages.removeWhere(
          (message) => message.id == pending.errorMessageId,
        );
        if (_messageController.text.trim() == text) {
          _messageController.clear();
        }
        _lastFailedMessage = null;
        _pendingSend = null;
      });
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      final bool storageStage =
          stage == 'crear_chat' ||
          stage == 'guardar_pregunta' ||
          stage == 'guardar_respuesta';
      final diagnostics = AiFailureDiagnostics.from(
        error,
        chatStorage: storageStage,
      );
      assert(() {
        debugPrint(
          '[EducFlow AI][send_failed] ${{'request': pending.userMessageId.substring(0, 8), 'attempt': pending.attempts, 'stage': stage, ...diagnostics.toSafeLog()}}',
        );
        return true;
      }());

      debugPrintStack(label: 'EducFlow AI stack trace', stackTrace: stackTrace);

      final bool timeout = error is AiRequestTimeoutException;
      final int timeoutSeconds = error is AiRequestTimeoutException
          ? error.timeout.inSeconds
          : AiFunctionCallingFlow.defaultTimeout.inSeconds;
      final bool storageTimeout =
          timeout &&
          (error.stage == 'crear_chat' ||
              error.stage == 'guardar_pregunta' ||
              error.stage == 'guardar_respuesta');
      final String errorText = storageTimeout
          ? (_spanish
                ? 'No pude confirmar el mensaje con el servidor en $timeoutSeconds segundos. Revisa tu conexión y reinténtalo.'
                : 'I could not confirm the message with the server within $timeoutSeconds seconds. Check your connection and retry.')
          : timeout
          ? (_spanish
                ? 'La consulta tardó más de $timeoutSeconds segundos. Puedes reintentarla sin perder tu mensaje.'
                : 'The request took longer than $timeoutSeconds seconds. You can retry without losing your message.')
          : diagnostics.userMessage(spanish: _spanish);

      _lastFailedMessage = text;
      if (!_messages.any((message) => message.id == pending.userMessageId) &&
          _messageController.text.trim().isEmpty) {
        _messageController.text = text;
      }

      final AiConversation? conversation = _conversation;

      if (conversation != null) {
        try {
          final AiChatMessage errorMessage = await _awaitStage(
            _historyService.addMessage(
              chatId: conversation.id,
              role: AiChatRole.assistant,
              text: errorText,
              isError: true,
              messageId: pending.errorMessageId,
            ),
            _errorWriteTimeout,
            'guardar_error',
          );

          if (isCurrent()) {
            setState(() {
              _upsertError(errorMessage);
            });
          }
        } catch (_) {
          if (isCurrent()) _showLocalError(errorText, pending.errorMessageId);
        }
      } else if (isCurrent()) {
        _showLocalError(errorText, pending.errorMessageId);
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        if (!_sessionController.isCurrentTicket(sessionTicket)) {
          _aiService.iniciarNuevoChat();
          setState(() {
            _conversation = null;
            _messages.clear();
            _clearStudyPlans();
            _lastFailedMessage = null;
            _pendingSend = null;
            _sending = false;
          });
        } else {
          setState(() {
            _sending = false;
          });

          _scrollToBottom();
        }
      }
    }
  }

  Future<void> _retryLastMessage() async {
    final text = _lastFailedMessage;
    if (text == null || text.isEmpty || _sending) return;
    await _sendMessage(retryText: text);
  }

  void _showLocalError(String text, String id) {
    setState(() {
      _upsertError(
        AiChatMessage(
          id: id,
          role: AiChatRole.assistant,
          text: text,
          createdAt: DateTime.now(),
          isError: true,
        ),
      );
    });
  }

  void _upsertError(AiChatMessage error) {
    final index = _messages.indexWhere((message) => message.id == error.id);
    if (index >= 0) _messages.removeAt(index);
    _messages.add(error);
  }

  String _newRequestId() {
    final random = math.Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: const Cubic(0.22, 1, 0.36, 1),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(dark),

                  Expanded(
                    child: _loadingConversation
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: _primaryColor,
                              strokeWidth: 3,
                            ),
                          )
                        : _historyLoadError
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _spanish
                                      ? 'No pude recuperar el chat. Revisa tu conexión.'
                                      : 'I could not restore the chat. Check your connection.',
                                ),
                                TextButton(
                                  key: const ValueKey('retry-ai-history'),
                                  onPressed: _loadInitialConversation,
                                  child: Text(
                                    _spanish ? 'Reintentar' : 'Retry',
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _messages.isEmpty
                        ? _buildEmptyState(dark)
                        : _buildConversation(dark),
                  ),

                  _buildComposer(dark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader(bool dark) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: dark ? const Color(0xFF26262D) : const Color(0xFFE7EAF0),
          ),
        ),
      ),
      child: Row(
        children: [
          _headerButton(
            dark: dark,
            icon: Ionicons.chevronBackOutline,
            onTap: _back,
          ),

          const SizedBox(width: 10),

          Container(
            width: 37,
            height: 37,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF272733) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Ionicons.sparkles,
              color: _primaryColor,
              size: 18,
            ),
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EducFlow AI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  _spanish ? 'Asistente académico' : 'Academic assistant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFF8F96A3)
                        : const Color(0xFF6B7280),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          _headerButton(
            dark: dark,
            icon: Icons.edit_square,
            onTap: _sending ? null : _newChat,
            accent: true,
          ),

          const SizedBox(width: 7),

          _headerButton(
            dark: dark,
            icon: Icons.history_rounded,
            onTap: _openHistory,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required bool dark,
    required IconData icon,
    required VoidCallback? onTap,
    bool accent = false,
  }) {
    return AppPressable(
      scale: 0.88,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: onTap == null ? 0.42 : 1,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1C1C22) : const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: dark ? const Color(0xFF303038) : const Color(0xFFE2E6ED),
              ),
            ),
            child: Icon(
              icon,
              color: accent
                  ? _primaryColor
                  : (dark ? const Color(0xFFE7EAF0) : const Color(0xFF374151)),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================

  Widget _buildEmptyState(bool dark) {
    final List<_SuggestionData> suggestions = _spanish
        ? const [
            _SuggestionData(
              icon: Icons.calendar_today_outlined,
              title: 'Clases de mañana',
              prompt: '¿Qué clases tengo mañana?',
            ),
            _SuggestionData(
              icon: Icons.checklist_rounded,
              title: 'Tareas pendientes',
              prompt: '¿Qué tareas tengo pendientes?',
            ),
            _SuggestionData(
              icon: Icons.school_outlined,
              title: 'Próximas evaluaciones',
              prompt: '¿Cuáles son mis próximas evaluaciones?',
            ),
          ]
        : const [
            _SuggestionData(
              icon: Icons.calendar_today_outlined,
              title: 'Tomorrow\'s classes',
              prompt: 'What classes do I have tomorrow?',
            ),
            _SuggestionData(
              icon: Icons.checklist_rounded,
              title: 'Pending tasks',
              prompt: 'What tasks do I have pending?',
            ),
            _SuggestionData(
              icon: Icons.school_outlined,
              title: 'Upcoming evaluations',
              prompt: 'What are my upcoming evaluations?',
            ),
          ];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _focusNode.unfocus();
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                const SizedBox(height: 4),

                Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF252532)
                        : const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(
                      color: _primaryColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Icon(
                    Ionicons.sparkles,
                    color: _primaryColor,
                    size: 28,
                  ),
                ),

                const SizedBox(height: 21),

                Text(
                  _spanish ? '¿En qué te ayudo hoy?' : 'How can I help today?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 25,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),

                const SizedBox(height: 9),

                Text(
                  _spanish
                      ? 'Consulta tus clases, tareas, evaluaciones o asignaturas. Revisa siempre la información antes de tomar decisiones académicas.'
                      : 'Ask about your classes, tasks, evaluations or subjects. Always review the information before making academic decisions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFF9BA3B2)
                        : const Color(0xFF6B7280),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),

                const SizedBox(height: 26),

                for (int index = 0; index < suggestions.length; index++) ...[
                  _buildSuggestionCard(dark, suggestions[index]),
                  if (index != suggestions.length - 1)
                    const SizedBox(height: 9),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(bool dark, _SuggestionData suggestion) {
    return AppPressable(
      scale: 0.985,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _sending ? null : () => _sendSuggestion(suggestion.prompt),
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF18181D) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF252532)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(suggestion.icon, color: _primaryColor, size: 19),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  suggestion.title,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFE7EAF0)
                        : const Color(0xFF374151),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const Icon(
                Icons.arrow_forward_rounded,
                color: _primaryColor,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // CONVERSATION
  // =========================================================

  Widget _buildConversation(bool dark) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _focusNode.unfocus();
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView.builder(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 26),
            itemCount: _messages.length + (_sending ? 1 : 0),
            itemBuilder: (context, index) {
              if (_sending && index == _messages.length) {
                return _buildThinkingRow(dark);
              }

              return _buildMessage(dark, _messages[index]);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(bool dark, AiChatMessage message) {
    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(left: 58, bottom: 20),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6266F3), Color(0xFF5256E8)],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(21),
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(21),
                bottomRight: Radius.circular(21),
              ),
            ),
            child: Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiAvatar(dark, error: message.isError),

          const SizedBox(width: 10),

          Expanded(
            child: message.isError
                ? _buildErrorMessage(dark, message)
                : _buildAiResponse(dark, message),
          ),
        ],
      ),
    );
  }

  Widget _buildAiResponse(bool dark, AiChatMessage message) {
    final plan = _studyPlansByMessage[message.id];
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF17171C) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(7),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(
          color: dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
        ),
        boxShadow: dark
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EDUCFLOW AI',
            style: TextStyle(
              color: _primaryColor,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),

          const SizedBox(height: 8),

          MarkdownBody(
            data: message.text,
            selectable: true,
            shrinkWrap: true,
            styleSheet: _markdownStyle(dark),
          ),
          if (plan != null) ...[
            const SizedBox(height: 13),
            _buildStudyPlanCard(dark: dark, messageId: message.id, plan: plan),
          ],
        ],
      ),
    );
  }

  Widget _buildStudyPlanCard({
    required bool dark,
    required String messageId,
    required PlanEstudioPropuesto plan,
  }) {
    final saving = _savingStudyPlans.contains(plan.id);
    final saved = _savedStudyPlans.contains(plan.id);
    final cancelled = _cancelledStudyPlans.contains(plan.id);
    final active = _activeStudyPlanMessageId == messageId;
    final superseded = !active && !saved && !cancelled;

    return Container(
      key: ValueKey('study-plan-${plan.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF202027) : const Color(0xFFF7F7FF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: dark ? const Color(0xFF393946) : const Color(0xFFDCDDFB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_stories_outlined,
                color: _primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.titulo,
                  style: TextStyle(
                    color: dark ? Colors.white : const Color(0xFF20223A),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${plan.sesiones.length} ${plan.sesiones.length == 1 ? 'sesión' : 'sesiones'}',
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFB8B9C8)
                      : const Color(0xFF60647A),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.asignaturaNombre,
            style: const TextStyle(
              color: _primaryColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 11),
          for (var index = 0; index < plan.sesiones.length; index++) ...[
            _buildStudySession(dark, plan.sesiones[index]),
            if (index != plan.sesiones.length - 1)
              const Divider(height: 17, thickness: 0.6),
          ],
          const SizedBox(height: 11),
          if (saved)
            _studyPlanStatus(
              Icons.check_circle_outline_rounded,
              _spanish ? 'Guardado en Calendario' : 'Saved to Calendar',
              const Color(0xFF059669),
            )
          else if (cancelled)
            _studyPlanStatus(
              Icons.cancel_outlined,
              _spanish ? 'Propuesta cancelada' : 'Proposal cancelled',
              const Color(0xFFB45309),
            )
          else if (superseded)
            _studyPlanStatus(
              Icons.update_rounded,
              _spanish
                  ? 'Reemplazado por una versión posterior'
                  : 'Replaced by a newer version',
              const Color(0xFF6B7280),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 7,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('modify-study-plan-${plan.id}'),
                  onPressed: saving
                      ? null
                      : () => _prepareStudyPlanModification(plan),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(_spanish ? 'Modificar' : 'Modify'),
                ),
                FilledButton.icon(
                  key: ValueKey('save-study-plan-${plan.id}'),
                  onPressed: saving
                      ? null
                      : () => _saveStudyPlan(plan, messageId),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.calendar_month_outlined, size: 17),
                  label: Text(_spanish ? 'Guardar' : 'Save'),
                ),
                TextButton(
                  key: ValueKey('cancel-study-plan-${plan.id}'),
                  onPressed: saving
                      ? null
                      : () => _cancelStudyPlan(plan, messageId),
                  child: Text(_spanish ? 'Cancelar' : 'Cancel'),
                ),
              ],
            ),
          if (saved) ...[
            const SizedBox(height: 7),
            TextButton.icon(
              key: ValueKey('open-calendar-study-plan-${plan.id}'),
              onPressed: () =>
                  MainNavigation.goTo(context, SeccionPrincipal.calendario),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(_spanish ? 'Ver Calendario' : 'View Calendar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudySession(bool dark, SesionPlanEstudio session) {
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(session.fecha);
    final end = TimeOfDay.fromDateTime(session.fin).format(context);
    final start = TimeOfDay.fromDateTime(session.inicio).format(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: _primaryColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.titulo,
                style: TextStyle(
                  color: dark ? Colors.white : const Color(0xFF282A3D),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$date · $start–$end · ${session.duracionMinutos} min',
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFAEB0BD)
                      : const Color(0xFF666A7C),
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                session.actividad,
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFC8CAD4)
                      : const Color(0xFF4E5264),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _studyPlanStatus(IconData icon, String text, Color color) => Row(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  void _prepareStudyPlanModification(PlanEstudioPropuesto plan) {
    _messageController.text = _spanish
        ? 'Quiero modificar este plan: '
        : 'I want to modify this plan: ';
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
    _focusNode.requestFocus();
  }

  Future<void> _cancelStudyPlan(
    PlanEstudioPropuesto plan,
    String messageId,
  ) async {
    if (_savingStudyPlans.contains(plan.id)) return;
    setState(() => _savingStudyPlans.add(plan.id));
    try {
      await _persistStudyPlanEvent(
        plan: plan,
        messageId: messageId,
        state: AiStudyPlanEventState.cancelled,
      );
      if (!mounted) return;
      (_aiService is AiStudyPlanProposalSource)
          ? (_aiService as AiStudyPlanProposalSource).descartarPlanEstudio(
              plan.id,
            )
          : null;
      setState(() {
        _savingStudyPlans.remove(plan.id);
        _cancelledStudyPlans.add(plan.id);
        if (_studyPlansByMessage[_activeStudyPlanMessageId]?.id == plan.id) {
          _activeStudyPlanMessageId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingStudyPlans.remove(plan.id));
      showAppStatusSnackBar(
        context,
        message: _spanish
            ? 'No pude confirmar la cancelación. Revisa tu conexión e inténtalo nuevamente.'
            : 'I could not confirm the cancellation. Check your connection and retry.',
        type: AppStatusType.error,
      );
    }
  }

  Future<void> _saveStudyPlan(
    PlanEstudioPropuesto plan,
    String messageId,
  ) async {
    if (_savingStudyPlans.contains(plan.id) ||
        _savedStudyPlans.contains(plan.id)) {
      return;
    }
    setState(() => _savingStudyPlans.add(plan.id));
    try {
      final result = await _planEstudioPersistence.guardar(plan);
      if (!mounted) return;
      try {
        await _persistStudyPlanEvent(
          plan: plan,
          messageId: messageId,
          state: AiStudyPlanEventState.saved,
        );
      } catch (_) {
        // Las tareas y sus marcadores siguen siendo la fuente de verdad. Si
        // este evento falla, la recarga recupera el estado desde ellas.
      }
      if (!mounted) return;
      (_aiService is AiStudyPlanProposalSource)
          ? (_aiService as AiStudyPlanProposalSource).descartarPlanEstudio(
              plan.id,
            )
          : null;
      setState(() {
        _savedStudyPlans.add(plan.id);
        _savingStudyPlans.remove(plan.id);
        if (_studyPlansByMessage[_activeStudyPlanMessageId]?.id == plan.id) {
          _activeStudyPlanMessageId = null;
        }
      });
      showAppStatusSnackBar(
        context,
        message: _spanish
            ? '${result.total} sesiones confirmadas en el Calendario.'
            : '${result.total} sessions confirmed in Calendar.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingStudyPlans.remove(plan.id));
      showAppStatusSnackBar(
        context,
        message: _spanish
            ? 'No se confirmó el plan completo. Puedes reintentar sin duplicar sesiones.'
            : 'The complete plan was not confirmed. You can retry without duplicating sessions.',
        type: AppStatusType.error,
      );
    }
  }

  Future<_RestoredStudyPlanHistory> _restoreStudyPlanHistory(
    List<AiChatMessage> storedMessages,
  ) async {
    final visibleMessages = <AiChatMessage>[];
    final plansByMessage = <String, PlanEstudioPropuesto>{};
    final eventStates = <String, AiStudyPlanEventState>{};

    for (final message in storedMessages) {
      if (message.isUser || message.isError) {
        visibleMessages.add(message);
        continue;
      }
      final decoded = AiStudyPlanMessageCodec.decode(message.text);
      final proposal = decoded.proposal;
      if (proposal != null) plansByMessage[message.id] = proposal;
      final event = decoded.event;
      if (event != null) eventStates[event.planId] = event.state;
      if (decoded.visibleText.trim().isNotEmpty) {
        visibleMessages.add(message.copyWith(text: decoded.visibleText));
      }
    }

    var savedPlans = eventStates.entries
        .where((entry) => entry.value == AiStudyPlanEventState.saved)
        .map((entry) => entry.key)
        .toSet();
    if (plansByMessage.isNotEmpty &&
        _planEstudioPersistence is PlanEstudioStatusReader) {
      try {
        savedPlans = await (_planEstudioPersistence as PlanEstudioStatusReader)
            .obtenerIdsPlanesGuardados();
      } catch (_) {
        // Si la lectura de tareas falla, el último evento cifrado confirmado
        // conserva un estado seguro sin crear ni modificar actividades.
      }
    }

    final cancelledPlans = eventStates.entries
        .where(
          (entry) =>
              entry.value == AiStudyPlanEventState.cancelled &&
              !savedPlans.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toSet();
    String? activeMessageId;
    for (final entry in plansByMessage.entries) {
      if (!savedPlans.contains(entry.value.id) &&
          !cancelledPlans.contains(entry.value.id)) {
        activeMessageId = entry.key;
      }
    }
    return _RestoredStudyPlanHistory(
      messages: visibleMessages,
      plansByMessage: plansByMessage,
      savedPlans: savedPlans,
      cancelledPlans: cancelledPlans,
      activeMessageId: activeMessageId,
    );
  }

  void _applyRestoredStudyPlans(_RestoredStudyPlanHistory restored) {
    _studyPlansByMessage
      ..clear()
      ..addAll(restored.plansByMessage);
    _savingStudyPlans.clear();
    _savedStudyPlans
      ..clear()
      ..addAll(restored.savedPlans);
    _cancelledStudyPlans
      ..clear()
      ..addAll(restored.cancelledPlans);
    _activeStudyPlanMessageId = restored.activeMessageId;
  }

  void _clearStudyPlans() {
    _studyPlansByMessage.clear();
    _savingStudyPlans.clear();
    _savedStudyPlans.clear();
    _cancelledStudyPlans.clear();
    _activeStudyPlanMessageId = null;
  }

  Future<void> _persistStudyPlanEvent({
    required PlanEstudioPropuesto plan,
    required String messageId,
    required AiStudyPlanEventState state,
  }) async {
    final conversation = _conversation;
    if (conversation == null) throw StateError('No existe un chat activo.');
    await _awaitStage(
      _historyService.addMessage(
        chatId: conversation.id,
        role: AiChatRole.assistant,
        text: AiStudyPlanMessageCodec.encodeEvent(
          messageId: messageId,
          planId: plan.id,
          state: state,
        ),
        messageId: '${messageId}_plan_${state.name}',
      ),
      _messageWriteTimeout,
      'guardar_estado_plan',
    );
  }

  MarkdownStyleSheet _markdownStyle(bool dark) {
    final Color main = dark ? const Color(0xFFF1F2F5) : const Color(0xFF1F2937);

    final Color secondary = dark
        ? const Color(0xFFB1B6C0)
        : const Color(0xFF6B7280);

    return MarkdownStyleSheet(
      p: TextStyle(color: main, fontSize: 14, height: 1.55),
      strong: TextStyle(
        color: dark ? Colors.white : const Color(0xFF111827),
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      em: TextStyle(color: main, fontSize: 14, fontStyle: FontStyle.italic),
      h1: TextStyle(color: main, fontSize: 20, fontWeight: FontWeight.w800),
      h2: TextStyle(color: main, fontSize: 18, fontWeight: FontWeight.w800),
      h3: TextStyle(color: main, fontSize: 16, fontWeight: FontWeight.w800),
      listBullet: const TextStyle(
        color: _primaryColor,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      blockquote: TextStyle(color: secondary, fontSize: 13.5, height: 1.5),
      blockquoteDecoration: BoxDecoration(
        color: _primaryColor.withValues(alpha: dark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: _primaryColor, width: 3)),
      ),
      code: TextStyle(
        color: dark ? const Color(0xFFE7E8FF) : const Color(0xFF3439A6),
        fontSize: 12.5,
        fontFamily: 'monospace',
        backgroundColor: dark
            ? const Color(0xFF222229)
            : const Color(0xFFF1F2FA),
      ),
      codeblockDecoration: BoxDecoration(
        color: dark ? const Color(0xFF222229) : const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark ? const Color(0xFF34343C) : const Color(0xFFE1E4EB),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
            width: 0.7,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(bool dark, AiChatMessage message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF241A1D) : const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? const Color(0xFF513036) : const Color(0xFFF3CACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: TextStyle(
              color: dark ? const Color(0xFFF0C5C5) : const Color(0xFF991B1B),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          if (_lastFailedMessage != null &&
              _pendingSend?.errorMessageId == message.id) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('retry-ai-message'),
              onPressed: _sending ? null : _retryLastMessage,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(_spanish ? 'Reintentar' : 'Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinkingRow(bool dark) {
    return Padding(
      padding: const EdgeInsets.only(right: 90, bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiAvatar(dark),

          const SizedBox(width: 10),

          Container(
            height: 37,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF18181D) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _ThinkingDots(),

                const SizedBox(width: 9),

                Text(
                  _spanish ? 'Pensando' : 'Thinking',
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFF9BA3B2)
                        : const Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiAvatar(bool dark, {bool error = false}) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: error
            ? (dark ? const Color(0xFF3A2328) : const Color(0xFFFEECEC))
            : (dark ? const Color(0xFF252532) : const Color(0xFFEEF0FF)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        error ? Icons.error_outline_rounded : Ionicons.sparkles,
        color: error ? const Color(0xFFDC2626) : _primaryColor,
        size: 17,
      ),
    );
  }

  // =========================================================
  // COMPOSER
  // =========================================================

  Widget _buildComposer(bool dark) {
    final bool canSend =
        !_sending &&
        !_loadingConversation &&
        !_historyLoadError &&
        _messageController.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52, maxHeight: 132),
              padding: const EdgeInsets.fromLTRB(17, 5, 6, 5),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1C1C22) : Colors.white,
                borderRadius: BorderRadius.circular(27),
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? _primaryColor
                      : (dark
                            ? const Color(0xFF393941)
                            : const Color(0xFFDFE3EA)),
                  width: _focusNode.hasFocus ? 1.15 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) {
                        setState(() {});
                      },
                      onTapOutside: (_) {
                        _focusNode.unfocus();
                      },
                      decoration: InputDecoration(
                        hintText: _spanish
                            ? 'Pregúntale a EducFlow AI'
                            : 'Ask EducFlow AI',
                        hintStyle: TextStyle(
                          color: dark
                              ? const Color(0xFF777E8B)
                              : const Color(0xFF9CA3AF),
                          fontSize: 13.5,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                      ),
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  AppPressable(
                    scale: 0.88,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canSend ? _sendMessage : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: canSend
                              ? _primaryColor
                              : (dark
                                    ? const Color(0xFF2B2B33)
                                    : const Color(0xFFE8EAF5)),
                          shape: BoxShape.circle,
                        ),
                        child: _sending
                            ? const _TinyThinkingDots()
                            : Icon(
                                Icons.arrow_upward_rounded,
                                color: canSend
                                    ? Colors.white
                                    : (dark
                                          ? const Color(0xFF777887)
                                          : const Color(0xFFA0A3C7)),
                                size: 21,
                              ),
                      ),
                    ),
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

class _SuggestionData {
  const _SuggestionData({
    required this.icon,
    required this.title,
    required this.prompt,
  });

  final IconData icon;
  final String title;
  final String prompt;
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final int active = (_controller.value * 3).floor().clamp(0, 2);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int index = 0; index < 3; index++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B5FEF)
                      .withValues(alpha: index == active ? 1 : 0.32),
                  shape: BoxShape.circle,
                ),
              ),
              if (index != 2) const SizedBox(width: 4),
            ],
          ],
        );
      },
    );
  }
}

class _AiPendingSend {
  _AiPendingSend({
    required this.text,
    required this.conversationId,
    required this.userMessageId,
    required this.assistantMessageId,
    required this.errorMessageId,
  });

  final String text;
  final String conversationId;
  final String userMessageId;
  final String assistantMessageId;
  final String errorMessageId;
  String? response;
  PlanEstudioPropuesto? planProposal;
  int attempts = 0;
}

class _RestoredStudyPlanHistory {
  const _RestoredStudyPlanHistory({
    required this.messages,
    required this.plansByMessage,
    required this.savedPlans,
    required this.cancelledPlans,
    required this.activeMessageId,
  });

  final List<AiChatMessage> messages;
  final Map<String, PlanEstudioPropuesto> plansByMessage;
  final Set<String> savedPlans;
  final Set<String> cancelledPlans;
  final String? activeMessageId;
}

class _TinyThinkingDots extends StatefulWidget {
  const _TinyThinkingDots();

  @override
  State<_TinyThinkingDots> createState() => _TinyThinkingDotsState();
}

class _TinyThinkingDotsState extends State<_TinyThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final int active = (_controller.value * 3).floor().clamp(0, 2);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int index = 0; index < 3; index++) ...[
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: index == active ? 1 : 0.38,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              if (index != 2) const SizedBox(width: 3),
            ],
          ],
        );
      },
    );
  }
}
