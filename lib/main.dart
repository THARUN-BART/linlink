import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request camera permission on startup before accessing camera services
  await Permission.camera.request();

  runApp(const LinLinkApp());
}

class LinLinkApp extends StatelessWidget {
  const LinLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.cyan,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
