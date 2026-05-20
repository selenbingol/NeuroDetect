import 'package:flutter/material.dart';
import '../models/patient_summary_model.dart';

class PatientTable extends StatelessWidget {
  final List<PatientSummaryModel> patients;
  final Function(PatientSummaryModel patient) onPatientTap;

  const PatientTable({
    super.key,
    required this.patients,
    required this.onPatientTap,
  });

  String _displayValue(String? value) {
    if (value == null || value.trim().isEmpty) return "-";
    return value;
  }

  String _latestSessionDate(PatientSummaryModel patient) {
    if (patient.sessionDates.isEmpty) return "-";

    final rawDate = patient.sessionDates.first;
    if (rawDate.length >= 10) {
      return rawDate.substring(0, 10);
    }

    return rawDate;
  }

  String _formatGender(String gender) {
    final value = gender.trim().toLowerCase();

    if (value.isEmpty) return "-";
    if (value == "male" || value == "m") return "Male";
    if (value == "female" || value == "f") return "Female";

    return gender;
  }

  @override
  Widget build(BuildContext context) {
    if (patients.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.folder_open_rounded,
              color: Color(0xFF94A3B8),
              size: 42,
            ),
            SizedBox(height: 12),
            Text(
              "No patient records found",
              style: TextStyle(
                color: Color(0xFF1C2430),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 5),
            Text(
              "Registered patients will appear here after data is available.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 1120 ? 1120.0 : constraints.maxWidth;

        return Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeaderRow(),
                  ...patients.map((patient) => _buildPatientRow(patient)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Row(
        children: [
          _buildHeaderCell("Patient", flex: 28),
          _buildHeaderCell("Gender", flex: 12),
          _buildHeaderCell("Phone", flex: 15),
          _buildHeaderCell("Date of Birth", flex: 13),
          _buildHeaderCell("Latest Session", flex: 14),
          _buildHeaderCell("Sessions", flex: 12),
          const SizedBox(width: 52),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildPatientRow(PatientSummaryModel patient) {
    final firstName = _displayValue(patient.firstName).trim();
    final lastName = _displayValue(patient.lastName).trim();
    final fullName = (firstName.toLowerCase() == lastName.toLowerCase() && firstName != "-")
        ? firstName
        : "$firstName $lastName".trim();

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => onPatientTap(patient),
        hoverColor: const Color(0xFFF8FAFC),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 28,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF0369A1),
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName == "- -" ? "Unknown Patient" : fullName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1C2430),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Patient ID: ${patient.userId}",
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSoftChip(
                    text: _formatGender(patient.gender),
                    icon: Icons.wc_rounded,
                  ),
                ),
              ),
              _buildTextCell(_displayValue(patient.phone), flex: 15),
              _buildTextCell(_displayValue(patient.dob), flex: 13),
              _buildTextCell(_latestSessionDate(patient), flex: 14),
              Expanded(
                flex: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildSessionBadge(patient.sessionDates.length),
                ),
              ),
              SizedBox(
                width: 52,
                child: IconButton(
                  onPressed: () => onPatientTap(patient),
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF64748B),
                    size: 26,
                  ),
                  tooltip: "Open patient record",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSoftChip({
    required String text,
    required IconData icon,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: const Color(0xFF64748B),
            size: 15,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionBadge(int count) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Text(
        "$count session${count == 1 ? "" : "s"}",
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF0369A1),
          fontSize: 12.8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}