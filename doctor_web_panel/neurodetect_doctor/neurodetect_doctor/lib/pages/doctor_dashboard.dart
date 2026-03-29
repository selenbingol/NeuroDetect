import 'package:flutter/material.dart';
import '../models/doctor_user_model.dart';
import '../models/patient_summary_model.dart';
import '../services/api_service.dart';
import '../widgets/patient_table.dart';
import '../widgets/stat_card.dart';
import 'patient_detail_page.dart';

class DoctorDashboardPage extends StatefulWidget {
  final DoctorUserModel doctor;

  const DoctorDashboardPage({super.key, required this.doctor});

  @override
  State<DoctorDashboardPage> createState() => _DoctorDashboardPageState();
}

class _DoctorDashboardPageState extends State<DoctorDashboardPage> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String _errorMessage = "";
  List<PatientSummaryModel> _patients = [];

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    final patients = await _apiService.getPatients();

    if (!mounted) return;

    setState(() {
      _patients = patients;
      _isLoading = false;
      if (patients.isEmpty) {
        _errorMessage = "No patient records found.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalPatients = _patients.length;
    final totalSessions = _patients.fold<int>(
  0,
  (sum, p) => sum + p.sessionDates.length,
);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          "NeuroDetect Doctor Dashboard",
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text(
                "Dr. ${widget.doctor.username}",
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Overview",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Monitor patient activity and review recent assessment records.",
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      StatCard(
                        title: "Total Patients",
                        value: totalPatients.toString(),
                        icon: Icons.people_alt_outlined,
                      ),
                      const SizedBox(width: 16),
                      StatCard(
                        title: "Total Sessions",
                        value: totalSessions.toString(),
                        icon: Icons.analytics_outlined,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Patient Records",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadPatients,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Refresh"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_errorMessage.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                        ),
                      ),
                    ),

                  Expanded(
                    child: PatientTable(
                      patients: _patients,
                      onPatientTap: (patient) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PatientDetailPage(patient: patient),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}