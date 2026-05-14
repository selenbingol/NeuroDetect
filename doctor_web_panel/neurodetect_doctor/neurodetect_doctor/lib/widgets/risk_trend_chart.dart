import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/fusion_assessment_model.dart';

class RiskTrendChart extends StatelessWidget {
  final List<RiskTrendPoint> points;

  const RiskTrendChart({
    super.key,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardStyle(),
        child: const Text(
          "Risk trend data is not available yet.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final sortedPoints = [...points]
      ..sort((a, b) => a.date.compareTo(b.date));

    final cognitiveSpots = <FlSpot>[];
    final motorSpots = <FlSpot>[];
    final overallSpots = <FlSpot>[];

    for (int i = 0; i < sortedPoints.length; i++) {
      final x = i.toDouble();

      cognitiveSpots.add(
        FlSpot(
          x,
          sortedPoints[i].cognitiveRiskScore.clamp(0, 100).toDouble(),
        ),
      );

      motorSpots.add(
        FlSpot(
          x,
          sortedPoints[i].motorRiskScore.clamp(0, 100).toDouble(),
        ),
      );

      overallSpots.add(
        FlSpot(
          x,
          sortedPoints[i].overallRiskScore.clamp(0, 100).toDouble(),
        ),
      );
    }

    final maxX = sortedPoints.length <= 1
        ? 1.0
        : (sortedPoints.length - 1).toDouble();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Longitudinal Fusion Risk Trend",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Tracks cognitive, motor, and overall risk scores across previous sessions.",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),

          const Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _LegendItem(
                label: "Cognitive Risk",
                color: Color(0xFF7E22CE),
              ),
              _LegendItem(
                label: "Motor Risk",
                color: Color(0xFF0369A1),
              ),
              _LegendItem(
                label: "Overall Risk",
                color: Color(0xFFB91C1C),
              ),
            ],
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: 0,
                maxY: 100,
                lineTouchData: LineTouchData(
  enabled: true,
  touchTooltipData: LineTouchTooltipData(
    getTooltipColor: (touchedSpot) => const Color(0xFFF8FAFC),
    tooltipRoundedRadius: 12,
    tooltipPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 9,
    ),
    tooltipBorder: const BorderSide(
      color: Color(0xFFCBD5E1),
      width: 1,
    ),
    getTooltipItems: (touchedSpots) {
      return touchedSpots.map((spot) {
        Color textColor;

        if (spot.barIndex == 0) {
          textColor = const Color(0xFF7E22CE); // Cognitive Risk
        } else if (spot.barIndex == 1) {
          textColor = const Color(0xFF0369A1); // Motor Risk
        } else {
          textColor = const Color(0xFFB91C1C); // Overall Risk
        }

        return LineTooltipItem(
          spot.y.toStringAsFixed(2),
          TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            height: 1.45,
          ),
        );
      }).toList();
    },
  ),
),
                gridData: const FlGridData(
                  show: true,
                  horizontalInterval: 25,
                  verticalInterval: 1,
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: Color(0xFFE5E7EB),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: 25,
                      getTitlesWidget: (value, meta) {
                        if (value % 25 != 0) {
                          return const SizedBox.shrink();
                        }

                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();

                        if (index < 0 || index >= sortedPoints.length) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            "S${index + 1}",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  _lineBar(
                    spots: cognitiveSpots,
                    color: const Color(0xFF7E22CE),
                  ),
                  _lineBar(
                    spots: motorSpots,
                    color: const Color(0xFF0369A1),
                  ),
                  _lineBar(
                    spots: overallSpots,
                    color: const Color(0xFFB91C1C),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          const Text(
            "X-axis represents session order. Y-axis represents risk score between 0 and 100.",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static LineChartBarData _lineBar({
    required List<FlSpot> spots,
    required Color color,
  }) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3.5,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(
        show: true,
        color: color.withOpacity(0.08),
      ),
    );
  }

  BoxDecoration _cardStyle() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF374151),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}