class PatientSummaryModel {
  final int userId;
  final String username;
  final String email;
  final int totalSessions;
  final int? latestScore;
  final double? latestAccuracy;
  final String? lastSessionAt;

  PatientSummaryModel({
    required this.userId,
    required this.username,
    required this.email,
    required this.totalSessions,
    required this.latestScore,
    required this.latestAccuracy,
    required this.lastSessionAt,
  });

  factory PatientSummaryModel.fromJson(Map<String, dynamic> json) {
    return PatientSummaryModel(
      userId: json['user_id'],
      username: json['username'],
      email: json['email'],
      totalSessions: json['total_sessions'] ?? 0,
      latestScore: json['latest_score'],
      latestAccuracy: json['latest_accuracy'] == null
          ? null
          : (json['latest_accuracy'] as num).toDouble(),
      lastSessionAt: json['last_session_at'],
    );
  }
}