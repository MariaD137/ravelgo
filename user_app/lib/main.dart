import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/SplashScreen/SplashScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "RavelGo",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: SplashScreen(),
    );
  }
}
