import 'package:eduflow_ai/pages/ocr/widgets/ocr_file_picker_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('web monta el input nativo sobre el selector OCR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 76,
          child: OcrFilePickerOverlay(
            enabled: true,
            spanish: true,
            onPicked: (_) {},
            onError: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('malla-native-file-picker')), findsOneWidget);
  }, skip: !kIsWeb);
}
