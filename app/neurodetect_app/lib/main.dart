import 'package:flutter/material.dart';
import 'pages/login_page.dart';

void main() {
  runApp(const NeuroDetectApp());
}

class NeuroDetectApp extends StatelessWidget {
  const NeuroDetectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NeuroDetect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LoginPage()
    );
  }
}