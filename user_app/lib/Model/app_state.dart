import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rider-app settings that are genuinely per-device, not business data: none
/// of saved addresses, display language, or notification-channel toggles
/// have a backend field anywhere (User has no language/notification-prefs
/// column, and there is no "favorite places" model) — see the audit note in
/// docs/DEPLOY-RUNBOOK.md-adjacent task notes. This used to be in-memory
/// only ("LOCAL STATE ONLY... nothing here is persisted to disk"), so every
/// one of these silently reverted to its default the moment the app
/// restarted, which reads as broken even though each screen's own Save
/// action reported success. Backed by SharedPreferences now, so "local"
/// actually means "persisted on this device" rather than "for this app
/// session only".
class RiderAppState extends ChangeNotifier {
  RiderAppState._();
  static final RiderAppState instance = RiderAppState._();

  /// A second, independent instance backed by the same on-device store —
  /// used only by tests to prove a value survives a real disk round-trip
  /// (a fresh `load()` on a fresh object) rather than just re-reading the
  /// singleton's own in-memory fields. Never use this outside a test: the
  /// rest of the app must share the one `.instance` so every screen sees
  /// the same state.
  @visibleForTesting
  RiderAppState.forTest();

  static const _kAddressesKey = 'rider_saved_addresses';
  static const _kLanguageKey = 'rider_language';
  static const _kCommunicationKey = 'rider_communication_preferences';
  static const _kSurgeNotificationsKey = 'rider_surge_notifications_enabled';

  SharedPreferences? _prefs;
  bool _loaded = false;

  // Saved addresses (Account -> Home address / Work address)
  final Map<String, String> savedAddresses = {};

  // App language
  String language = 'English';

  // Communication channel toggles (Account -> Communication -> Promotions /
  // Ravel Go's offers), keyed by page title since both share the same set of
  // channels but are saved independently.
  final Map<String, Map<String, bool>> communicationPreferences = {};

  // Surge-hour push notification toggle (Account -> Communication -> Surge
  // hour Notifications).
  bool surgeNotificationsEnabled = true;

  /// Loads persisted values from disk. Call once, early (see main.dart) —
  /// every screen above already reads/writes the plain fields synchronously,
  /// so this only needs to run before the first frame, not before every
  /// access. Safe to call more than once; a second call is a no-op.
  Future<void> load() async {
    if (_loaded) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final addressesJson = _prefs!.getString(_kAddressesKey);
      if (addressesJson != null) {
        final decoded = jsonDecode(addressesJson);
        if (decoded is Map) {
          savedAddresses.addAll(decoded.map((k, v) => MapEntry('$k', '$v')));
        }
      }
      language = _prefs!.getString(_kLanguageKey) ?? language;
      surgeNotificationsEnabled = _prefs!.getBool(_kSurgeNotificationsKey) ?? surgeNotificationsEnabled;
      final commsJson = _prefs!.getString(_kCommunicationKey);
      if (commsJson != null) {
        final decoded = jsonDecode(commsJson);
        if (decoded is Map) {
          decoded.forEach((title, values) {
            if (values is Map) {
              communicationPreferences['$title'] = values.map((k, v) => MapEntry('$k', v == true));
            }
          });
        }
      }
    } catch (e) {
      // A corrupt or inaccessible store just means defaults stick for this
      // run — never crash startup over a settings read.
      debugPrint('[RiderAppState] load failed: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  void _persistString(String key, String value) {
    // Best-effort, fire-and-forget: a write failure (e.g. storage momentarily
    // unavailable) should never block or crash the UI action that triggered
    // it — the in-memory value the user just set is already correct for the
    // rest of this session either way.
    _prefs?.setString(key, value).catchError((e) {
      debugPrint('[RiderAppState] failed to persist $key: $e');
      return false;
    });
  }

  void _persistBool(String key, bool value) {
    _prefs?.setBool(key, value).catchError((e) {
      debugPrint('[RiderAppState] failed to persist $key: $e');
      return false;
    });
  }

  void saveAddress(String type, String address) {
    savedAddresses[type] = address;
    _persistString(_kAddressesKey, jsonEncode(savedAddresses));
    notifyListeners();
  }

  void setLanguage(String value) {
    language = value;
    _persistString(_kLanguageKey, value);
    notifyListeners();
  }

  void saveCommunicationPreferences(String title, Map<String, bool> values) {
    communicationPreferences[title] = Map.of(values);
    _persistString(_kCommunicationKey, jsonEncode(communicationPreferences));
    notifyListeners();
  }

  void setSurgeNotificationsEnabled(bool value) {
    surgeNotificationsEnabled = value;
    _persistBool(_kSurgeNotificationsKey, value);
    notifyListeners();
  }
}
