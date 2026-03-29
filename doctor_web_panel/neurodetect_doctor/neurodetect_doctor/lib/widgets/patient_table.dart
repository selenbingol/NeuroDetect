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

  String formatSessionDate(String date) {
    if (date.isEmpty) return "-";

    if (date.contains("T")) {
      return date.split("T").first;
    }

    if (date.contains(" ")) {
      return date.split(" ").first;
    }

    return date;
  }

  List<DataRow> buildRows() {
    final List<DataRow> rows = [];

    for (final patient in patients) {
      if (patient.sessionDates.isEmpty) {
        rows.add(
          DataRow(
            cells: [
              DataCell(
                InkWell(
                  onTap: () => onPatientTap(patient),
                  child: Text(
                    patient.firstName,
                    style: const TextStyle(
                      color: Color(0xFF1E5F92),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              DataCell(Text(patient.lastName)),
              DataCell(Text(patient.dob ?? "-")),
              const DataCell(Text("-")),
            ],
          ),
        );
      } else {
        for (final sessionDate in patient.sessionDates) {
          rows.add(
            DataRow(
              cells: [
                DataCell(
                  InkWell(
                    onTap: () => onPatientTap(patient),
                    child: Text(
                      patient.firstName,
                      style: const TextStyle(
                        color: Color(0xFF1E5F92),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                DataCell(Text(patient.lastName)),
                DataCell(Text(patient.dob ?? "-")),
                DataCell(Text(formatSessionDate(sessionDate))),
              ],
            ),
          );
        }
      }
    }

    return rows;
  }

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
              DataColumn(label: Text("First Name")),
              DataColumn(label: Text("Last Name")),
              DataColumn(label: Text("Date of Birth")),
              DataColumn(label: Text("Session Date")),
            ],
            rows: buildRows(),
          ),
        ),
      ),
    );
  }
}