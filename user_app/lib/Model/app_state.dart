import 'package:flutter/foundation.dart';

/// LOCAL STATE ONLY: in-memory application state for the rider app.
/// Holds the values the UI flows read and write (saved addresses, language).
/// Nothing here is persisted to disk or a backend yet - each field is the
/// integration point for the corresponding profile service.
class RiderAppState extends ChangeNotifier {
  RiderAppState._();
  static final RiderAppState instance = RiderAppState._();

  // Saved addresses (Account -> Home address / Work address)
  final Map<String, String> savedAddresses = {};

  void saveAddress(String type, String address) {
    savedAddresses[type] = address;
    notifyListeners();
  }

  // App language
  String language = 'English';

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }
}
