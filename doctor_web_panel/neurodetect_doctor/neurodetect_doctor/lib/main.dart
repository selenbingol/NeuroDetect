import 'package:flutter/material.dart';
import 'pages/doctor_login_page.dart';

void main() {
  runApp(const NeuroDetectDoctorApp());
}

class NeuroDetectDoctorApp extends StatelessWidget {
  const NeuroDetectDoctorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NeuroDetect Doctor Panel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const DoctorLoginPage(),
    );
  }
}