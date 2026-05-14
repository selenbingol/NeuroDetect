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
    });

    try {
      final report = await _apiService.getPatientReport(widget.patient.userId);

      if (!mounted) return;

      setState(() {
        _report = report;
        _isLoading = false;

        if (report == null) {
          _errorMessage = "Failed to load patient report.";
        }
      });

      if (report != null && report.sessions.isNotEmpty) {
        final latestSession = report.sessions.first;

        setState(() {
          _selectedSessionId = latestSession.sessionId;
        });

        await _loadFusionAssessment(latestSession.sessionId);
        await _loadRiskTrend(widget.patient.userId);
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

  Future<Uint8List?> _captureWidget(GlobalKey key) async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));

      final context = key.currentContext;
      if (context == null) return null;

      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("Chart capture error: $e");
      return null;
    }
  }

  String formatDate(String? raw) {
    if (raw == null) return "-";

    try {
      final dt = DateTime.parse(raw);
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
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
      default:
        return "-";
    }
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
      default:
        label = "-";
        backgroundColor = const Color(0xFFF3F4F6);
        textColor = const Color(0xFF6B7280);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
        return const Color(0xFF6B7280);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('${widget.patient.firstName} ${widget.patient.lastName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () async {
              if (_report == null) return;

              final accuracyChartBytes = await _captureWidget(_accuracyChartKey);
              final reactionChartBytes = await _captureWidget(_reactionChartKey);
              final tremorChartBytes = await _captureWidget(_tremorChartKey);

              await PdfService.generatePatientReport(
                _report!,
                accuracyChartBytes: accuracyChartBytes,
                reactionChartBytes: reactionChartBytes,
                tremorChartBytes: tremorChartBytes,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Center(child: Text(_errorMessage))
                : _report == null
                    ? const Center(child: Text("No report available"))
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPatientHeader(),
                            const SizedBox(height: 20),

                            _buildRiskSection(),
                            const SizedBox(height: 20),

                            _buildFusionAnalysisSection(),
                            const SizedBox(height: 20),

                            _buildSummaryCards(),
                            const SizedBox(height: 20),

                            _buildDetailedMetricsSection(),
                            const SizedBox(height: 20),

                            _buildAccuracyChart(),
                            const SizedBox(height: 20),

                            _buildReactionChart(),
                            const SizedBox(height: 20),

                            _buildTremorChart(),
                            const SizedBox(height: 20),

                            _buildSessionTable(),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _buildPatientHeader() {
    final p = _report!.patient;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardStyle(),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Color(0xFFE8F1F8),
            child: Icon(Icons.person, size: 30),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.fullName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(p.email, style: const TextStyle(color: Colors.grey)),
              Text(
                "Patient ID: ${p.userId}",
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskSection() {
    final s = _report!.summary;
    final color = _riskColor(s.latestRiskLevel);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.10), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, size: 40, color: color),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("AI Risk Assessment"),
              Text(
                s.latestRiskLevel ?? "No data",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text("Score: ${s.latestRiskScore ?? '-'}"),
            ],
          ),
        ],
      ),
    );
  }
  

  Widget _buildFusionAnalysisSection() {
    if (_selectedSessionId == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardStyle(),
        child: const Text(
          "No session selected for fusion analysis.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_isFusionLoading) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _cardStyle(),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_fusionError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          _fusionError!,
          style: TextStyle(color: Colors.red.shade700),
        ),
      );
    }

    if (_fusionAssessment == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardStyle(),
        child: const Text(
          "Fusion analysis is not available for this session.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final fusion = _fusionAssessment!;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: Color(0xFF1E5F92)),
              const SizedBox(width: 8),
              const Text(
                "Fusion-Based Risk Analysis",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1F8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Session ID: $_selectedSessionId",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E5F92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
                  title: "Overall Risk",
                  score: fusion.overallRiskScore,
                  subtitle: "Combined multimodal risk score",
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Katman 2: Klinik Proxy Göstergeleri ──
          Row(
            children: [
              Expanded(
                child: _buildClinicalProbCard(
                  title: "Alzheimer Probability",
                  probability: fusion.alzheimerProbability,
                  riskLevel: fusion.alzheimerRiskLevel,
                  icon: Icons.psychology,
                  color: const Color(0xFF7E22CE),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildClinicalProbCard(
                  title: "ALS Probability",
                  probability: fusion.alsProbability,
                  riskLevel: fusion.alsRiskLevel,
                  icon: Icons.accessibility_new,
                  color: const Color(0xFF0369A1),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FusionRiskCard(
                  title: "Final Fusion Score",
                  score: fusion.finalFusionScore,
                  subtitle: "3-layer multimodal fusion result",
                ),
              ),
            ],
          ),

          // ── Baskın Faktörler ──
          if (fusion.dominantFactors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const Text(
                  "Dominant Factors: ",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                ...fusion.dominantFactors.map((f) {
                  final isHigh = f["impact"] == "high";
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isHigh
                          ? const Color(0xFFFEE2E2)
                          : const Color(0xFFFEF3C7),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isHigh
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF92400E),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],

          const SizedBox(height: 20),

          _buildXAIComment(fusion),

          const SizedBox(height: 24),

          if (_riskTrendPoints.isNotEmpty)
            RiskTrendChart(points: _riskTrendPoints)
          else
            const Text(
              "Risk trend data is not available yet.",
              style: TextStyle(color: Colors.grey),
            ),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology_alt_outlined, color: Color(0xFF1E5F92)),
              SizedBox(width: 8),
              Text(
                "Explainable AI Comment",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF374151),
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
  }) {
    final pct = (probability * 100).clamp(0, 100);
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    value: probability.clamp(0, 1),
                    strokeWidth: 7,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Text(
                  "%${pct.toStringAsFixed(0)}",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                levelLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: levelColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final s = _report!.summary;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _summaryCard("Sessions", s.totalSessions.toString()),
        _summaryCard("Accuracy", "${s.avgAccuracy.toStringAsFixed(1)}%"),
        _summaryCard("Score", s.avgScore.toStringAsFixed(1)),
        _summaryCard("Reaction", "${s.avgReactionTime.toStringAsFixed(0)} ms"),
        _summaryCard("Misses", s.totalMissCount.toString()),
        _summaryCard("Avg Motion", s.avgMotion.toStringAsFixed(2)),
        _summaryCard("Avg Gyro", s.avgGyro.toStringAsFixed(2)),
        _summaryCard("Avg Tremor", s.avgTremorIndex.toStringAsFixed(2)),
      ],
    );
  }

  Widget _summaryCard(String title, String value) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Task-Specific Metrics",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildReactionMetricsCard(reaction),
            _buildDecisionMetricsCard(decision),
            _buildTargetMovementMetricsCard(targetMovement),
          ],
        ),
      ],
    );
  }

  Widget _buildReactionMetricsCard(SessionReportItem? session) {
    return Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildSessionTypeBadge("reaction"),
              const SizedBox(width: 10),
              const Text(
                "Latest Reaction Metrics",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (session == null)
            const Text("No reaction session found.")
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _miniMetric("Tap Count", "${session.tapCount ?? 0}"),
                _miniMetric("False Start", "${session.falseStartCount ?? 0}"),
                _miniMetric("Wrong Tap", "${session.wrongTapCount ?? 0}"),
                _miniMetric("Timeout", "${session.timeoutCount ?? 0}"),
                _miniMetric("Miss Count", "${session.missCount ?? 0}"),
                _miniMetric(
                  "Reaction",
                  session.reactionTimeMs == null
                      ? "-"
                      : "${session.reactionTimeMs} ms",
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDecisionMetricsCard(SessionReportItem? session) {
    return Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildSessionTypeBadge("decision"),
              const SizedBox(width: 10),
              const Text(
                "Latest Decision Metrics",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (session == null)
            const Text("No decision session found.")
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _miniMetric("Correct Decisions", "${session.tapCount ?? 0}"),
                _miniMetric("False Start", "${session.falseStartCount ?? 0}"),
                _miniMetric("False Alarm", "${session.falseAlarmCount ?? 0}"),
                _miniMetric("Omission", "${session.omissionCount ?? 0}"),
                _miniMetric("Miss Count", "${session.missCount ?? 0}"),
                _miniMetric(
                  "Reaction",
                  session.reactionTimeMs == null
                      ? "-"
                      : "${session.reactionTimeMs} ms",
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTargetMovementMetricsCard(SessionReportItem? session) {
    return Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildSessionTypeBadge("target_movement"),
              const SizedBox(width: 10),
              const Text(
                "Latest Sensor-Based Motor Metrics",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (session == null)
            const Text("No target movement session found.")
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _miniMetric("Motor Success", "${session.successfulCutCount ?? 0}"),
                _miniMetric("Motor Miss", "${session.sliceMissCount ?? 0}"),
                _miniMetric("Near-Miss Events", "${session.nearMissCount ?? 0}"),
                _miniMetric(
                  "Avg Motor Path",
                  session.avgSliceLength == null
                      ? "-"
                      : session.avgSliceLength!.toStringAsFixed(1),
                ),
                _miniMetric(
                  "Movement Coverage",
                  session.avgCutCoverage == null
                      ? "-"
                      : session.avgCutCoverage!.toStringAsFixed(2),
                ),
                _miniMetric(
                  "Avg Motion",
                  session.avgMotion == null
                      ? "-"
                      : session.avgMotion!.toStringAsFixed(2),
                ),
                _miniMetric(
                  "Avg Gyro",
                  session.avgGyro == null
                      ? "-"
                      : session.avgGyro!.toStringAsFixed(2),
                ),
                _miniMetric(
                  "Tremor Index",
                  session.tremorIndex == null
                      ? "-"
                      : session.tremorIndex!.toStringAsFixed(2),
                ),
                _miniMetric(
                  "Movement Variability",
                  session.movementVariability == null
                      ? "-"
                      : session.movementVariability!.toStringAsFixed(3),
                ),
                _miniMetric(
                  "Path Corrections",
                  "${session.pathCorrectionCount ?? 0}",
                ),
                _miniMetric(
                  "Sensor Samples",
                  "${session.sampleCount ?? 0}",
                ),
              ],
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
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardStyle() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 10),
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
      padding: const EdgeInsets.all(20),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    barWidth: 4,
                    color: const Color(0xFF1E5F92),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF1E5F92).withValues(alpha: 0.10),
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
      padding: const EdgeInsets.all(20),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Session History",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Select a session to update the fusion-based risk analysis above.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
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
                    setState(() {
                      _selectedSessionId = s.sessionId;
                    });

                    await _loadFusionAssessment(s.sessionId);
                  },
                  color: WidgetStateProperty.resolveWith<Color?>(
                    (states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFFE8F1F8);
                      }

                      return i.isEven ? Colors.white : const Color(0xFFF9FAFB);
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
                                Icons.info_outline,
                                size: 14,
                                color: Colors.grey,
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
        ],
      ),
    );
  }
}