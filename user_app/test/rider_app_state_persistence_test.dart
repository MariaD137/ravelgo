import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RiderAppState used to be in-memory only — every saved address, the
/// chosen language, and every notification toggle silently reverted to its
/// default the moment the app restarted, even though each screen's own Save
/// action reported success. This proves values actually survive a fresh
/// `load()` the way a real app restart would exercise it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saved address, language, communication prefs and surge toggle all survive a reload', () async {
    await RiderAppState.instance.load();

    RiderAppState.instance.saveAddress('Home', 'Ikeja City Mall, Alausa, Ikeja');
    RiderAppState.instance.setLanguage('French');
    RiderAppState.instance.saveCommunicationPreferences('Promotions', {'E-mail': true, 'SMS': false});
    RiderAppState.instance.setSurgeNotificationsEnabled(false);

    // Let the fire-and-forget SharedPreferences writes actually land before
    // simulating the restart.
    await Future<void>.delayed(Duration.zero);

    // Simulate an app restart: a brand new instance backed by the same
    // on-device store (setMockInitialValues persists across
    // SharedPreferences.getInstance() calls within one test).
    final restarted = _FreshRiderAppState();
    await restarted.load();

    expect(restarted.savedAddresses['Home'], 'Ikeja City Mall, Alausa, Ikeja');
    expect(restarted.language, 'French');
    expect(restarted.communicationPreferences['Promotions'], {'E-mail': true, 'SMS': false});
    expect(restarted.surgeNotificationsEnabled, false);
  });

  test('a fresh install with nothing saved yet keeps the documented defaults', () async {
    final fresh = _FreshRiderAppState();
    await fresh.load();

    expect(fresh.savedAddresses, isEmpty);
    expect(fresh.language, 'English');
    expect(fresh.surgeNotificationsEnabled, true);
  });
}

/// RiderAppState is a singleton by design (every screen reads the same
/// `.instance`), so this test needs its own instance to prove a genuine
/// disk round-trip rather than just re-reading the same in-memory object
/// under test. Constructs one exactly like the real singleton, without
/// touching the private constructor.
class _FreshRiderAppState extends RiderAppState {
  _FreshRiderAppState() : super.forTest();
}
