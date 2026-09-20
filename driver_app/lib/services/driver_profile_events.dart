import 'package:flutter/foundation.dart';

/// App-wide "your driver record may have changed on the server — re-fetch
/// it" signal. Fired when the driver taps (or receives in the foreground) a
/// DRIVER_ACCOUNT_STATUS_CHANGED notification — the one the backend sends
/// when an admin approves, suspends or reactivates the account
/// (backend/src/routes/drivers.routes.ts). The notification is only ever a
/// prompt to refresh: whoever listens (DriverShell) still reads the actual
/// status from GET /drivers/me, so the database stays the single source of
/// truth and a lost or duplicated notification can never invent a state.
class DriverProfileEvents {
  DriverProfileEvents._();

  static const accountStatusChangedType = 'DRIVER_ACCOUNT_STATUS_CHANGED';

  static final _RefreshNotifier _notifier = _RefreshNotifier();

  static void addListener(VoidCallback listener) =>
      _notifier.addListener(listener);
  static void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);

  /// Ask the shell to re-fetch the driver record from the backend.
  static void requestRefresh() => _notifier.fire();

  /// True for the notification type that means the record's status changed.
  static bool isAccountStatusChange(String? type) =>
      type == accountStatusChangedType;
}

class _RefreshNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}
