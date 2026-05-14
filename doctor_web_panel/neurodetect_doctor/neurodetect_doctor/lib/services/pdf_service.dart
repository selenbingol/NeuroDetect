import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/session_report_model.dart';

class PdfService {
  static final PdfColor _primary = PdfColor.fromHex('#0F4C81');
  static final PdfColor _primaryLight = PdfColor.fromHex('#E0F2FE');
  static final PdfColor _accent = PdfColor.fromHex('#2FBF9F');
  static final PdfColor _textDark = PdfColor.fromHex('#1C2430');
  static final PdfColor _textMuted = PdfColor.fromHex('#64748B');
  static final PdfColor _softBg = PdfColor.fromHex('#F8FAFC');
  static final PdfColor _border = PdfColor.fromHex('#E2E8F0');

  static Future<void> generatePatientReport(
    PatientReportModel report, {
    Uint8List? accuracyChartBytes,
    Uint8List? reactionChartBytes,
    Uint8List? tremorChartBytes,
  }) async {
    final pdf = pw.Document();

    final patient = report.patient;
    final summary = report.summary;

    final allSessions = [...report.sessions];

    allSessions.sort((a, b) {
      final dateA = DateTime.tryParse(a.startTime ?? "") ?? DateTime(1900);
      final dateB = DateTime.tryParse(b.startTime ?? "") ?? DateTime(1900);
      return dateB.compareTo(dateA);
    });

    final recentSessions = allSessions.take(20).toList();

    final accuracyImage =
        accuracyChartBytes != null ? pw.MemoryImage(accuracyChartBytes) : null;
    final reactionImage =
        reactionChartBytes != null ? pw.MemoryImage(reactionChartBytes) : null;
    final tremorImage =
        tremorChartBytes != null ? pw.MemoryImage(tremorChartBytes) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        footer: (context) => _buildPageFooter(context),
        build: (context) => [
          _buildTopHeader(patient),
          pw.SizedBox(height: 16),

          _buildPatientOverview(patient, summary),
          pw.SizedBox(height: 16),

          _buildSectionHeading(
            title: "Clinical Summary",
            subtitle: "Aggregated overview of cognitive, motor, and sensor-supported assessments.",
          ),
          pw.SizedBox(height: 10),
          _buildSummaryGrid(summary),
          pw.SizedBox(height: 16),

          _buildRiskBlock(summary),
          pw.SizedBox(height: 16),

          _buildClinicalInterpretation(summary),
          pw.SizedBox(height: 16),

          _buildTaskSpecificPdfMetrics(allSessions),

          if (accuracyImage != null ||
              reactionImage != null ||
              tremorImage != null) ...[
            pw.NewPage(),
            _buildSectionHeading(
              title: "Performance Trend Charts",
              subtitle: "Visual trend captures exported from the doctor panel.",
            ),
            pw.SizedBox(height: 12),
            _buildChartsBlock(
              accuracyImage: accuracyImage,
              reactionImage: reactionImage,
              tremorImage: tremorImage,
            ),
          ],

          pw.NewPage(),
          _buildSessionTable(
            recentSessions,
            totalSessionCount: allSessions.length,
          ),
          pw.SizedBox(height: 18),
          _buildSignatureBlock(),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  static pw.Widget _buildTopHeader(PatientInfo patient) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: _primary,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 44,
            height: 44,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFFFFF'),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Center(
              child: pw.Text(
                "ND",
                style: pw.TextStyle(
                  color: _primary,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "NeuroDetect",
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 23,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Clinical Cognitive-Motor Assessment Report",
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 10.5,
                  ),
                ),
                pw.SizedBox(height: 7),
                pw.Text(
                  patient.fullName,
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#1E6BA8'),
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  "Generated",
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  _formatPdfDate(DateTime.now().toIso8601String()),
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 8.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPatientOverview(
    PatientInfo patient,
    PatientSummary summary,
  ) {
    final riskPalette = _riskPalette(summary.latestRiskLevel);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: _cardDecoration(),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _smallCapsTitle("Patient Profile"),
                pw.SizedBox(height: 10),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _infoLine("Full Name", patient.fullName),
                          _infoLine("Patient ID", patient.userId.toString()),
                          _infoLine("Phone", patient.phone ?? "-"),
                          _infoLine("Date of Birth", patient.dob ?? "-"),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 18),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _infoLine("Username", patient.username),
                          _infoLine("Email", patient.email),
                          _infoLine("Gender", patient.gender ?? "-"),
                          _infoLine("Address", patient.address ?? "-"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 1,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: riskPalette.background,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: riskPalette.border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _smallCapsTitle("Latest Risk"),
                pw.SizedBox(height: 10),
                pw.Text(
                  summary.latestRiskLevel ?? "No data",
                  style: pw.TextStyle(
                    color: riskPalette.text,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  "Score",
                  style: pw.TextStyle(
                    color: _textMuted,
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  summary.latestRiskScore?.toStringAsFixed(1) ?? "-",
                  style: pw.TextStyle(
                    color: riskPalette.text,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSectionHeading({
    required String title,
    required String subtitle,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 8,
          height: 34,
          decoration: pw.BoxDecoration(
            color: _accent,
            borderRadius: pw.BorderRadius.circular(99),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  color: _textDark,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                subtitle,
                style: pw.TextStyle(
                  color: _textMuted,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryGrid(PatientSummary summary) {
    final items = [
      _PdfSummaryItem("Total Sessions", summary.totalSessions.toString()),
      _PdfSummaryItem("Average Score", summary.avgScore.toStringAsFixed(1)),
      _PdfSummaryItem("Average Accuracy", "${summary.avgAccuracy.toStringAsFixed(1)}%"),
      _PdfSummaryItem("Avg Reaction Time", "${summary.avgReactionTime.toStringAsFixed(0)} ms"),
      _PdfSummaryItem("Total Misses", summary.totalMissCount.toString()),
      _PdfSummaryItem("Avg Motion", summary.avgMotion.toStringAsFixed(2)),
      _PdfSummaryItem("Avg Gyro", summary.avgGyro.toStringAsFixed(2)),
      _PdfSummaryItem("Avg Tremor", summary.avgTremorIndex.toStringAsFixed(2)),
      _PdfSummaryItem(
        "Latest Assessment",
        summary.latestAssessmentTime == null
            ? "-"
            : _formatPdfDate(summary.latestAssessmentTime),
      ),
    ];

    return pw.Wrap(
      spacing: 9,
      runSpacing: 9,
      children: items.map((item) => _summaryCard(item)).toList(),
    );
  }

  static pw.Widget _summaryCard(_PdfSummaryItem item) {
    return pw.Container(
      width: 166,
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _softBg,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            item.title,
            style: pw.TextStyle(
              fontSize: 8.8,
              color: _textMuted,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            item.value,
            maxLines: 1,
            style: pw.TextStyle(
              fontSize: 15,
              color: _textDark,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRiskBlock(PatientSummary summary) {
    final palette = _riskPalette(summary.latestRiskLevel);

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: palette.background,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: palette.border),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 42,
            height: 42,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: palette.border),
            ),
            child: pw.Center(
              child: pw.Text(
                "AI",
                style: pw.TextStyle(
                  color: palette.text,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Latest AI Risk Assessment",
                  style: pw.TextStyle(
                    color: palette.text,
                    fontSize: 12.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  "Risk Level: ${summary.latestRiskLevel ?? '-'}",
                  style: pw.TextStyle(
                    color: palette.text,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "Risk Score: ${summary.latestRiskScore?.toStringAsFixed(1) ?? '-'}",
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  "Alert: ${summary.latestRiskAlert?.trim().isNotEmpty == true ? summary.latestRiskAlert : '-'}",
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildClinicalInterpretation(PatientSummary summary) {
    final notes = <String>[];

    if (summary.avgAccuracy < 50) {
      notes.add(
        "Observed average accuracy is below the preferred range and may indicate reduced task consistency.",
      );
    } else if (summary.avgAccuracy < 70) {
      notes.add(
        "Average accuracy is within a borderline range and may benefit from continued monitoring.",
      );
    } else {
      notes.add(
        "Average accuracy is within an acceptable range for the recorded sessions.",
      );
    }

    if (summary.avgReactionTime > 1800) {
      notes.add(
        "Average reaction time is elevated, suggesting slower response performance.",
      );
    } else if (summary.avgReactionTime > 1200) {
      notes.add(
        "Average reaction time is moderately elevated and should be reviewed alongside other indicators.",
      );
    } else {
      notes.add(
        "Reaction time profile appears relatively stable in the current dataset.",
      );
    }

    if (summary.totalMissCount > 20) {
      notes.add(
        "Total miss count is high and may reflect reduced attention stability or motor precision across sessions.",
      );
    }

    if (summary.avgTremorIndex > 0.30) {
      notes.add(
        "Average tremor index is elevated and may indicate reduced movement stability during sensor-based tasks.",
      );
    } else if (summary.avgTremorIndex > 0.15) {
      notes.add(
        "Average tremor index is mildly elevated and should be reviewed alongside target-movement performance.",
      );
    }

    if (summary.avgMotion > 1.20) {
      notes.add(
        "Average motion level is relatively high and may reflect increased corrective movement or unstable motor control.",
      );
    }

    if ((summary.latestRiskLevel ?? "").toLowerCase() == "high") {
      notes.add(
        "Most recent AI assessment indicates high risk and merits prompt clinician review.",
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _smallCapsTitle("Clinical Interpretation"),
          pw.SizedBox(height: 10),
          ...notes.map(
            (note) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 4),
                    width: 4,
                    height: 4,
                    decoration: pw.BoxDecoration(
                      color: _accent,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.Expanded(
                    child: pw.Text(
                      note,
                      style: const pw.TextStyle(
                        fontSize: 9.5,
                        height: 1.35,
                      ),
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

  static SessionReportItem? _latestSessionByType(
    List<SessionReportItem> sessions,
    String type,
  ) {
    for (final s in sessions) {
      if (s.sessionType == type) return s;
    }
    return null;
  }

  static pw.Widget _buildTaskSpecificPdfMetrics(
    List<SessionReportItem> sessions,
  ) {
    final reaction = _latestSessionByType(sessions, "reaction");
    final decision = _latestSessionByType(sessions, "decision");
    final target = _latestSessionByType(sessions, "target_movement");
    final visualMemory = _latestSessionByType(sessions, "visual_memory");

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _smallCapsTitle("Task-Specific Metrics"),
          pw.SizedBox(height: 10),
          _buildTaskMetricBlock(
            "Reaction Task",
            "Latest reaction response performance",
            [
              _PdfMetric("Tap Count", "${reaction?.tapCount ?? 0}"),
              _PdfMetric("False Start", "${reaction?.falseStartCount ?? 0}"),
              _PdfMetric("Wrong Tap", "${reaction?.wrongTapCount ?? 0}"),
              _PdfMetric("Timeout", "${reaction?.timeoutCount ?? 0}"),
              _PdfMetric("Miss Count", "${reaction?.missCount ?? 0}"),
              _PdfMetric(
                "Reaction",
                reaction?.reactionTimeMs == null
                    ? "-"
                    : "${reaction!.reactionTimeMs} ms",
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          _buildTaskMetricBlock(
            "Decision Task",
            "GO / NO-GO decision control indicators",
            [
              _PdfMetric("Correct Decisions", "${decision?.tapCount ?? 0}"),
              _PdfMetric("False Start", "${decision?.falseStartCount ?? 0}"),
              _PdfMetric("False Alarm", "${decision?.falseAlarmCount ?? 0}"),
              _PdfMetric("Omission", "${decision?.omissionCount ?? 0}"),
              _PdfMetric("Miss Count", "${decision?.missCount ?? 0}"),
              _PdfMetric(
                "Reaction",
                decision?.reactionTimeMs == null
                    ? "-"
                    : "${decision!.reactionTimeMs} ms",
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          _buildTaskMetricBlock(
            "Visual Memory Task",
            "Short-term visual recall and selection accuracy",
            [
              _PdfMetric("Score", "${visualMemory?.score ?? "-"}"),
              _PdfMetric(
                "Accuracy",
                visualMemory?.accuracyRate == null
                    ? "-"
                    : "${visualMemory!.accuracyRate!.toStringAsFixed(1)}%",
              ),
              _PdfMetric("Correct Selection", "${visualMemory?.tapCount ?? 0}"),
              _PdfMetric("False Selection", "${visualMemory?.wrongTapCount ?? 0}"),
              _PdfMetric("Omission", "${visualMemory?.omissionCount ?? 0}"),
              _PdfMetric("False Start", "${visualMemory?.falseStartCount ?? 0}"),
              _PdfMetric(
                "Recall Time",
                visualMemory?.reactionTimeMs == null
                    ? "-"
                    : "${visualMemory!.reactionTimeMs} ms",
              ),
            ],
          ),
          pw.SizedBox(height: 9),
          _buildTaskMetricBlock(
            "Target Movement Task",
            "Sensor-supported motor precision and tremor indicators",
            [
              _PdfMetric("Motor Success", "${target?.successfulCutCount ?? 0}"),
              _PdfMetric("Motor Miss", "${target?.sliceMissCount ?? 0}"),
              _PdfMetric("Near-Miss", "${target?.nearMissCount ?? 0}"),
              _PdfMetric(
                "Avg Motor Path",
                target?.avgSliceLength == null
                    ? "-"
                    : target!.avgSliceLength!.toStringAsFixed(1),
              ),
              _PdfMetric(
                "Coverage",
                target?.avgCutCoverage == null
                    ? "-"
                    : target!.avgCutCoverage!.toStringAsFixed(2),
              ),
              _PdfMetric(
                "Avg Motion",
                target?.avgMotion == null
                    ? "-"
                    : target!.avgMotion!.toStringAsFixed(2),
              ),
              _PdfMetric(
                "Avg Gyro",
                target?.avgGyro == null
                    ? "-"
                    : target!.avgGyro!.toStringAsFixed(2),
              ),
              _PdfMetric(
                "Tremor Index",
                target?.tremorIndex == null
                    ? "-"
                    : target!.tremorIndex!.toStringAsFixed(2),
              ),
              _PdfMetric(
                "Variability",
                target?.movementVariability == null
                    ? "-"
                    : target!.movementVariability!.toStringAsFixed(3),
              ),
              _PdfMetric("Path Corrections", "${target?.pathCorrectionCount ?? 0}"),
              _PdfMetric("Samples", "${target?.sampleCount ?? 0}"),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTaskMetricBlock(
    String title,
    String subtitle,
    List<_PdfMetric> metrics,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _softBg,
        borderRadius: pw.BorderRadius.circular(9),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              color: _textDark,
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            subtitle,
            style: pw.TextStyle(
              color: _textMuted,
              fontSize: 8.5,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 7,
            runSpacing: 7,
            children: metrics.map(_metricPill).toList(),
          ),
        ],
      ),
    );
  }

  static pw.Widget _metricPill(_PdfMetric metric) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            metric.label,
            maxLines: 1,
            style: pw.TextStyle(
              color: _textMuted,
              fontSize: 7.8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            metric.value,
            maxLines: 1,
            style: pw.TextStyle(
              color: _textDark,
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildChartsBlock({
    pw.MemoryImage? accuracyImage,
    pw.MemoryImage? reactionImage,
    pw.MemoryImage? tremorImage,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (accuracyImage != null) ...[
          _chartCard("Accuracy Trend", accuracyImage),
          pw.SizedBox(height: 12),
        ],
        if (reactionImage != null) ...[
          _chartCard("Reaction Time Trend", reactionImage),
          pw.SizedBox(height: 12),
        ],
        if (tremorImage != null) ...[
          _chartCard("Tremor Index Trend", tremorImage),
        ],
      ],
    );
  }

  static pw.Widget _chartCard(String title, pw.MemoryImage image) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _smallCapsTitle(title),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 155,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: _border),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Center(
              child: pw.Image(
                image,
                height: 145,
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _sessionTypeLabel(String? sessionType) {
    switch (sessionType) {
      case "reaction":
        return "Reaction";
      case "decision":
        return "Decision";
      case "target_movement":
        return "Target Movement";
      case "visual_memory":
        return "Visual Memory";
      default:
        return "-";
    }
  }

  static pw.Widget _buildSessionTable(
    List<SessionReportItem> sessions, {
    required int totalSessionCount,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _smallCapsTitle("Session History"),
          pw.SizedBox(height: 6),
          pw.Text(
            totalSessionCount > sessions.length
                ? "Showing latest ${sessions.length} sessions out of $totalSessionCount total sessions."
                : "Showing ${sessions.length} recorded sessions.",
            style: pw.TextStyle(
              fontSize: 9,
              color: _textMuted,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const [
              "Date",
              "Type",
              "Score",
              "Accuracy",
              "Reaction",
              "Miss",
            ],
            data: sessions.map((s) {
              return [
                _formatPdfDate(s.startTime),
                _sessionTypeLabel(s.sessionType),
                s.score?.toString() ?? "-",
                s.accuracyRate == null
                    ? "-"
                    : "${s.accuracyRate!.toStringAsFixed(1)}%",
                s.reactionTimeMs == null ? "-" : "${s.reactionTimeMs} ms",
                s.missCount?.toString() ?? "-",
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 8.8,
            ),
            headerDecoration: pw.BoxDecoration(
              color: _primary,
            ),
            cellStyle: pw.TextStyle(
              fontSize: 8,
              color: _textDark,
            ),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 5,
            ),
            rowDecoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: _border,
                  width: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _softBg,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "Generated by NeuroDetect Clinical Decision Support System",
            style: pw.TextStyle(
              fontSize: 8.5,
              color: _textMuted,
            ),
          ),
          pw.Text(
            "Clinician Signature: ____________________",
            style: pw.TextStyle(
              fontSize: 9,
              color: _textDark,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _border, width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "NeuroDetect Report",
            style: pw.TextStyle(
              fontSize: 8,
              color: _textMuted,
            ),
          ),
          pw.Text(
            "Page ${context.pageNumber} of ${context.pagesCount}",
            style: pw.TextStyle(
              fontSize: 8,
              color: _textMuted,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _smallCapsTitle(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: _primary,
        fontSize: 10.5,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget _infoLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: "$label: ",
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _textDark,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.TextSpan(
              text: value,
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.BoxDecoration _cardDecoration() {
    return pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: pw.BorderRadius.circular(12),
      border: pw.Border.all(color: _border),
    );
  }

  static _RiskPalette _riskPalette(String? riskLevel) {
    switch ((riskLevel ?? "").toLowerCase()) {
      case "high":
        return _RiskPalette(
          background: PdfColor.fromHex('#FEE2E2'),
          border: PdfColor.fromHex('#FCA5A5'),
          text: PdfColor.fromHex('#B91C1C'),
        );
      case "moderate":
        return _RiskPalette(
          background: PdfColor.fromHex('#FEF3C7'),
          border: PdfColor.fromHex('#FCD34D'),
          text: PdfColor.fromHex('#92400E'),
        );
      case "low":
        return _RiskPalette(
          background: PdfColor.fromHex('#DCFCE7'),
          border: PdfColor.fromHex('#86EFAC'),
          text: PdfColor.fromHex('#15803D'),
        );
      default:
        return _RiskPalette(
          background: PdfColor.fromHex('#F1F5F9'),
          border: PdfColor.fromHex('#CBD5E1'),
          text: PdfColor.fromHex('#475569'),
        );
    }
  }

  static String _formatPdfDate(String? raw) {
    if (raw == null) return "-";
    try {
      final dt = DateTime.parse(raw);
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');

      return "$day/$month/${dt.year} $hour:$minute";
    } catch (_) {
      return raw;
    }
  }
}

class _PdfSummaryItem {
  final String title;
  final String value;

  const _PdfSummaryItem(this.title, this.value);
}

class _PdfMetric {
  final String label;
  final String value;

  const _PdfMetric(this.label, this.value);
}

class _RiskPalette {
  final PdfColor background;
  final PdfColor border;
  final PdfColor text;

  const _RiskPalette({
    required this.background,
    required this.border,
    required this.text,
  });
}