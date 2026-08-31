import 'package:flutter/widgets.dart';

// Displays a locally-picked image by path across platforms. On mobile the
// path is a real file (dart:io File); on web it's a blob URL loaded over the
// network. The dart:io-specific code lives in file_image_io.dart, which is
// only compiled on non-web targets thanks to the conditional import below —
// so the app builds for the browser, where dart:io does not exist.
import 'file_image_io.dart' if (dart.library.html) 'file_image_web.dart' as impl;

Widget localFileImage(String path, {BoxFit fit = BoxFit.cover, Widget? fallback}) {
  return impl.localFileImage(path, fit: fit, fallback: fallback ?? const SizedBox.shrink());
}
