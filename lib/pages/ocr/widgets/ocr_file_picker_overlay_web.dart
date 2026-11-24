import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../../services/ocr_file_picker_service.dart';

class OcrFilePickerOverlay extends StatefulWidget {
  const OcrFilePickerOverlay({
    super.key,
    required this.enabled,
    required this.spanish,
    required this.onPicked,
    required this.onError,
  });

  final bool enabled;
  final bool spanish;
  final ValueChanged<OcrPickedFile> onPicked;
  final ValueChanged<Object> onError;

  @override
  State<OcrFilePickerOverlay> createState() => _OcrFilePickerOverlayState();
}

class _OcrFilePickerOverlayState extends State<OcrFilePickerOverlay> {
  StreamSubscription<web.Event>? _changeSubscription;
  web.HTMLInputElement? _input;

  @override
  void didUpdateWidget(covariant OcrFilePickerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spanish != widget.spanish) _setAccessibleLabel();
  }

  @override
  void dispose() {
    _changeSubscription?.cancel();
    super.dispose();
  }

  void _elementCreated(Object element) {
    final input = element as web.HTMLInputElement;
    _input = input;
    input
      ..type = 'file'
      ..accept = '.pdf,.jpg,.jpeg,.png,.webp,application/pdf,image/jpeg,image/png,image/webp'
      ..multiple = false;
    input.style
      ..width = '100%'
      ..height = '100%'
      ..opacity = '0'
      ..cursor = 'pointer'
      ..border = '0'
      ..padding = '0'
      ..margin = '0';
    _setAccessibleLabel();
    _changeSubscription?.cancel();
    _changeSubscription = input.onChange.listen(_fileChanged);
  }

  void _setAccessibleLabel() {
    _input?.setAttribute(
      'aria-label',
      widget.spanish ? 'Elegir PDF o imagen' : 'Choose PDF or image',
    );
  }

  Future<void> _fileChanged(web.Event _) async {
    final input = _input;
    final file = input?.files?.item(0);
    if (input == null || file == null) return;

    input.disabled = true;
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      final picked = OcrPickedFile(
        name: file.name,
        bytes: bytes,
        mimeType: OcrFilePickerService.mimeTypeFromFileName(file.name),
        sizeBytes: bytes.length,
      );
      if (mounted) widget.onPicked(picked);
    } catch (error) {
      if (mounted) widget.onError(error);
    } finally {
      input
        ..value = ''
        ..disabled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return HtmlElementView.fromTagName(
      key: const Key('malla-native-file-picker'),
      tagName: 'input',
      isVisible: false,
      onElementCreated: _elementCreated,
    );
  }
}
