import 'dart:io';
import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker_linux/file_picker_linux.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register platform-specific file picker implementations
  if (Platform.isAndroid) {
    try {
      FilePickerAndroid.registerWith();
    } catch (_) {}
  } else if (Platform.isLinux) {
    try {
      FilePickerLinux.registerWith();
    } catch (_) {}
  }

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
