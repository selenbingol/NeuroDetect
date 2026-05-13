import 'package:flutter/material.dart';
import '../models/doctor_user_model.dart';
import '../models/patient_summary_model.dart';
import '../models/session_report_model.dart';
import '../services/api_service.dart';
import '../widgets/patient_table.dart';
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

  int _totalReactionSessions = 0;
  int _totalDecisionSessions = 0;
  int _totalTargetMovementSessions = 0;
  int _totalVisualMemorySessions = 0;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
      _totalReactionSessions = 0;
      _totalDecisionSessions = 0;
      _totalTargetMovementSessions = 0;
      _totalVisualMemorySessions = 0;
    });

    final patients = await _apiService.getPatients();

    int reactionCount = 0;
    int decisionCount = 0;
    int targetMovementCount = 0;
    int visualMemoryCount = 0;

    if (patients.isNotEmpty) {
      final reports = await Future.wait<PatientReportModel?>(
        patients.map((p) => _apiService.getPatientReport(p.userId)),
      );

      for (final report in reports) {
        if (report == null) continue;

        for (final session in report.sessions) {
          if (session.sessionType == "reaction") {
            reactionCount++;
          } else if (session.sessionType == "decision") {
            decisionCount++;
          } else if (session.sessionType == "target_movement") {
            targetMovementCount++;
          } else if (session.sessionType == "visual_memory") {
            visualMemoryCount++;
          }
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _patients = patients;
      _totalReactionSessions = reactionCount;
      _totalDecisionSessions = decisionCount;
      _totalTargetMovementSessions = targetMovementCount;
      _totalVisualMemorySessions = visualMemoryCount;
      _isLoading = false;

      if (patients.isEmpty) {
        _errorMessage = "No patient records found.";
      }
    });
  }

  String get _doctorDisplayName {
    final username = widget.doctor.username.trim();
    if (username.isEmpty) return "Doctor";
    return username;
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
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingView()
            : RefreshIndicator(
                onRefresh: _loadPatients,
                color: const Color(0xFF1E6BA8),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeHeader(),
                      const SizedBox(height: 24),
                      _buildOverviewSection(
                        totalPatients: totalPatients,
                        totalSessions: totalSessions,
                      ),
                      const SizedBox(height: 28),
                      _buildPatientRecordsSection(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Container(
        width: 310,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF1E6BA8),
            ),
            SizedBox(height: 18),
            Text(
              "Loading clinical dashboard...",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1C2430),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Please wait while patient activity and assessment records are prepared.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F4C81),
            Color(0xFF1E6BA8),
            Color(0xFF38BDF8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220F4C81),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.28),
              ),
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome, Dr. $_doctorDisplayName",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withOpacity(0.28),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                SizedBox(width: 7),
                Text(
                  "Doctor Panel",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSection({
    required int totalPatients,
    required int totalSessions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: "Clinical Overview",
          subtitle: "Summary of patient activity and task-based assessment records.",
          trailing: _buildRefreshButton(),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            int columns = 1;
            if (width >= 1200) {
              columns = 3;
            } else if (width >= 760) {
              columns = 2;
            }

            const spacing = 14.0;
            final cardWidth = (width - ((columns - 1) * spacing)) / columns;

            final cards = [
              _DashboardStatData(
                title: "Total Patients",
                value: totalPatients.toString(),
                icon: Icons.people_alt_rounded,
                accentColor: const Color(0xFF0369A1),
                backgroundColor: const Color(0xFFE0F2FE),
              ),
              _DashboardStatData(
                title: "Total Sessions",
                value: totalSessions.toString(),
                icon: Icons.analytics_rounded,
                accentColor: const Color(0xFF4338CA),
                backgroundColor: const Color(0xFFE0E7FF),
              ),
              _DashboardStatData(
                title: "Reaction Sessions",
                value: _totalReactionSessions.toString(),
                icon: Icons.flash_on_rounded,
                accentColor: const Color(0xFFB45309),
                backgroundColor: const Color(0xFFFEF3C7),
              ),
              _DashboardStatData(
                title: "Decision Sessions",
                value: _totalDecisionSessions.toString(),
                icon: Icons.psychology_alt_rounded,
                accentColor: const Color(0xFF7E22CE),
                backgroundColor: const Color(0xFFF3E8FF),
              ),
              _DashboardStatData(
                title: "Target Movement",
                value: _totalTargetMovementSessions.toString(),
                icon: Icons.track_changes_rounded,
                accentColor: const Color(0xFF4D7C0F),
                backgroundColor: const Color(0xFFECFCCB),
              ),
              _DashboardStatData(
                title: "Visual Memory",
                value: _totalVisualMemorySessions.toString(),
                icon: Icons.grid_view_rounded,
                accentColor: const Color(0xFF0F766E),
                backgroundColor: const Color(0xFFCCFBF1),
              ),
            ];

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards
                  .map(
                    (card) => SizedBox(
                      width: cardWidth,
                      child: _buildDashboardStatCard(card),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDashboardStatCard(_DashboardStatData data) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: data.backgroundColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              data.icon,
              color: data.accentColor,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.value,
                  style: const TextStyle(
                    color: Color(0xFF1C2430),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientRecordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: "Patient Records",
          subtitle: "Select a patient to review session history, task metrics, and clinical summaries.",
          trailing: Text(
            "${_patients.length} patient${_patients.length == 1 ? "" : "s"}",
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_errorMessage.isNotEmpty) _buildErrorBox(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
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
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1C2430),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 16),
          trailing,
        ],
      ],
    );
  }

  Widget _buildRefreshButton() {
    return OutlinedButton.icon(
      onPressed: _loadPatients,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text("Refresh"),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1E6BA8),
        side: const BorderSide(color: Color(0xFFBAE6FD)),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildErrorBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF9A3412),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatData {
  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;

  const _DashboardStatData({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
  });
}