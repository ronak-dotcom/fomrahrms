import 'dart:async';
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Camera that lives inside the page.
///
/// The previous approach — image_picker on web — triggers a hidden file input,
/// which hands control to the operating system: the native camera opens on top
/// of the browser and the page is backgrounded. Mobile browsers suspend or
/// discard backgrounded pages under memory pressure, so when the camera closes
/// the callback the app is waiting on frequently never fires. It then waits out
/// the timeout and reports failure.
///
/// That is why 10 of 16 employees hit it across different phones and browsers,
/// why it clusters at 09:20–09:40 when everyone checks in at once, and why
/// retrying usually works — the page is still warm the second time.
///
/// getUserMedia renders a live preview in a <video> element inside the page.
/// The browser is never backgrounded, the OS is never handed control, and
/// there is no callback to lose. Different mechanism, not a workaround.
class WebCamera {
  static int _seq = 0;

  /// Opens a full-screen preview and returns PNG bytes, or null if the
  /// employee cancelled or the camera could not start.
  ///
  /// [onUnavailable] fires when getUserMedia itself fails — permission denied,
  /// no camera, or an insecure context — so the caller can fall back rather
  /// than showing an empty black box.
  static Future<Uint8List?> capture({
    required BuildContext context,
    required String label,
    void Function(String reason)? onUnavailable,
  }) async {
    final viewId = 'webcam-${_seq++}';
    final video = html.VideoElement()
      ..autoplay = true
      // Required on iOS, which otherwise takes the video full-screen and
      // out of the page — reintroducing the exact problem this avoids.
      ..setAttribute('playsinline', 'true')
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    html.MediaStream? stream;
    try {
      stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          // Front camera where there is one; ideal rather than exact so a
          // device with only a rear camera still works instead of throwing.
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 960},
        },
        'audio': false,
      });
      video.srcObject = stream;
    } catch (e) {
      onUnavailable?.call('$e');
      return null;
    }

    ui_web.platformViewRegistry.registerViewFactory(viewId, (_) => video);

    // Stopping every track matters: leaving one running keeps the camera
    // light on after the sheet closes, which looks like the app is watching.
    void stopStream() {
      for (final t in stream!.getTracks()) {
        t.stop();
      }
    }

    Uint8List? shot;
    try {
      shot = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _CameraSheet(
          viewId: viewId,
          label: label,
          onCapture: () => _grabFrame(video),
        ),
      );
    } finally {
      stopStream();
    }
    return shot;
  }

  /// Draws the current video frame to a canvas and returns PNG bytes.
  static Future<Uint8List?> _grabFrame(html.VideoElement video) async {
    final w = video.videoWidth;
    final h = video.videoHeight;
    // Zero dimensions mean the stream has not produced a frame yet; capturing
    // would silently save a blank image.
    if (w == 0 || h == 0) return null;

    final canvas = html.CanvasElement(width: w, height: h);
    final ctx = canvas.context2D;
    // Mirrored, so the photo matches what the employee saw while framing it.
    ctx
      ..translate(w, 0)
      ..scale(-1, 1);
    ctx.drawImage(video, 0, 0);

    // toDataUrl rather than toBlob: dart:html's toBlob signature has varied
    // between SDK versions and the callback form needs a FileReader round
    // trip, which is two more things to get wrong on the path that has to be
    // reliable. A data URL is synchronous and the base64 decode is exact.
    final dataUrl = canvas.toDataUrl('image/png');
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    return base64Decode(dataUrl.substring(comma + 1));
  }

  /// Whether this browser can do in-page capture at all. Checked before
  /// offering it so an unsupported browser goes straight to the fallback
  /// rather than showing a preview that never starts.
  static bool get isSupported {
    try {
      // mediaDevices is only exposed in a secure context, so its presence is
      // the check that matters. Avoids a js_util probe, which is another
      // thing that can throw on the path that must not.
      return html.window.navigator.mediaDevices != null;
    } catch (_) {
      return false;
    }
  }
}

class _CameraSheet extends StatefulWidget {
  final String viewId;
  final String label;
  final Future<Uint8List?> Function() onCapture;

  const _CameraSheet({
    required this.viewId,
    required this.label,
    required this.onCapture,
  });

  @override
  State<_CameraSheet> createState() => _CameraSheetState();
}

class _CameraSheetState extends State<_CameraSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _take() async {
    setState(() { _busy = true; _error = null; });
    final bytes = await widget.onCapture();
    if (!mounted) return;
    if (bytes == null) {
      // Usually the stream has not delivered a frame yet, which resolves in a
      // moment — so this invites another try rather than closing the sheet.
      setState(() {
        _busy = false;
        _error = 'The camera is still starting. Tap again in a moment.';
      });
      return;
    }
    Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Expanded(
              child: Text(widget.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            IconButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              tooltip: 'Cancel',
            ),
          ]),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 380,
            width: double.infinity,
            child: Transform.flip(
              flipX: true, // preview mirrored to match the saved photo
              child: HtmlElementView(viewType: widget.viewId),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(_error!,
                style: TextStyle(color: Colors.orange.shade300, fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _take,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text(_busy ? 'Capturing…' : 'Take photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
