class TestResult {
  final int reactionTime;
  final bool isSuccess;
  final double accuracy;
  final int score;
  final DateTime timestamp;

  final int tapCount;
  final int missCount;
  final int falseStartCount;
  final int wrongTapCount;
  final int timeoutCount;
  final int falseAlarmCount;
  final int omissionCount;

  TestResult({
    required this.reactionTime,
    required this.isSuccess,
    required this.accuracy,
    required this.score,
    required this.timestamp,
    required this.tapCount,
    required this.missCount,
    required this.falseStartCount,
    required this.wrongTapCount,
    required this.timeoutCount,
    required this.falseAlarmCount,
    required this.omissionCount,
  });
}