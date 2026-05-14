class FusionAssessmentModel {
  final int sessionId;
  final double cognitiveRiskScore;
  final double motorRiskScore;
  final double overallRiskScore;
  final String riskLevel;
  final String explanation;

  // Katman 2 — Klinik Proxy
  final double alzheimerProbability;
  final String alzheimerRiskLevel;
  final double alsProbability;
  final String alsRiskLevel;

  // Katman 3 — Nihai Füzyon
  final double finalFusionScore;
  final List<Map<String, dynamic>> dominantFactors;

  FusionAssessmentModel({
    required this.sessionId,
    required this.cognitiveRiskScore,
    required this.motorRiskScore,
    required this.overallRiskScore,
    required this.riskLevel,
    required this.explanation,
    required this.alzheimerProbability,
    required this.alzheimerRiskLevel,
    required this.alsProbability,
    required this.alsRiskLevel,
    required this.finalFusionScore,
    required this.dominantFactors,
  });

  factory FusionAssessmentModel.fromJson(Map<String, dynamic> json) {
    // Klinik göstergeler iç içe gelebilir
    final clinical = json["clinical_indicators"] as Map<String, dynamic>? ?? {};

    return FusionAssessmentModel(
      sessionId: json["session_id"] ?? json["sessionId"] ?? 0,

      cognitiveRiskScore: _toDouble(
        json["cognitive_risk_score"] ??
            json["cognitiveRiskScore"] ??
            json["cognitive_risk"],
      ),

      motorRiskScore: _toDouble(
        json["motor_risk_score"] ??
            json["motorRiskScore"] ??
            json["motor_risk"],
      ),

      overallRiskScore: _toDouble(
        json["overall_risk_score"] ??
            json["overallRiskScore"] ??
            json["digital_risk_score"] ??
            json["final_risk_score"],
      ),

      riskLevel: json["risk_level"] ?? json["riskLevel"] ?? "Unknown",

      explanation: json["xai_explanation"] ??
          json["explanation"] ??
          json["xai_comment"] ??
          json["comment"] ??
          "",

      // Klinik proxy alanları
      alzheimerProbability: _toDouble(
        clinical["alzheimer_probability"] ??
            json["alzheimer_probability"],
      ),

      alzheimerRiskLevel:
          clinical["alzheimer_risk_level"] ??
          json["alzheimer_risk_level"] ??
          "unknown",

      alsProbability: _toDouble(
        clinical["als_probability"] ??
            json["als_probability"],
      ),

      alsRiskLevel:
          clinical["als_risk_level"] ??
          json["als_risk_level"] ??
          "unknown",

      // Nihai füzyon
      finalFusionScore: _toDouble(
        json["final_fusion_score"] ??
            json["finalFusionScore"] ??
            json["digital_risk_score"],
      ),

      dominantFactors: _parseFactors(json["dominant_factors"]),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static List<Map<String, dynamic>> _parseFactors(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
          .toList();
    }
    return [];
  }
}

class RiskTrendPoint {
  final int sessionId;
  final DateTime date;
  final double cognitiveRiskScore;
  final double motorRiskScore;
  final double overallRiskScore;

  RiskTrendPoint({
    required this.sessionId,
    required this.date,
    required this.cognitiveRiskScore,
    required this.motorRiskScore,
    required this.overallRiskScore,
  });
}