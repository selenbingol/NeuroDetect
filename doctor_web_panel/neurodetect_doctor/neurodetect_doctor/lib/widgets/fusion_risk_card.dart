import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';

class FusionRiskCard extends StatelessWidget {
  final String title;
  final double score;
  final String subtitle;

  const FusionRiskCard({
    super.key,
    required this.title,
    required this.score,
    required this.subtitle,
  });

  Color _getRiskColor(double value) {
    if (value >= 70) {
      return const Color(0xFFB91C1C);
    } else if (value >= 40) {
      return const Color(0xFFD97706);
    } else {
      return const Color(0xFF15803D);
    }
  }

  String _getRiskLabel(double value) {
    if (value >= 70) {
      return "High";
    } else if (value >= 40) {
      return "Moderate";
    } else {
      return "Low";
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeScore = score.clamp(0, 100).toDouble();
    final riskColor = _getRiskColor(safeScore);
    final riskLabel = _getRiskLabel(safeScore);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: riskColor.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),

          const SizedBox(height: 14),

          CircularPercentIndicator(
            radius: 54,
            lineWidth: 10,
            percent: safeScore / 100,
            animation: true,
            circularStrokeCap: CircularStrokeCap.round,
            progressColor: riskColor,
            backgroundColor: const Color(0xFFE5E7EB),
            center: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  safeScore.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: riskColor,
                  ),
                ),
                const Text(
                  "/100",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              riskLabel,
              style: TextStyle(
                color: riskColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}