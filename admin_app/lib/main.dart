import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // The app's one composition root: the only place that decides which
  // AuthProvider is in effect (via createDefaultAuthProvider — see its own
  // doc comment). Passed down to the screen that actually needs it rather
  // than each constructing its own default.
  final authProvider = createDefaultAuthProvider();

  runApp(RavelGoAdminApp(authProvider: authProvider));
}

class RavelGoAdminApp extends StatelessWidget {
  const RavelGoAdminApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "RavelGo Admin",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, primary: AppColors.primary),
        fontFamily: "Roboto",
      ),
      home: SplashScreen(authProvider: authProvider),
    );
  }
}
