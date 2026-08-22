import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/api/auth_provider.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // The app's one composition root: the only place that decides which
  // AuthProvider is in effect (via createDefaultAuthProvider — see its own
  // doc comment) and wires it through to everything that needs it. Nothing
  // downstream (ApiClient's default, DriverSession, any screen) constructs
  // an AuthProvider on its own.
  final authProvider = createDefaultAuthProvider();
  final apiClient = ApiClient(
    authProvider: authProvider,
    // A 401 means the token this session was using is no longer valid
    // server-side (expired, revoked, or the account got suspended) — drop
    // back to signed-out rather than continuing to show screens that need
    // a session that no longer exists.
    onUnauthorized: () => DriverSession.instance.signOut(),
  );
  DriverSession.initialize(authProvider: authProvider, apiClient: apiClient);

  runApp(const RavelGoDriverApp());
}

class RavelGoDriverApp extends StatelessWidget {
  const RavelGoDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "RavelGo Driver",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
        ),
        fontFamily: "Roboto",
      ),
      home: const SplashScreen(),
    );
  }
}
