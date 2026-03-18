import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/test_result.dart';

class ApiService {
  final String _baseUrl = "http://127.0.0.1:8000";

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

  Future<int?> startSession(int userId) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/start-session"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "session_type": "game",
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

  Future<bool> sendGameMetrics(
    TestResult result,
    int sessionId,
    int missCount,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/save-metrics"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "session_id": sessionId,
          "score": result.score,
          "reaction_time_ms": result.reactionTime,
          "accuracy_rate": result.accuracy,
          "miss_count": missCount,
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
}