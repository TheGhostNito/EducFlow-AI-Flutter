import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class OcrPdfPreview extends StatefulWidget {
  const OcrPdfPreview({
    super.key,
    required this.bytes,
    required this.sourceName,
    required this.spanish,
  });

  final Uint8List bytes;
  final String sourceName;
  final bool spanish;

  @override
  State<OcrPdfPreview> createState() => _OcrPdfPreviewState();
}

class _OcrPdfPreviewState extends State<OcrPdfPreview> {
  final PdfViewerController _controller = PdfViewerController();
  int _page = 1;
  int _pageCount = 0;
  bool _ready = false;
  bool _failed = false;

  String _t(String es, String en) => widget.spanish ? es : en;

  void _setReady(PdfDocument document) {
    if (!mounted) return;
    setState(() {
      _pageCount = document.pages.length;
      _page = _controller.pageNumber ?? 1;
      _ready = true;
      _failed = false;
    });
  }

  void _setPage(int? page) {
    if (!mounted || page == null || page == _page) return;
    setState(() => _page = page);
  }

  void _setLoadResult(bool succeeded) {
    if (!mounted || succeeded || _failed) return;
    setState(() {
      _ready = false;
      _failed = true;
    });
  }

  Future<void> _goToPage(int page) async {
    if (!_ready || page < 1 || page > _pageCount) return;
    try {
      await _controller.goToPage(pageNumber: page);
    } catch (_) {
      // Un fallo de navegación no debe impedir analizar el archivo seleccionado.
    }
  }

  Future<void> _changeZoom(bool zoomIn) async {
    if (!_ready) return;
    try {
      if (zoomIn) {
        await _controller.zoomUp();
      } else {
        await _controller.zoomDown();
      }
    } catch (_) {
      // La previsualización es auxiliar y no debe bloquear el flujo OCR.
    }
  }

  bool _handleGeneralTap(
    BuildContext _,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.doubleTap) return false;
    unawaited(_zoomFromDoubleTap(controller, details.localPosition));
    return true;
  }

  Future<void> _zoomFromDoubleTap(
    PdfViewerController controller,
    Offset localPosition,
  ) async {
    try {
      await controller.zoomUpOnLocalPosition(
        localPosition: localPosition,
        loop: true,
      );
    } catch (_) {
      // Los botones de zoom siguen disponibles si el gesto no puede aplicarse.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? const Color(0xFF11151C) : const Color(0xFFF3F4F8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            key: const Key('malla-pdf-preview'),
            height: 360,
            child: PdfViewer.data(
              widget.bytes,
              key: ValueKey(widget.sourceName),
              sourceName: widget.sourceName,
              controller: _controller,
              params: PdfViewerParams(
                backgroundColor: background,
                margin: 10,
                sizeDelegateProvider: const PdfViewerSizeDelegateProviderSmart(
                  maxScale: 6,
                  maxPagesVisible: 2,
                ),
                onViewerReady: (document, _) => _setReady(document),
                onPageChanged: _setPage,
                onGeneralTap: _handleGeneralTap,
                onDocumentLoadFinished: (_, succeeded) =>
                    _setLoadResult(succeeded),
                loadingBannerBuilder: (_, _, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.hourglass_top_rounded,
                        color: Color(0xFF5B5FEF),
                        size: 30,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t('Cargando páginas…', 'Loading pages…'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                errorBannerBuilder: (_, _, _, _) => _fallback(theme),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              key: const Key('malla-pdf-previous-page'),
              tooltip: _t('Página anterior', 'Previous page'),
              visualDensity: VisualDensity.compact,
              onPressed: _ready && _page > 1
                  ? () => _goToPage(_page - 1)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _ready
                    ? _t(
                        'Página $_page de $_pageCount',
                        'Page $_page of $_pageCount',
                      )
                    : _failed
                    ? _t('Vista no disponible', 'Preview unavailable')
                    : _t('Cargando vista previa…', 'Loading preview…'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: const Key('malla-pdf-next-page'),
              tooltip: _t('Página siguiente', 'Next page'),
              visualDensity: VisualDensity.compact,
              onPressed: _ready && _page < _pageCount
                  ? () => _goToPage(_page + 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const Key('malla-pdf-zoom-out'),
              tooltip: _t('Alejar', 'Zoom out'),
              visualDensity: VisualDensity.compact,
              onPressed: _ready ? () => _changeZoom(false) : null,
              icon: const Icon(Icons.zoom_out_rounded),
            ),
            IconButton(
              key: const Key('malla-pdf-zoom-in'),
              tooltip: _t('Ampliar', 'Zoom in'),
              visualDensity: VisualDensity.compact,
              onPressed: _ready ? () => _changeZoom(true) : null,
              icon: const Icon(Icons.zoom_in_rounded),
            ),
          ],
        ),
        Text(
          _t(
            'También puedes pellizcar o tocar dos veces para ampliar.',
            'You can also pinch or double-tap to zoom.',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _fallback(ThemeData theme) {
    return ColoredBox(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF11151C)
          : const Color(0xFFF3F4F8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            key: const Key('malla-pdf-preview-fallback'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFF5B5FEF),
                size: 36,
              ),
              const SizedBox(height: 10),
              Text(
                _t(
                  'No pudimos mostrar las páginas, pero el PDF sigue listo para analizar.',
                  'We could not display the pages, but the PDF is still ready to analyze.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
