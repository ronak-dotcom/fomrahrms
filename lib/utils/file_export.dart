/// Saves [bytes] as a file named [filename]: a browser download on web, the
/// share sheet on a phone.
export 'file_export_native.dart'
  if (dart.library.html) 'file_export_web.dart';
