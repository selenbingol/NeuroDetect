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

  // Veritabanı şemasına ve API'ye uygun paketleme
  Map<String, dynamic> toJson() => {
    'session_id': 1, // Şimdilik varsayılan, ileride dinamik olacak
    'reaction_time_ms': reactionTime,
    'is_success': isSuccess,
    'accuracy_rate': accuracy,
    'score': score,
    'timestamp': timestamp.toIso8601String(),
  };
}