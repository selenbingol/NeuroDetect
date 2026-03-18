class TestResult {
  final int reactionTime;
  final bool isSuccess;
  final double accuracy;
  final int score;
  final DateTime timestamp;

  TestResult({
    required this.reactionTime,
    required this.isSuccess,
    required this.accuracy,
    required this.score,
    required this.timestamp,
  });
}