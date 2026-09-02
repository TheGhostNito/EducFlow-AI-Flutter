import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../models/ai_conversation.dart';
import '../../services/ai_chat_history_service.dart';
import '../../services/time_format_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_status_snackbar.dart';

class AiChatHistoryPage extends StatefulWidget {
  const AiChatHistoryPage({super.key, this.currentConversationId});

  final String? currentConversationId;

  @override
  State<AiChatHistoryPage> createState() => _AiChatHistoryPageState();
}

class _AiChatHistoryPageState extends State<AiChatHistoryPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final AiChatHistoryService _historyService = AiChatHistoryService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  List<AiConversation> _conversations = [];

  bool _loading = true;

  bool get _spanish => _translationService.isSpanish;

  @override
  void initState() {
    super.initState();

    _translationService.addListener(_refresh);

    _timeFormatService.addListener(_refresh);

    _load();
  }

  @override
  void dispose() {
    _translationService.removeListener(_refresh);

    _timeFormatService.removeListener(_refresh);

    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    try {
      final List<AiConversation> conversations = await _historyService
          .getConversations();

      if (!mounted) {
        return;
      }

      setState(() {
        _conversations = conversations;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      showAppStatusSnackBar(
        context,
        message: _spanish
            ? 'No pudimos cargar el historial.'
            : 'We could not load chat history.',
        type: AppStatusType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _back() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  void _selectConversation(AiConversation conversation) {
    HapticFeedback.selectionClick();

    Navigator.of(context).pop(conversation);
  }

  Future<void> _deleteConversation(AiConversation conversation) async {
    if (conversation.id == widget.currentConversationId) {
      showAppStatusSnackBar(
        context,
        message: _spanish
            ? 'El chat actual no se elimina desde el historial.'
            : 'The current chat cannot be deleted from history.',
        type: AppStatusType.info,
      );

      return;
    }

    HapticFeedback.selectionClick();

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
          title: Text(
            _spanish ? '¿Eliminar conversación?' : 'Delete conversation?',
          ),
          content: Text(
            _spanish
                ? 'Se eliminarán todos los mensajes de "${conversation.title}".'
                : 'All messages from "${conversation.title}" will be deleted.',
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
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: Text(_spanish ? 'Eliminar' : 'Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    try {
      await _historyService.deleteConversation(conversation.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _conversations.removeWhere((item) => item.id == conversation.id);
      });

      showAppStatusSnackBar(
        context,
        message: _spanish ? 'Conversación eliminada.' : 'Conversation deleted.',
        type: AppStatusType.success,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      showAppStatusSnackBar(
        context,
        message: _spanish
            ? 'No pudimos eliminar la conversación.'
            : 'We could not delete the conversation.',
        type: AppStatusType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(dark),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _primaryColor,
                        strokeWidth: 3,
                      ),
                    )
                  : _conversations.isEmpty
                  ? _buildEmpty(dark)
                  : RefreshIndicator(
                      color: _primaryColor,
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 30),
                        itemCount: _conversations.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          return _buildConversationCard(
                            dark,
                            _conversations[index],
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

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
          AppPressable(
            scale: 0.88,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _back,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF1C1C22)
                      : const Color(0xFFF4F5F8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF303038)
                        : const Color(0xFFE2E6ED),
                  ),
                ),
                child: Icon(
                  Ionicons.chevronBackOutline,
                  color: dark
                      ? const Color(0xFFE7EAF0)
                      : const Color(0xFF374151),
                  size: 19,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _spanish ? 'Historial' : 'History',
                  style: TextStyle(
                    color: dark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  _spanish
                      ? 'Tus conversaciones con EducFlow AI'
                      : 'Your EducFlow AI conversations',
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
        ],
      ),
    );
  }

  Widget _buildEmpty(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF252532) : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: _primaryColor,
                size: 28,
              ),
            ),

            const SizedBox(height: 17),

            Text(
              _spanish
                  ? 'Todavía no hay conversaciones'
                  : 'No conversations yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              _spanish
                  ? 'Cuando inicies nuevos chats aparecerán aquí.'
                  : 'New chats will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? const Color(0xFF9BA3B2) : const Color(0xFF6B7280),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationCard(bool dark, AiConversation conversation) {
    final bool current = conversation.id == widget.currentConversationId;

    return AppPressable(
      scale: 0.99,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectConversation(conversation),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 9, 14),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF18181D) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: current
                  ? _primaryColor.withValues(alpha: 0.65)
                  : (dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF252532)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Ionicons.sparkles,
                  color: _primaryColor,
                  size: 19,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: dark
                                  ? const Color(0xFFF1F2F5)
                                  : const Color(0xFF1F2937),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),

                        if (current) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(
                                alpha: dark ? 0.18 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _spanish ? 'Actual' : 'Current',
                              style: const TextStyle(
                                color: _primaryColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 5),

                    Text(
                      '${_formatDate(conversation.updatedAt)} · '
                      '${conversation.messageCount} '
                      '${_messageCountLabel(conversation.messageCount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFF8F96A3)
                            : const Color(0xFF6B7280),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              if (!current)
                IconButton(
                  tooltip: _spanish ? 'Eliminar' : 'Delete',
                  onPressed: () {
                    _deleteConversation(conversation);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: const Color(0xFFDC2626),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _primaryColor,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final DateTime now = DateTime.now();

    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime date = DateTime(value.year, value.month, value.day);

    final int difference = today.difference(date).inDays;

    final String time = _timeFormatService.formatStoredTime(
      context,
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}',
    );

    if (difference == 0) {
      return _spanish ? 'Hoy · $time' : 'Today · $time';
    }

    if (difference == 1) {
      return _spanish ? 'Ayer · $time' : 'Yesterday · $time';
    }

    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year} · $time';
  }

  String _messageCountLabel(int count) {
    if (_spanish) {
      return count == 1 ? 'mensaje' : 'mensajes';
    }

    return count == 1 ? 'message' : 'messages';
  }
}
