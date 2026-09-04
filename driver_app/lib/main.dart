import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // Build the persistent-storage-backed Cognito pool before the first frame so
  // a stored session can be restored on startup (survives browser refresh).
  await AuthService.init();
  runApp(const RavelGoDriverApp());
}

class RavelGoDriverApp extends StatelessWidget {
  const RavelGoDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "RavelGo Driver",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
      // Phone-shaped app viewed in an ordinary wide desktop browser window
      // still needs to look like a phone screen, not stretch edge to edge.
      builder: (context, child) {
        return Container(
          color: AppColors.background,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
