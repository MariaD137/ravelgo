import 'package:flutter/foundation.dart';

/// LOCAL STATE ONLY: in-memory application state for the rider app.
/// Holds the values the UI flows read and write (saved addresses, favorites,
/// payment methods, language). Nothing here is persisted to disk or a
/// backend yet - each field is the integration point for the corresponding
/// profile/payments service.
class RiderAppState extends ChangeNotifier {
  RiderAppState._();
  static final RiderAppState instance = RiderAppState._();

  // Saved addresses (Account -> Home address / Work address)
  final Map<String, String> savedAddresses = {};

  void saveAddress(String type, String address) {
    savedAddresses[type] = address;
    notifyListeners();
  }

  // Payment methods (masked display data only - never store raw card data)
  final List<SavedPaymentMethod> paymentMethods = [];

  void addPaymentMethod(SavedPaymentMethod method) {
    paymentMethods.add(method);
    notifyListeners();
  }

  // App language
  String language = 'English';

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }
}

/// Masked payment-method details for display. Only the brand, last four
/// digits and expiry are kept - full card numbers are never stored locally.
class SavedPaymentMethod {
  final String brand;
  final String lastFour;
  final String expiry;

  const SavedPaymentMethod({required this.brand, required this.lastFour, required this.expiry});
}
