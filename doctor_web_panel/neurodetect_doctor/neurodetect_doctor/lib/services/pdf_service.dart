import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/session_report_model.dart';

class PdfService {
  static Future<void> generatePatientReport(
    PatientReportModel report, {
    Uint8List? accuracyChartBytes,
    Uint8List? reactionChartBytes,
  }) async {
    final pdf = pw.Document();

    final patient = report.patient;
    final summary = report.summary;
    final sessions = report.sessions;

    final accuracyImage =
        accuracyChartBytes != null ? pw.MemoryImage(accuracyChartBytes) : null;
    final reactionImage =
        reactionChartBytes != null ? pw.MemoryImage(reactionChartBytes) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        build: (context) => [
          _buildTopHeader(),
          pw.SizedBox(height: 14),
          _buildPatientIdentityCard(patient),
          pw.SizedBox(height: 14),
          _buildSectionTitle("Clinical Summary"),
          pw.SizedBox(height: 8),
          _buildSummaryGrid(summary),
          pw.SizedBox(height: 14),
          _buildRiskBlock(summary),
          pw.SizedBox(height: 14),
          _buildClinicalInterpretation(summary),
          pw.SizedBox(height: 14),
          if (accuracyImage != null || reactionImage != null) ...[
  pw.NewPage(),
  _buildChartsBlock(
    accuracyImage: accuracyImage,
    reactionImage: reactionImage,
  ),
],
          pw.NewPage(),
          _buildSessionTable(sessions),
          _buildFooter(),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  static pw.Widget _buildTopHeader() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#243B6B'),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "NeuroDetect",
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                "Clinical Cognitive-Motor Assessment Report",
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                "Generated",
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                _formatPdfDate(DateTime.now().toIso8601String()),
                style: const pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPatientIdentityCard(PatientInfo patient) {
    return pw.Container(
      decoration: _cardDecoration(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildBandTitle("Patient Profile"),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: pw.Row(
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
                pw.SizedBox(width: 24),
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
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryGrid(PatientSummary summary) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _summaryCard("Total Sessions", summary.totalSessions.toString()),
        _summaryCard("Average Score", summary.avgScore.toStringAsFixed(1)),
        _summaryCard(
          "Average Accuracy",
          "${summary.avgAccuracy.toStringAsFixed(1)}%",
        ),
        _summaryCard(
          "Avg Reaction Time",
          "${summary.avgReactionTime.toStringAsFixed(0)} ms",
        ),
        _summaryCard("Total Misses", summary.totalMissCount.toString()),
        _summaryCard(
          "Latest Assessment",
          summary.latestAssessmentTime == null
              ? "-"
              : _formatPdfDate(summary.latestAssessmentTime),
        ),
      ],
    );
  }

  static pw.Widget _summaryCard(String title, String value) {
    return pw.Container(
      width: 165,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F4F6F8'),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRiskBlock(PatientSummary summary) {
    final riskLevel = (summary.latestRiskLevel ?? "unknown").toLowerCase();

    PdfColor bg;
    PdfColor border;
    PdfColor text;

    switch (riskLevel) {
      case "high":
        bg = PdfColor.fromHex('#FDECEC');
        border = PdfColor.fromHex('#C0392B');
        text = PdfColor.fromHex('#922B21');
        break;
      case "moderate":
        bg = PdfColor.fromHex('#FFF4E5');
        border = PdfColor.fromHex('#D68910');
        text = PdfColor.fromHex('#A04000');
        break;
      case "low":
        bg = PdfColor.fromHex('#EAF7EC');
        border = PdfColor.fromHex('#239B56');
        text = PdfColor.fromHex('#196F3D');
        break;
      default:
        bg = PdfColor.fromHex('#F2F4F4');
        border = PdfColors.grey500;
        text = PdfColors.black;
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: border, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildBandTitle("Latest AI Risk Assessment", background: border),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Risk Level: ${summary.latestRiskLevel ?? '-'}",
                  style: pw.TextStyle(
                    color: text,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Risk Score: ${summary.latestRiskScore?.toStringAsFixed(1) ?? '-'}",
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Alert: ${summary.latestRiskAlert?.trim().isNotEmpty == true ? summary.latestRiskAlert : '-'}",
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

    if ((summary.latestRiskLevel ?? "").toLowerCase() == "high") {
      notes.add(
        "Most recent AI assessment indicates high risk and merits prompt clinician review.",
      );
    }

    return pw.Container(
      decoration: _cardDecoration(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildBandTitle("Clinical Interpretation"),
          pw.Padding(
            padding: const pw.EdgeInsets.all(14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: notes
                  .map(
                    (note) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Bullet(text: note),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildChartsBlock({
  pw.MemoryImage? accuracyImage,
  pw.MemoryImage? reactionImage,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _buildSectionTitle("Performance Trend Charts"),
      pw.SizedBox(height: 8),

      if (accuracyImage != null) ...[
        pw.Text(
          "Accuracy Trend",
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 13,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Image(accuracyImage, height: 180),
        pw.SizedBox(height: 12),
      ],

      if (reactionImage != null) ...[
        pw.Text(
          "Reaction Time Trend",
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 13,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Image(reactionImage, height: 180),
      ],
    ],
  );
}

 static pw.Widget _buildSessionTable(List<SessionReportItem> sessions) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [

      _buildBandTitle("Session History"),

      pw.Padding(
        padding: const pw.EdgeInsets.all(12),
        child: pw.TableHelper.fromTextArray(
          headers: const [
            "Date",
            "Score",
            "Accuracy",
            "Reaction",
            "Miss",
            "Risk Level",
          ],
          data: sessions.map((s) {
            return [
              _formatPdfDate(s.startTime),
              s.score?.toString() ?? "-",
              s.accuracyRate == null
                  ? "-"
                  : "${s.accuracyRate!.toStringAsFixed(1)}%",
              s.reactionTimeMs == null ? "-" : "${s.reactionTimeMs} ms",
              s.missCount?.toString() ?? "-",
              s.riskLevel ?? "-",
            ];
          }).toList(),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 10,
          ),
          headerDecoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#243B6B'),
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(6),
          rowDecoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.4,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

  static pw.Widget _buildFooter() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          "Generated by NeuroDetect",
          style: const pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey700,
          ),
        ),
        pw.Text(
          "Clinician Signature: ____________________",
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 16,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget _buildBandTitle(String title, {PdfColor? background}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: background ?? PdfColor.fromHex('#2FBF9F'),
        borderRadius: const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(6),
          topRight: pw.Radius.circular(6),
        ),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  static pw.Widget _infoLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: "$label: ",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  static pw.BoxDecoration _cardDecoration() {
    return pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: pw.BorderRadius.circular(6),
      border: pw.Border.all(color: PdfColors.grey300),
    );
  }

  static String _formatPdfDate(String? raw) {
    if (raw == null) return "-";
    try {
      final dt = DateTime.parse(raw);
      final minute = dt.minute.toString().padLeft(2, '0');
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:$minute";
    } catch (_) {
      return raw;
    }
  }
}