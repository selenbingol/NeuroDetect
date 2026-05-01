import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';

class ApiService {
  
  final String _baseUrl = "http://localhost:8000"; // Login servisi
  final String _aiUrl = "http://localhost:5000";   // Yapay Zeka servisi

  // --- KULLANICI İŞLEMLERİ ---
  Future<UserModel?> login(String username, String passwordHash) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password_hash": passwordHash,
        }),
      );

      if (response.statusCode == 200) {
        return UserModel.fromJson(jsonDecode(response.body));
      } else {
        print("Login başarısız: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Login hatası: $e");
      return null;
    }
  }

  // --- OTURUM (SESSION) İŞLEMLERİ ---
  Future<int?> startSession(int userId, String sessionType) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/start-session"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "session_type": sessionType,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["session_id"];
      } else {
        print("Session başlatılamadı: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Start session hatası: $e");
      return null;
    }
  }

  Future<bool> endSession(int sessionId) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/end-session"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "session_id": sessionId,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print("End session hatası: $e");
      return false;
    }
  }

  // --- VERİ TABANINA OYUN VERİLERİNİ KAYDETME ---
 Future<bool> sendGameMetrics({
  required int sessionId,
  required int score,
  required int reactionTimeMs,
  required double accuracyRate,
  required int missCount,
  int tapCount = 0,
  int falseStartCount = 0,
  int wrongTapCount = 0,
  int timeoutCount = 0,
  int falseAlarmCount = 0,
  int omissionCount = 0,
}) async {
  try {
    final response = await http.post(
      Uri.parse("$_baseUrl/save-metrics"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "session_id": sessionId,
        "score": score,
        "reaction_time_ms": reactionTimeMs,
        "accuracy_rate": accuracyRate,
        "miss_count": missCount,
        "tap_count": tapCount,
        "false_start_count": falseStartCount,
        "wrong_tap_count": wrongTapCount,
        "timeout_count": timeoutCount,
        "false_alarm_count": falseAlarmCount,
        "omission_count": omissionCount,
      }),
    );

    if (response.statusCode != 200) {
      print("Metric gönderilemedi: ${response.body}");
    }
    return response.statusCode == 200;
  } catch (e) {
    print("Save metrics hatası: $e");
    return false;
  }
}

  // ======================================================
  // YAPAY ZEKA ANALİZ FONKSİYONU (FLASK BAĞLANTISI)
  // ======================================================
  Future<Map<String, dynamic>?> getAiPrediction({
    required List<double> mri,       // [eTIV, nWBV, ASF]
    required List<double> clinical,  // [Age, EDUC, SES, MMSE, CDR, Gender]
    required List<double> game,      // [ReactionTime, Accuracy, MissCount]
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$_aiUrl/predict"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "mri": mri,
          "clinical": clinical,
          "game": game,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("AI Sunucu Hatası: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      print("AI Bağlantı Hatası: $e");
      return null;
    }
  }
}