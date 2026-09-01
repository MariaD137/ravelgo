import 'dart:io';
import 'package:flutter/widgets.dart';

// Mobile/desktop implementation: the picked path is a real file on disk.
Widget localFileImage(String path, {required BoxFit fit, required Widget fallback}) {
  if (path.isEmpty) return fallback;
  final file = File(path);
  return file.existsSync() ? Image.file(file, fit: fit) : fallback;
}
