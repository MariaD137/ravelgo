import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/SplashScreen/SplashScreen.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F6F6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD500),
          primary: const Color(0xFFFFD500),
        ),
        fontFamily: "Roboto",
      ),
      home: SplashScreen(),
    );
  }
}
