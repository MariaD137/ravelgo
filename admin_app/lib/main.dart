import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // Build the persistent-storage-backed Cognito pool before the first frame so
  // a stored session can be restored on startup (survives browser refresh).
  await AuthService.init();
  runApp(const RavelGoAdminApp());
}

class RavelGoAdminApp extends StatelessWidget {
  const RavelGoAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "RavelGo Admin",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Sign-in screen removed at the user's explicit, repeated instruction
      // while the admin app is under active development. Backend routes are
      // untouched and still enforce requireAuth/requireRole("Admin") on every
      // request, so screens that call the API will still show real
      // 401/403s here since there is no Cognito session to attach.
      home: const AdminShell(),
    );
  }
}
