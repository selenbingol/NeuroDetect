import 'package:flutter/material.dart';
import '../models/patient_summary_model.dart';

class PatientTable extends StatelessWidget {
  final List<PatientSummaryModel> patients;
  final void Function(PatientSummaryModel patient) onPatientTap;

  const PatientTable({
    super.key,
    required this.patients,
    required this.onPatientTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            columns: const [
              DataColumn(label: Text("Patient")),
              DataColumn(label: Text("Email")),
              DataColumn(label: Text("Sessions")),
              DataColumn(label: Text("Latest Score")),
              DataColumn(label: Text("Latest Accuracy")),
              DataColumn(label: Text("Last Session")),
            ],
            rows: patients.map((patient) {
              return DataRow(
                cells: [
                  DataCell(
                    InkWell(
                      onTap: () => onPatientTap(patient),
                      child: Text(
                        patient.username,
                        style: const TextStyle(
                          color: Color(0xFF1E5F92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(patient.email)),
                  DataCell(Text(patient.totalSessions.toString())),
                  DataCell(Text(patient.latestScore?.toString() ?? "-")),
                  DataCell(
                    Text(
                      patient.latestAccuracy == null
                          ? "-"
                          : "${patient.latestAccuracy!.toStringAsFixed(1)}%",
                    ),
                  ),
                  DataCell(Text(patient.lastSessionAt ?? "-")),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}