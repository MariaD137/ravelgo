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

  // Communication channel toggles (Account -> Communication -> Promotions /
  // Ravel Go's offers), keyed by page title since both share the same set of
  // channels but are saved independently.
  final Map<String, Map<String, bool>> communicationPreferences = {};

  void saveCommunicationPreferences(String title, Map<String, bool> values) {
    communicationPreferences[title] = Map.of(values);
    notifyListeners();
  }

  // Surge-hour push notification toggle (Account -> Communication -> Surge
  // hour Notifications).
  bool surgeNotificationsEnabled = true;

  void setSurgeNotificationsEnabled(bool value) {
    surgeNotificationsEnabled = value;
    notifyListeners();
  }
}
