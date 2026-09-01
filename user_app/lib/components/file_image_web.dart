import 'package:flutter/widgets.dart';

// Web implementation: image_picker returns a blob URL for the picked file,
// which loads through an <img> element via Image.network.
Widget localFileImage(String path, {required BoxFit fit, required Widget fallback}) {
  if (path.isEmpty) return fallback;
  return Image.network(path, fit: fit, errorBuilder: (_, __, ___) => fallback);
}
