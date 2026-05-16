import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/patient_summary_model.dart';
import '../models/session_report_model.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';
import '../models/fusion_assessment_model.dart';
import '../widgets/fusion_risk_card.dart';
import '../widgets/risk_trend_chart.dart';

class PatientDetailPage extends StatefulWidget {
  final PatientSummaryModel patient;

  const PatientDetailPage({super.key, required this.patient});

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  final ApiService _apiService = ApiService();

  final GlobalKey _accuracyChartKey = GlobalKey();
  final GlobalKey _reactionChartKey = GlobalKey();
  final GlobalKey _tremorChartKey = GlobalKey();

  bool _isLoading = true;
  String _errorMessage = "";
  PatientReportModel? _report;

  int? _selectedSessionId;

  bool _isFusionLoading = false;
  String? _fusionError;
  FusionAssessmentModel? _fusionAssessment;
  List<RiskTrendPoint> _riskTrendPoints = [];
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

Future<void> _loadReport() async {
  setState(() {
    _isLoading = true;
    _errorMessage = "";
    _fusionError = null;
    _fusionAssessment = null;
  });

  try {
    final report = await _apiService.getPatientReport(widget.patient.userId);

    List<RiskTrendPoint> trendPoints = [];

    if (report != null) {
      try {
        trendPoints = await _apiService.getRiskTrend(widget.patient.userId);
      } catch (e) {
        debugPrint("Risk trend could not be loaded: $e");
      }
    }

    if (!mounted) return;

    setState(() {
      _report = report;
      _riskTrendPoints = trendPoints;
      _isLoading = false;

      if (report == null) {
        _errorMessage = "Failed to load patient report.";
      }
    });

    if (report != null && report.sessions.isNotEmpty) {
      await _loadBestFusionAssessment(report);
    }
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _errorMessage = "Failed to load patient report: $e";
    });
  }
}

  Future<void> _loadFusionAssessment(int sessionId) async {
    setState(() {
      _isFusionLoading = true;
      _fusionError = null;
    });

    try {
      final fusionResult = await _apiService.getFusionAssessment(sessionId);

      if (!mounted) return;

      setState(() {
        _fusionAssessment = fusionResult;
        _isFusionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _fusionAssessment = null;
        _isFusionLoading = false;
        _fusionError = "Failed to load fusion analysis: $e";
      });
    }
  }

  Future<void> _loadRiskTrend(int userId) async {
    try {
      final points = await _apiService.getRiskTrend(userId);

      if (!mounted) return;

      setState(() {
        _riskTrendPoints = points;
      });
    } catch (e) {
      debugPrint("Risk trend could not be loaded: $e");
    }
  }
  bool _hasDigitalRisk(FusionAssessmentModel fusion) {
  return fusion.cognitiveRiskScore > 0 ||
      fusion.motorRiskScore > 0 ||
      fusion.overallRiskScore > 0;
}

Future<void> _loadBestFusionAssessment(PatientReportModel report) async {
  if (report.sessions.isEmpty) return;

  setState(() {
    _isFusionLoading = true;
    _fusionError = null;
  });

  FusionAssessmentModel? fallbackFusion;
  int? fallbackSessionId;

  // Çok fazla API çağrısı yapmamak için son 30 session yeterli.
  final recentSessions = report.sessions.take(30).toList();

  for (final session in recentSessions) {
    try {
      final fusion = await _apiService.getFusionAssessment(session.sessionId);

      fallbackFusion ??= fusion;
      fallbackSessionId ??= session.sessionId;

      if (_hasDigitalRisk(fusion)) {
        if (!mounted) return;

        setState(() {
          _selectedSessionId = session.sessionId;
          _fusionAssessment = fusion;
          _isFusionLoading = false;
        });

        return;
      }
    } catch (e) {
      debugPrint("Fusion could not be loaded for session ${session.sessionId}: $e");
    }
  }

  if (!mounted) return;

  // Hiç cognitive/motor/overall risk üreten session yoksa,
  // en azından gelen ilk fusion sonucunu göster.
  setState(() {
    _selectedSessionId = fallbackSessionId ?? report.sessions.first.sessionId;
    _fusionAssessment = fallbackFusion;
    _isFusionLoading = false;

    if (fallbackFusion == null) {
      _fusionError = "Fusion analysis is not available for recent sessions.";
    }
  });
}

  Future<Uint8List?> _captureWidget(
  GlobalKey key, {
  double pixelRatio = 1.5,
}) async {
  try {
    await Future.delayed(const Duration(milliseconds: 50));

    final context = key.currentContext;
    if (context == null) return null;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData?.buffer.asUint8List();
  } catch (e) {
    debugPrint("Chart capture error: $e");
    return null;
  }
}
Future<void> _exportPdf() async {
  if (_report == null || _isExportingPdf) return;

  setState(() {
    _isExportingPdf = true;
  });

  try {
    final accuracyChartBytes = await _captureWidget(_accuracyChartKey);
    final reactionChartBytes = await _captureWidget(_reactionChartKey);
    final tremorChartBytes = await _captureWidget(_tremorChartKey);

    await PdfService.generatePatientReport(
      _report!,
      accuracyChartBytes: accuracyChartBytes,
      reactionChartBytes: reactionChartBytes,
      tremorChartBytes: tremorChartBytes,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("PDF report was generated successfully."),
        backgroundColor: Color(0xFF15803D),
      ),
    );
  } catch (e) {
    debugPrint("PDF export error: $e");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("PDF export failed: $e"),
        backgroundColor: const Color(0xFFB91C1C),
      ),
    );
  } finally {
    if (!mounted) return;

    setState(() {
      _isExportingPdf = false;
    });
  }
}

  String formatDate(String? raw) {
    if (raw == null) return "-";

    try {
      final dt = DateTime.parse(raw);
      final day = dt.day.toString().padLeft(2, "0");
      final month = dt.month.toString().padLeft(2, "0");
      final hour = dt.hour.toString().padLeft(2, "0");
      final minute = dt.minute.toString().padLeft(2, "0");

      return "$day/$month/${dt.year} $hour:$minute";
    } catch (_) {
      return "-";
    }
  }

  String formatSessionType(String? sessionType) {
    switch (sessionType) {
      case "reaction":
        return "Reaction Task";
      case "decision":
        return "Decision Task";
      case "target_movement":
        return "Target Movement Task";
      case "visual_memory":
        return "Visual Memory Task";
      default:
        return "-";
    }
  }

  Color _riskColor(String? riskLevel) {
    switch ((riskLevel ?? "").toLowerCase()) {
      case "high":
        return const Color(0xFFB91C1C);
      case "moderate":
        return const Color(0xFFD97706);
      case "low":
        return const Color(0xFF15803D);
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _scoreColor(double score) {
    if (score >= 70) return const Color(0xFFB91C1C);
    if (score >= 40) return const Color(0xFFD97706);
    return const Color(0xFF15803D);
  }

  SessionReportItem? get _latestReactionSession {
    final sessions = _report?.sessions ?? [];
    for (final s in sessions) {
      if (s.sessionType == "reaction") return s;
    }
    return null;
  }

  SessionReportItem? get _latestDecisionSession {
    final sessions = _report?.sessions ?? [];
    for (final s in sessions) {
      if (s.sessionType == "decision") return s;
    }
    return null;
  }

  SessionReportItem? get _latestTargetMovementSession {
    final sessions = _report?.sessions ?? [];
    for (final s in sessions) {
      if (s.sessionType == "target_movement") return s;
    }
    return null;
  }

  SessionReportItem? get _latestVisualMemorySession {
    final sessions = _report?.sessions ?? [];
    for (final s in sessions) {
      if (s.sessionType == "visual_memory") return s;
    }
    return null;
  }
  bool _isTaskSession(SessionReportItem session) {
  return session.sessionType == "reaction" ||
      session.sessionType == "decision" ||
      session.sessionType == "target_movement" ||
      session.sessionType == "visual_memory";
}

int get _taskSessionCount {
  final sessions = _report?.sessions ?? [];
  return sessions.where(_isTaskSession).length;
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingView()
            : _errorMessage.isNotEmpty
                ? _buildErrorState(_errorMessage)
                : _report == null
                    ? _buildErrorState("No report available.")
                    : RefreshIndicator(
                        onRefresh: _loadReport,
                        color: const Color(0xFF1E6BA8),
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTopBar(),
                              const SizedBox(height: 18),
                              _buildPatientHeader(),
                              const SizedBox(height: 22),
                              _buildRiskSection(),
                              const SizedBox(height: 22),
                              _buildFusionAnalysisSection(),
                              const SizedBox(height: 22),
                              _buildSummaryCards(),
                              const SizedBox(height: 22),
                              _buildDetailedMetricsSection(),
                              const SizedBox(height: 22),
                              _buildChartsSection(),
                              const SizedBox(height: 22),
                              _buildSessionTable(),
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
        width: 320,
        padding: const EdgeInsets.all(26),
        decoration: _panelDecoration(),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF1E6BA8)),
            SizedBox(height: 18),
            Text(
              "Loading patient profile...",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1C2430),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Clinical metrics, fusion results, and session history are being prepared.",
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

  Widget _buildErrorState(String message) {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFF9A3412),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF9A3412),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text("Back to Dashboard"),
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
        ),
        const Spacer(),
        OutlinedButton.icon(
  onPressed: _isExportingPdf ? null : _exportPdf,
  icon: _isExportingPdf
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF1E6BA8),
          ),
        )
      : const Icon(Icons.picture_as_pdf_rounded, size: 18),
  label: Text(_isExportingPdf ? "Preparing PDF..." : "Export PDF"),
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
        ),
      ],
    );
  }

  Widget _buildPatientHeader() {
    final p = _report!.patient;
    final s = _report!.summary;
    final displayRiskLevel =
    (_isFusionLoading && _fusionAssessment == null)
        ? "Loading..."
        : (_fusionAssessment?.riskLevel ?? s.latestRiskLevel);
    final riskColor = _riskColor(displayRiskLevel);

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
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.28)),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _headerChip(Icons.badge_rounded, "Patient ID: ${p.userId}"),
                    _headerChip(Icons.email_rounded, p.email),
                    _headerChip(
  Icons.event_note_rounded,
  "$_taskSessionCount task sessions",
),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.health_and_safety_rounded,
                  color: riskColor == const Color(0xFF64748B)
                      ? Colors.white
                      : Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Latest Risk",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      displayRiskLevel ?? "No data",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

Widget _buildRiskSection() {
  if (_isFusionLoading && _fusionAssessment == null) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: const Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF1E6BA8),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              "Loading AI risk assessment...",
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
  final s = _report!.summary;

  final fusion = _fusionAssessment;

  final riskLevel = fusion?.riskLevel ?? s.latestRiskLevel ?? "No data";
  final riskColor = _riskColor(riskLevel);

  final double? riskScore =
      fusion?.finalFusionScore ?? s.latestRiskScore?.toDouble();

  return Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: riskColor.withOpacity(0.25)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10000000),
          blurRadius: 22,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: riskColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.monitor_heart_rounded,
            color: riskColor,
            size: 30,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "AI Risk Assessment",
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                riskLevel,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: riskColor,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              const Text(
                "Risk Score",
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                riskScore == null ? "-" : riskScore.toStringAsFixed(1),
                style: TextStyle(
                  color: riskColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildFusionAnalysisSection() {
  if (_selectedSessionId == null) {
    return _infoPanel("No session selected for fusion analysis.");
  }

  if (_isFusionLoading && _fusionAssessment == null) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: _panelDecoration(),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFF1E6BA8)),
      ),
    );
  }

  if (_fusionError != null && _fusionAssessment == null) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _fusionError!,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  if (_fusionAssessment == null) {
    return _infoPanel("Fusion analysis is not available for this session.");
  }

  final fusion = _fusionAssessment!;

  return Container(
    padding: const EdgeInsets.all(24),
    decoration: _panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isFusionLoading) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 4,
              color: Color(0xFF1E6BA8),
              backgroundColor: Color(0xFFE0F2FE),
            ),
          ),
          const SizedBox(height: 14),
        ],

        _sectionHeader(
          icon: Icons.auto_graph_rounded,
          title: "Fusion-Based Clinical Analysis",
          subtitle:
              "Three-layer multimodal fusion result for the selected assessment session.",
          trailing: _softBadge("Session ID: $_selectedSessionId"),
        ),
        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(
              child: FusionRiskCard(
                title: "Cognitive Risk",
                score: fusion.cognitiveRiskScore,
                subtitle: "Memory and decision-related indicators",
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FusionRiskCard(
                title: "Motor Risk",
                score: fusion.motorRiskScore,
                subtitle: "Reaction and movement-related indicators",
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
  child: FusionRiskCard(
    title: "Digital Risk Score",
    score: fusion.overallRiskScore,
    subtitle: "Average of cognitive and motor indicators",
  ),
),
          ],
        ),

        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(
              child: _buildClinicalProbCard(
                title: "Alzheimer Probability",
                probability: fusion.alzheimerProbability,
                riskLevel: fusion.alzheimerRiskLevel,
                icon: Icons.psychology_rounded,
                color: const Color(0xFF7E22CE),
                mlUsed: fusion.alzheimerMlUsed,
                mciProb: fusion.alzheimerMciProb,
                adProb: fusion.alzheimerAdProb,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildClinicalProbCard(
                title: "ALS Probability",
                probability: fusion.alsProbability,
                riskLevel: fusion.alsRiskLevel,
                icon: Icons.accessibility_new_rounded,
                color: const Color(0xFF0369A1),
                mlUsed: fusion.alsMlUsed,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FusionRiskCard(
                title: "Final Fusion Score",
                score: fusion.finalFusionScore,
                subtitle: "Final 3-layer decision-support output",
              ),
            ),
          ],
        ),

        if (fusion.dominantFactors.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildDominantFactors(fusion),
        ],

        const SizedBox(height: 20),
        _buildXAIComment(fusion),

        const SizedBox(height: 24),

        if (_riskTrendPoints.isNotEmpty)
          RiskTrendChart(points: _riskTrendPoints)
        else
          _infoPanel("Risk trend data is not available yet."),
      ],
    ),
  );
}

  Widget _buildDominantFactors(FusionAssessmentModel fusion) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            "Dominant Factors:",
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF334155),
            ),
          ),
          ...fusion.dominantFactors.map((f) {
            final isHigh = f["impact"] == "high";
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color:
                    isHigh ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isHigh
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFFDE68A),
                ),
              ),
              child: Text(
                f["label"] ?? "",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: isHigh
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF92400E),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildXAIComment(FusionAssessmentModel fusion) {
    final comment = fusion.explanation.isNotEmpty
        ? fusion.explanation
        : _generateFallbackXAIComment(fusion);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.psychology_alt_outlined,
                color: Color(0xFF1E6BA8),
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                "Explainable AI Comment",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1C2430),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Color(0xFF334155),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _generateFallbackXAIComment(FusionAssessmentModel fusion) {
    final comments = <String>[];

    if (fusion.motorRiskScore >= 70) {
      comments.add(
        "Motor risk appears elevated. Reaction time deviation, movement instability, tremor index, or task performance irregularity may have contributed to this score.",
      );
    }

    if (fusion.cognitiveRiskScore >= 70) {
      comments.add(
        "Cognitive risk appears elevated. Decision accuracy, omission errors, memory task performance, or response consistency may have influenced this result.",
      );
    }

    if (fusion.overallRiskScore < 40) {
      comments.add(
        "The overall fusion score is within a lower-risk range for this session.",
      );
    }

    if (comments.isEmpty) {
      comments.add(
        "The fusion engine combined cognitive and motor indicators for this session. No single dominant risk factor was detected.",
      );
    }

    return comments.join(" ");
  }

  Widget _buildClinicalProbCard({
    required String title,
    required double probability,
    required String riskLevel,
    required IconData icon,
    required Color color,
    bool mlUsed = false,
    double? mciProb,
    double? adProb,
  }) {
    final normalized = probability.clamp(0.0, 1.0).toDouble();
    final pct = (normalized * 100).clamp(0, 100);
    final levelLabel = riskLevel == "high"
        ? "HIGH"
        : riskLevel == "moderate"
            ? "MODERATE"
            : "LOW";
    final levelColor = riskLevel == "high"
        ? const Color(0xFFB91C1C)
        : riskLevel == "moderate"
            ? const Color(0xFFD97706)
            : const Color(0xFF15803D);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: CircularProgressIndicator(
                  value: normalized,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                "%${pct.toStringAsFixed(0)}",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: levelColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: levelColor.withOpacity(0.20)),
                ),
                child: Text(
                  levelLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: levelColor,
                  ),
                ),
              ),
              if (mlUsed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.memory_rounded, size: 14, color: Color(0xFF1D4ED8)),
                      SizedBox(width: 4),
                      Text(
                        "ML Powered",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (mciProb != null && adProb != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Text(
                        "MCI Prob",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        "%${(mciProb * 100).toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: const Color(0xFFCBD5E1),
                  ),
                  Column(
                    children: [
                      const Text(
                        "AD Prob",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        "%${(adProb * 100).toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final s = _report!.summary;

    final cards = [
      _SummaryData("Task Sessions", _taskSessionCount.toString(), Icons.event_note_rounded),
      _SummaryData("Accuracy", "${s.avgAccuracy.toStringAsFixed(1)}%", Icons.check_circle_rounded),
      _SummaryData("Score", s.avgScore.toStringAsFixed(1), Icons.insights_rounded),
      _SummaryData("Reaction", "${s.avgReactionTime.toStringAsFixed(0)} ms", Icons.timer_rounded),
      _SummaryData("Misses", s.totalMissCount.toString(), Icons.error_outline_rounded),
      _SummaryData("Avg Motion", s.avgMotion.toStringAsFixed(2), Icons.directions_run_rounded),
      _SummaryData("Avg Gyro", s.avgGyro.toStringAsFixed(2), Icons.screen_rotation_rounded),
      _SummaryData("Avg Tremor", s.avgTremorIndex.toStringAsFixed(2), Icons.monitor_heart_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          icon: Icons.dashboard_rounded,
          title: "Assessment Summary",
          subtitle: "Aggregated patient performance indicators across recorded sessions.",
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            int columns = 1;
            if (width >= 1200) {
              columns = 4;
            } else if (width >= 760) {
              columns = 2;
            }

            const spacing = 14.0;
            final cardWidth = (width - ((columns - 1) * spacing)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards
                  .map(
                    (card) => SizedBox(
                      width: cardWidth,
                      child: _summaryCard(card),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _summaryCard(_SummaryData data) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              data.icon,
              color: const Color(0xFF1E6BA8),
              size: 24,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  data.value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1C2430),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedMetricsSection() {
  final reaction = _latestReactionSession;
  final decision = _latestDecisionSession;
  final targetMovement = _latestTargetMovementSession;
  final visualMemory = _latestVisualMemorySession;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader(
        icon: Icons.fact_check_rounded,
        title: "Task-Specific Metrics",
        subtitle:
            "Latest task results grouped by cognitive, motor, and visual-memory task types.",
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _buildReactionMetricsCard(reaction),
          _buildDecisionMetricsCard(decision),
          _buildVisualMemoryMetricsCard(visualMemory),
          _buildTargetMovementMetricsCard(targetMovement),
        ],
      ),
    ],
  );
}


  Widget _buildReactionMetricsCard(SessionReportItem? session) {
    return _taskMetricCard(
      sessionType: "reaction",
      title: "Latest Reaction Metrics",
      emptyText: "No reaction session found.",
      session: session,
      metrics: session == null
          ? []
          : [
              _MiniMetricData("Tap Count", "${session.tapCount ?? 0}"),
              _MiniMetricData("False Start", "${session.falseStartCount ?? 0}"),
              _MiniMetricData("Wrong Tap", "${session.wrongTapCount ?? 0}"),
              _MiniMetricData("Timeout", "${session.timeoutCount ?? 0}"),
              _MiniMetricData("Miss Count", "${session.missCount ?? 0}"),
              _MiniMetricData(
                "Reaction",
                session.reactionTimeMs == null ? "-" : "${session.reactionTimeMs} ms",
              ),
            ],
    );
  }

  Widget _buildDecisionMetricsCard(SessionReportItem? session) {
    return _taskMetricCard(
      sessionType: "decision",
      title: "Latest Decision Metrics",
      emptyText: "No decision session found.",
      session: session,
      metrics: session == null
          ? []
          : [
              _MiniMetricData("Correct Decisions", "${session.tapCount ?? 0}"),
              _MiniMetricData("False Start", "${session.falseStartCount ?? 0}"),
              _MiniMetricData("False Alarm", "${session.falseAlarmCount ?? 0}"),
              _MiniMetricData("Omission", "${session.omissionCount ?? 0}"),
              _MiniMetricData("Miss Count", "${session.missCount ?? 0}"),
              _MiniMetricData(
                "Reaction",
                session.reactionTimeMs == null ? "-" : "${session.reactionTimeMs} ms",
              ),
            ],
    );
  }

  Widget _buildTargetMovementMetricsCard(SessionReportItem? session) {
    return _taskMetricCard(
      sessionType: "target_movement",
      title: "Latest Sensor-Based Motor Metrics",
      emptyText: "No target movement session found.",
      session: session,
      width: 780,
      metrics: session == null
          ? []
          : [
              _MiniMetricData("Motor Success", "${session.successfulCutCount ?? 0}"),
              _MiniMetricData("Motor Miss", "${session.sliceMissCount ?? 0}"),
              _MiniMetricData("Near-Miss Events", "${session.nearMissCount ?? 0}"),
              _MiniMetricData(
                "Avg Motor Path",
                session.avgSliceLength == null
                    ? "-"
                    : session.avgSliceLength!.toStringAsFixed(1),
              ),
              _MiniMetricData(
                "Movement Coverage",
                session.avgCutCoverage == null
                    ? "-"
                    : session.avgCutCoverage!.toStringAsFixed(2),
              ),
              _MiniMetricData(
                "Avg Motion",
                session.avgMotion == null ? "-" : session.avgMotion!.toStringAsFixed(2),
              ),
              _MiniMetricData(
                "Avg Gyro",
                session.avgGyro == null ? "-" : session.avgGyro!.toStringAsFixed(2),
              ),
              _MiniMetricData(
                "Tremor Index",
                session.tremorIndex == null
                    ? "-"
                    : session.tremorIndex!.toStringAsFixed(2),
              ),
              _MiniMetricData(
                "Movement Variability",
                session.movementVariability == null
                    ? "-"
                    : session.movementVariability!.toStringAsFixed(3),
              ),
              _MiniMetricData("Path Corrections", "${session.pathCorrectionCount ?? 0}"),
              _MiniMetricData("Sensor Samples", "${session.sampleCount ?? 0}"),
            ],
    );
  }

  Widget _buildVisualMemoryMetricsCard(SessionReportItem? session) {
  return _taskMetricCard(
    sessionType: "visual_memory",
    title: "Latest Memory Metrics",
    emptyText: "No visual memory session found.",
    session: session,
    width: 380,
    metrics: session == null
        ? []
        : [
            _MiniMetricData("Score", "${session.score ?? "-"}"),
            _MiniMetricData(
              "Accuracy",
              session.accuracyRate == null
                  ? "-"
                  : "${session.accuracyRate!.toStringAsFixed(1)}%",
            ),
            _MiniMetricData("Correct Selection", "${session.tapCount ?? 0}"),
            _MiniMetricData("False Selection", "${session.wrongTapCount ?? 0}"),
            _MiniMetricData("Omission", "${session.omissionCount ?? 0}"),
            _MiniMetricData("False Start", "${session.falseStartCount ?? 0}"),
            _MiniMetricData(
              "Recall Time",
              session.reactionTimeMs == null
                  ? "-"
                  : "${session.reactionTimeMs} ms",
            ),
          ],
  );
}

  Widget _taskMetricCard({
    required String sessionType,
    required String title,
    required String emptyText,
    required SessionReportItem? session,
    required List<_MiniMetricData> metrics,
    double width = 380,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildSessionTypeBadge(sessionType),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1C2430),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (session == null)
            Text(
              emptyText,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: metrics
                  .map((metric) => _miniMetric(metric.title, metric.value))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _miniMetric(String title, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1C2430),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          icon: Icons.show_chart_rounded,
          title: "Performance Trends",
          subtitle: "Longitudinal changes across accuracy, reaction time, and tremor-related indicators.",
        ),
        const SizedBox(height: 14),
        _buildAccuracyChart(),
        const SizedBox(height: 18),
        _buildReactionChart(),
        const SizedBox(height: 18),
        _buildTremorChart(),
      ],
    );
  }

  Widget _buildAccuracyChart() {
    final sessions = _report!.sessions;
    final spots = <FlSpot>[];

    for (int i = 0; i < sessions.length; i++) {
      if (sessions[i].accuracyRate != null) {
        spots.add(FlSpot(i.toDouble(), sessions[i].accuracyRate!));
      }
    }

    return RepaintBoundary(
      key: _accuracyChartKey,
      child: _chart("Accuracy Trend", spots, 100),
    );
  }

  Widget _buildReactionChart() {
    final sessions = _report!.sessions;
    final spots = <FlSpot>[];

    double max = 1000;

    for (int i = 0; i < sessions.length; i++) {
      if (sessions[i].reactionTimeMs != null) {
        final val = sessions[i].reactionTimeMs!.toDouble();
        spots.add(FlSpot(i.toDouble(), val));
        if (val > max) max = val;
      }
    }

    return RepaintBoundary(
      key: _reactionChartKey,
      child: _chart("Reaction Time Trend", spots, max + 200),
    );
  }

  Widget _buildTremorChart() {
    final sessions = _report!.sessions;
    final spots = <FlSpot>[];

    double max = 1.0;

    for (int i = 0; i < sessions.length; i++) {
      if (sessions[i].tremorIndex != null) {
        final val = sessions[i].tremorIndex!;
        spots.add(FlSpot(i.toDouble(), val));
        if (val > max) max = val;
      }
    }

    return RepaintBoundary(
      key: _tremorChartKey,
      child: _chart("Tremor Index Trend", spots, max + 0.2),
    );
  }

  Widget _chart(String title, List<FlSpot> spots, double maxY) {
  return Container(
    padding: const EdgeInsets.all(22),
    decoration: _panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1C2430),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,

              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => const Color(0xFFF8FAFC),
                  tooltipRoundedRadius: 12,
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  tooltipBorder: const BorderSide(
                    color: Color(0xFFBAE6FD),
                    width: 1,
                  ),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      return LineTooltipItem(
                        spot.y.toStringAsFixed(1),
                        const TextStyle(
                          color: Color(0xFF0369A1),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),

              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return const FlLine(
                    color: Color(0xFFE5E7EB),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: const FlTitlesData(
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 4,
                  color: const Color(0xFF1E6BA8),
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF1E6BA8).withOpacity(0.10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildSessionTable() {
    final sessions = _report!.sessions;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.history_rounded,
            title: "Session History",
            subtitle: "Select a session to update the fusion-based risk analysis above.",
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                dataRowMinHeight: 58,
                dataRowMaxHeight: 66,
                columnSpacing: 28,
                columns: const [
                  DataColumn(label: Text("Date")),
                  DataColumn(label: Text("Score")),
                  DataColumn(label: Text("Accuracy")),
                  DataColumn(label: Text("Reaction")),
                  DataColumn(label: Text("Miss")),
                  DataColumn(label: Text("Session Type")),
                ],
                rows: List.generate(sessions.length, (i) {
                  final s = sessions[i];
                  final isSelected = _selectedSessionId == s.sessionId;

                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: (_) async {
                    if (_selectedSessionId == s.sessionId) return;

                    setState(() {
                      _selectedSessionId = s.sessionId;
                    });

                    await _loadFusionAssessment(s.sessionId);
                  },
                    color: WidgetStateProperty.resolveWith<Color?>(
                      (states) {
                        if (states.contains(WidgetState.selected)) {
                          return const Color(0xFFE0F2FE);
                        }

                        return i.isEven ? Colors.white : const Color(0xFFF8FAFC);
                      },
                    ),
                    cells: [
                      DataCell(Text(formatDate(s.startTime))),
                      DataCell(Text("${s.score ?? '-'}")),
                      DataCell(
                        Text(
                          s.accuracyRate == null
                              ? "-"
                              : "${s.accuracyRate!.toStringAsFixed(1)}%",
                        ),
                      ),
                      DataCell(
                        Text(
                          s.reactionTimeMs == null
                              ? "-"
                              : "${s.reactionTimeMs} ms",
                        ),
                      ),
                      DataCell(
                        Tooltip(
                          message:
                              "False Starts: ${s.falseStartCount ?? 0}\n"
                              "Wrong Taps: ${s.wrongTapCount ?? 0}\n"
                              "Timeouts: ${s.timeoutCount ?? 0}\n"
                              "False Alarms: ${s.falseAlarmCount ?? 0}\n"
                              "Omissions: ${s.omissionCount ?? 0}\n"
                              "Motor Success: ${s.successfulCutCount ?? 0}\n"
                              "Motor Miss: ${s.sliceMissCount ?? 0}\n"
                              "Near-Miss Events: ${s.nearMissCount ?? 0}\n"
                              "Tremor Index: ${s.tremorIndex == null ? '-' : s.tremorIndex!.toStringAsFixed(2)}",
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("${s.missCount ?? '-'}"),
                              if (s.missCount != null && s.missCount! > 0) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 14,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      DataCell(buildSessionTypeBadge(s.sessionType)),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSessionTypeBadge(String? sessionType) {
    String label;
    Color backgroundColor;
    Color textColor;

    switch (sessionType) {
      case "reaction":
        label = "Reaction Task";
        backgroundColor = const Color(0xFFE0F2FE);
        textColor = const Color(0xFF0369A1);
        break;
      case "decision":
        label = "Decision Task";
        backgroundColor = const Color(0xFFF3E8FF);
        textColor = const Color(0xFF7E22CE);
        break;
      case "target_movement":
        label = "Target Movement Task";
        backgroundColor = const Color(0xFFECFCCB);
        textColor = const Color(0xFF4D7C0F);
        break;
      case "visual_memory":
        label = "Visual Memory Task";
        backgroundColor = const Color(0xFFCCFBF1);
        textColor = const Color(0xFF0F766E);
        break;
      default:
        label = "-";
        backgroundColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withOpacity(0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF1E6BA8),
            size: 23,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1C2430),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    );
  }

  Widget _softBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0369A1),
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _infoPanel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF1E6BA8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
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
    );
  }
}

class _SummaryData {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryData(this.title, this.value, this.icon);
}

class _MiniMetricData {
  final String title;
  final String value;

  const _MiniMetricData(this.title, this.value);
}