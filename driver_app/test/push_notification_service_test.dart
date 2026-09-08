import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/services/push_notification_service.dart';

void main() {
  // Deliberately never calls dotenv.load() — replicates a real risk this
  // service must survive: reading its .env-backed getters before dotenv is
  // initialized must never throw (flutter_dotenv's `.env` getter throws
  // NotInitializedError in that case), and every public method must stay a
  // safe no-op rather than attempting any real AWS/Amplify call.
  test('is not configured, and every public method no-ops safely, before dotenv has ever loaded', () async {
    expect(PushNotificationService.isConfigured, isFalse);
    await PushNotificationService.configureAndRegister();
    await PushNotificationService.unregister();
    // Reaching here without a thrown exception is the assertion.
  });
}
