import 'package:flutter/material.dart';
import '../models/patient_summary_model.dart';
import '../models/session_report_model.dart';
import '../services/api_service.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/pdf_service.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';


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

  bool _isLoading = true;
  String _errorMessage = "";
  PatientReportModel? _report;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    final report = await _apiService.getPatientReport(widget.patient.userId);

    if (!mounted) return;

    setState(() {
      _report = report;
      _isLoading = false;
      if (report == null) {
        _errorMessage = "Failed to load patient report.";
      }
    });
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
    final dt = DateTime.parse(raw);
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute}";
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

      await PdfService.generatePatientReport(
        _report!,
        accuracyChartBytes: accuracyChartBytes,
        reactionChartBytes: reactionChartBytes,
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
                            _buildSummaryCards(),
                            const SizedBox(height: 20),
                            _buildAccuracyChart(),
                            const SizedBox(height: 20),
                            _buildReactionChart(),
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
              Text(p.username,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              Text(p.email, style: const TextStyle(color: Colors.grey)),
              Text("Patient ID: ${p.userId}",
                  style: const TextStyle(color: Colors.grey)),
            ],
          )
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
          colors: [color.withOpacity(0.1), Colors.white],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
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
                    color: color),
              ),
              Text("Score: ${s.latestRiskScore ?? '-'}"),
            ],
          )
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
        _card("Sessions", s.totalSessions.toString()),
        _card("Accuracy", "${s.avgAccuracy.toStringAsFixed(1)}%"),
        _card("Score", s.avgScore.toStringAsFixed(1)),
        _card("Reaction", "${s.avgReactionTime.toStringAsFixed(0)} ms"),
        _card("Misses", s.totalMissCount.toString()),
      ],
    );
  }

  Widget _card(String title, String value) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  BoxDecoration _cardStyle() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 10)
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

  Widget _chart(String title, List<FlSpot> spots, double maxY) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      color: const Color(0xFF1E5F92).withOpacity(0.1),
                    ),
                  )
                ],
              ),
            ),
          )
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
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
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

              return DataRow(
                color: MaterialStateProperty.resolveWith<Color?>(
                  (states) =>
                      i % 2 == 0 ? Colors.white : const Color(0xFFF9FAFB),
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
                      message: "False Starts: ${s.falseStartCount ?? 0}\nWrong Taps: ${s.wrongTapCount ?? 0}\nTimeouts: ${s.timeoutCount ?? 0}\nFalse Alarms: ${s.falseAlarmCount ?? 0}\nOmissions: ${s.omissionCount ?? 0}",
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("${s.missCount ?? '-'}"),
                          if (s.missCount != null && s.missCount! > 0) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.info_outline, size: 14, color: Colors.grey),
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