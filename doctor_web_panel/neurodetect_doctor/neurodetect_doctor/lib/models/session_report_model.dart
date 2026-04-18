class PatientReportModel {
  final PatientInfo patient;
  final PatientSummary summary;
  final List<SessionReportItem> sessions;

  PatientReportModel({
    required this.patient,
    required this.summary,
    required this.sessions,
  });

  factory PatientReportModel.fromJson(Map<String, dynamic> json) {
    return PatientReportModel(
      patient: PatientInfo.fromJson(json['patient']),
      summary: PatientSummary.fromJson(json['summary']),
      sessions: (json['sessions'] as List)
          .map((e) => SessionReportItem.fromJson(e))
          .toList(),
    );
  }
}

class PatientInfo {
  final int userId;
  final String username;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? address;
  final String? dob;
  final String? gender;

  PatientInfo({
    required this.userId,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.address,
    required this.dob,
    required this.gender,
  });

  String get fullName {
    final first = firstName?.trim() ?? "";
    final last = lastName?.trim() ?? "";
    final combined = "$first $last".trim();
    return combined.isEmpty ? username : combined;
  }

  factory PatientInfo.fromJson(Map<String, dynamic> json) {
    return PatientInfo(
      userId: json['user_id'],
      username: json['username'],
      email: json['email'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      phone: json['phone'],
      address: json['address'],
      dob: json['dob'],
      gender: json['gender'],
    );
  }
}

class PatientSummary {
  final int totalSessions;
  final double avgScore;
  final double avgAccuracy;
  final double avgReactionTime;
  final int totalMissCount;
  final double? latestRiskScore;
  final String? latestRiskLevel;
  final String? latestRiskAlert;
  final String? latestAssessmentTime;

  PatientSummary({
    required this.totalSessions,
    required this.avgScore,
    required this.avgAccuracy,
    required this.avgReactionTime,
    required this.totalMissCount,
    required this.latestRiskScore,
    required this.latestRiskLevel,
    required this.latestRiskAlert,
    required this.latestAssessmentTime,
  });

  factory PatientSummary.fromJson(Map<String, dynamic> json) {
    return PatientSummary(
      totalSessions: json['total_sessions'] ?? 0,
      avgScore: (json['avg_score'] as num?)?.toDouble() ?? 0.0,
      avgAccuracy: (json['avg_accuracy'] as num?)?.toDouble() ?? 0.0,
      avgReactionTime: (json['avg_reaction_time'] as num?)?.toDouble() ?? 0.0,
      totalMissCount: json['total_miss_count'] ?? 0,
      latestRiskScore: (json['latest_risk_score'] as num?)?.toDouble(),
      latestRiskLevel: json['latest_risk_level'],
      latestRiskAlert: json['latest_risk_alert'],
      latestAssessmentTime: json['latest_assessment_time'],
    );
  }
}

class SessionReportItem {
  final int sessionId;
  final String? startTime;
  final String? endTime;
  final String? sessionType;
  final int? score;
  final double? accuracyRate;
  final int? reactionTimeMs;
  final int? missCount;
  final int? tapCount;
  final int? falseStartCount;
  final int? wrongTapCount;
  final int? timeoutCount;
  final int? falseAlarmCount;
  final int? omissionCount;
  final double? riskScore;
  final String? riskLevel;
  final String? riskAlert;
  final String? assessmentTime;

  SessionReportItem({
    required this.sessionId,
    required this.startTime,
    required this.endTime,
    required this.sessionType,
    required this.score,
    required this.accuracyRate,
    required this.reactionTimeMs,
    required this.missCount,
    required this.tapCount,
    required this.falseStartCount,
    required this.wrongTapCount,
    required this.timeoutCount,
    required this.falseAlarmCount,
    required this.omissionCount,
    required this.riskScore,
    required this.riskLevel,
    required this.riskAlert,
    required this.assessmentTime,
  });

  factory SessionReportItem.fromJson(Map<String, dynamic> json) {
    return SessionReportItem(
      sessionId: json['session_id'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      sessionType: json['session_type'],
      score: json['score'],
      accuracyRate: (json['accuracy_rate'] as num?)?.toDouble(),
      reactionTimeMs: json['reaction_time_ms'],
      missCount: json['miss_count'],
      tapCount: json['tap_count'],
      falseStartCount: json['false_start_count'],
      wrongTapCount: json['wrong_tap_count'],
      timeoutCount: json['timeout_count'],
      falseAlarmCount: json['false_alarm_count'],
      omissionCount: json['omission_count'],
      riskScore: (json['risk_score'] as num?)?.toDouble(),
      riskLevel: json['risk_level'],
      riskAlert: json['risk_alert'],
      assessmentTime: json['assessment_time'],
    );
  }
}