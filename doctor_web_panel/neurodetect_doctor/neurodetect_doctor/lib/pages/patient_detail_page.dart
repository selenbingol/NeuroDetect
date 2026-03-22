import 'package:flutter/material.dart';
import '../models/patient_summary_model.dart';

class PatientDetailPage extends StatelessWidget {
  final PatientSummaryModel patient;

  const PatientDetailPage({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Patient Detail - ${patient.username}"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "Detailed reports for ${patient.username} will be shown here.",
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}