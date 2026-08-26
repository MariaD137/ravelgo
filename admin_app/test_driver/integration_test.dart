// Standard Flutter driver for integration_test screenshots — receives
// each binding.takeScreenshot(name) call and writes it to disk as a real
// PNG under screenshots/. See https://docs.flutter.dev/cookbook/testing/integration/screenshots.
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (String screenshotName, List<int> screenshotBytes, [Map<String, Object?>? args]) async {
        final file = await File('screenshots/$screenshotName.png').create(recursive: true);
        await file.writeAsBytes(screenshotBytes);
        return true;
      },
    );
