import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart' show loadPdfium;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../contracts/preview_session.dart';
import '../../infrastructure/private_cache.dart';

/// Local bytes only. No URI loading, link activation, scripts or PDF files in
/// the cache; one bounded page image is held at a time.
class LocalPdfPreview extends StatefulWidget {
  const LocalPdfPreview({
    super.key,
    required this.session,
    required this.name,
    required this.readBytes,
    this.compact = false,
  });
  final PreviewSession session;
  final String name;
  final Future<Uint8List> Function() readBytes;
  final bool compact;
  static const maxBytes = 8 * 1024 * 1024;
  static bool supports(String name, String mimeType) =>
      mimeType == 'application/pdf' ||
      (mimeType == 'application/octet-stream' &&
          name.toLowerCase().endsWith('.pdf'));
  @override
  State<LocalPdfPreview> createState() => LocalPdfPreviewState();
}

class LocalPdfPreviewState extends State<LocalPdfPreview> {
  static Future<void>? _initialization;
  PdfDocument? _document;
  PdfPageRenderCancellationToken? _token;
  Uint8List? _bytes;
  ui.Image? _image;
  Future<void>? _opening, _closing;
  Future<void> _rendering = Future.value();
  bool _closed = false, _disposing = false, _busy = true;
  int _page = 0, _requestedPage = 0;
  String? _error;
  bool get isReady => !_closed && !_busy && _image != null;
  int get pageCount => _document?.pages.length ?? 0;
  int get currentPage => _page;
  ui.Image? get renderedImage => _image;

  static Future<void> _initialize() async {
    final cache = await privateCacheDirectory();
    loadPdfium(); // Includes Flutter's native asset deployment layer.
    await pdfrxInitialize(tmpPath: cache.path);
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    widget.session.registerPreviewCleanup(closePreview);
    _opening = _open();
  }

  void _sessionChanged() {
    if (!widget.session.isUnlocked) unawaited(closePreview());
  }

  Future<void> _open() async {
    try {
      if (!Platform.isLinux) throw const FormatException('此PDF预览仅在Linux启用');
      _bytes = await widget.readBytes();
      if (_closed || !mounted || !widget.session.isUnlocked) return;
      if (_bytes!.length > LocalPdfPreview.maxBytes) {
        throw const FormatException('PDF内嵌预览最多8 MB');
      }
      await (_initialization ??= _initialize());
      if (_closed || !mounted || !widget.session.isUnlocked) return;
      final document = await PdfDocument.openData(
        _bytes!,
        sourceName: 'local-${identityHashCode(this)}',
        maxSizeToCacheOnMemory: LocalPdfPreview.maxBytes,
      );
      _document = document;
      if (_closed || !mounted || !widget.session.isUnlocked) return;
      if (document.pages.isEmpty || document.pages.length > 2000) {
        throw const FormatException('PDF需包含1至2000页');
      }
      _busy = false;
      await goToPage(0);
    } on Object catch (error) {
      if (!_closed) {
        _error = error is FormatException
            ? error.message
            : 'PDF无法打开，请检查格式；加密PDF需先解密';
      }
      await _disposeDocument();
    } finally {
      if (_closed || _document == null) _wipeBytes();
      _busy = false;
      if (mounted && !_disposing) setState(() {});
    }
  }

  Future<void> goToPage(int page) {
    final document = _document;
    if (_closed || _busy || document == null) return Future.value();
    if (page < 0 || page >= pageCount) {
      return Future.error(const FormatException('PDF页码无效'));
    }
    _busy = true;
    _requestedPage = page;
    _error = null;
    if (mounted) setState(() {});
    return _rendering = _render(document, page);
  }

  Future<void> _render(PdfDocument document, int index) async {
    PdfImage? bitmap;
    ui.Image? image;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      final page = document.pages[index];
      if (!page.width.isFinite ||
          !page.height.isFinite ||
          page.width <= 0 ||
          page.height <= 0) {
        throw const FormatException('PDF页面尺寸无效');
      }
      final scale = 1600 / math.max(page.width, page.height);
      _token = page.createCancellationToken();
      bitmap = await page.render(
        fullWidth: math.max(1, page.width * scale),
        fullHeight: math.max(1, page.height * scale),
        cancellationToken: _token,
      );
      if (_closed || !mounted || !widget.session.isUnlocked) return;
      if (bitmap == null) throw const FormatException('PDF页面无法渲染');
      buffer = await ui.ImmutableBuffer.fromUint8List(bitmap.pixels);
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: bitmap.width,
        height: bitmap.height,
        pixelFormat: ui.PixelFormat.bgra8888,
      );
      codec = await descriptor.instantiateCodec();
      image = (await codec.getNextFrame()).image;
      if (_closed || !mounted || !widget.session.isUnlocked) return;
      _image?.dispose();
      _image = image;
      image = null;
      _page = index;
    } on Object {
      if (!_closed) _error = 'PDF页面无法渲染，可以重试';
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      if (bitmap != null) {
        bitmap.pixels.fillRange(0, bitmap.pixels.length, 0);
        bitmap.dispose();
      }
      _token = null;
      _busy = false;
      if (mounted && !_disposing) setState(() {});
    }
  }

  void _wipeBytes() {
    _bytes?.fillRange(0, _bytes!.length, 0);
    _bytes = null;
  }

  Future<void> _disposeDocument() async {
    final document = _document;
    _document = null;
    await document?.dispose();
  }

  Future<void> closePreview() {
    if (_closing != null) return _closing!;
    _closed = true;
    _token?.cancel();
    _image?.dispose();
    _image = null;
    if (mounted && !_disposing) setState(() {});
    return _closing = _finishClosing();
  }

  Future<void> _finishClosing() async {
    try {
      await _opening;
      await _rendering;
      await _disposeDocument();
    } finally {
      _wipeBytes();
    }
  }

  @override
  void dispose() {
    _disposing = true;
    widget.session.removeListener(_sessionChanged);
    unawaited(
      closePreview().whenComplete(
        () => widget.session.unregisterPreviewCleanup(closePreview),
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const Text('预览已关闭');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (_error != null) Text(_error!),
        if (_busy) const LinearProgressIndicator(),
        if (_image != null)
          SizedBox(
            height: widget.compact ? 340 : 480,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Center(
                child: RawImage(image: _image, fit: BoxFit.contain),
              ),
            ),
          ),
        if (pageCount > 0)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('pdf-previous-page'),
                tooltip: '上一页',
                onPressed: _busy || _page == 0
                    ? null
                    : () => goToPage(_page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('第 ${_page + 1} / $pageCount 页'),
              IconButton(
                key: const ValueKey('pdf-next-page'),
                tooltip: '下一页',
                onPressed: _busy || _page + 1 >= pageCount
                    ? null
                    : () => goToPage(_page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              if (_error != null)
                TextButton(
                  onPressed: _busy ? null : () => goToPage(_requestedPage),
                  child: const Text('重试'),
                ),
            ],
          ),
      ],
    );
  }
}
