import 'package:flutter/widgets.dart';

import '../../../services/ocr_file_picker_service.dart';

class OcrFilePickerOverlay extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
