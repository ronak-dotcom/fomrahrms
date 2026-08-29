import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

// Best-effort PDF compression via pdf-lib (loaded from CDN in web/index.html):
// re-serializes the PDF with object-stream compression. This shrinks
// redundant objects/streams but can't guarantee hitting an exact target for
// image-heavy/scanned PDFs without re-rendering pages, which this does not do.
//
// dart:js_util and dart:html were removed from the SDK; this uses their
// replacement, dart:js_interop / dart:js_interop_unsafe, for the same
// dynamic property/method access on the pdf-lib global.
Future<Uint8List?> compressPdf(Uint8List bytes) async {
  try {
    final pdfLib   = globalContext.getProperty('PDFLib'.toJS) as JSObject;
    final docClass = pdfLib.getProperty('PDFDocument'.toJS) as JSObject;

    final doc = await docClass
        .callMethod<JSPromise<JSObject>>('load'.toJS, bytes.toJS)
        .toDart;

    final opts = JSObject();
    opts.setProperty('useObjectStreams'.toJS, true.toJS);

    final saved = await doc
        .callMethod<JSPromise<JSUint8Array>>('save'.toJS, opts)
        .toDart;
    return saved.toDart;
  } catch (_) {
    return null;
  }
}
