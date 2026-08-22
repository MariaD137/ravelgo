import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/views/SplashScreen/SplashScreen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // The app's one composition root: the only place that decides which
  // AuthProvider is in effect (via createDefaultAuthProvider — see its own
  // doc comment). Passed down to the screen that actually needs it rather
  // than each constructing its own default.
  final authProvider = createDefaultAuthProvider();

  runApp(MyApp(authProvider: authProvider));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(authProvider: authProvider),
    );
  }
}
