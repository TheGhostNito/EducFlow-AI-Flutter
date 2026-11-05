import 'package:flutter/material.dart';

class FormSubmitController {
  Future<void> Function()? _submitCallback;

  Future<void> submit() async {
    await _submitCallback?.call();
  }

  void attach(Future<void> Function() callback) {
    _submitCallback = callback;
  }

  void detach(Future<void> Function() callback) {
    if (identical(_submitCallback, callback)) {
      _submitCallback = null;
    }
  }
}

class FormStickyActionBar extends StatelessWidget {
  const FormStickyActionBar({
    super.key,
    required this.cancelLabel,
    required this.saveLabel,
    required this.saving,
    required this.onCancel,
    required this.onSave,
    this.maxContentWidth = 1050,
  });

  static const double _narrowBreakpoint = 360;

  final String cancelLabel;
  final String saveLabel;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final double maxContentWidth;

  static double contentClearance(double width) {
    return width < _narrowBreakpoint + 20 ? 184 : 126;
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: dark ? const Color(0xFF18181D) : Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.42 : 0.14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: dark ? const Color(0xFF303038) : const Color(0xFFE2E6ED),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(vertical: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool stackButtons =
                        constraints.maxWidth < _narrowBreakpoint;
                    final Widget cancelButton = _buildCancelButton(dark);
                    final Widget saveButton = _buildSaveButton();

                    if (stackButtons) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          saveButton,
                          const SizedBox(height: 10),
                          cancelButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: cancelButton),
                        const SizedBox(width: 10),
                        Expanded(child: saveButton),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCancelButton(bool dark) {
    return SizedBox(
      height: 49,
      child: OutlinedButton(
        onPressed: saving ? null : onCancel,
        style: OutlinedButton.styleFrom(
          foregroundColor: dark
              ? const Color(0xFFE5E9F0)
              : const Color(0xFF4B5563),
          side: BorderSide(
            color: dark ? const Color(0xFF343C48) : const Color(0xFFDFE3EA),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: Text(
          cancelLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    const Color primaryColor = Color(0xFF5B5FEF);

    return SizedBox(
      height: 49,
      child: ElevatedButton(
        onPressed: saving ? null : onSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primaryColor.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: saving
              ? const SizedBox(
                  key: ValueKey('saving'),
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  saveLabel,
                  key: const ValueKey('save'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}
