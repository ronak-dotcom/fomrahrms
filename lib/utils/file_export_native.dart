import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> exportBytes(String filename, Uint8List bytes, String mimeType) async {
  await Share.shareXFiles([XFile.fromData(bytes, name: filename, mimeType: mimeType)]);
}
