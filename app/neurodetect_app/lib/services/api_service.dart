import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';

class ApiService {
  final String _baseUrl = "https://neurodetect-api.onrender.com";
  final String _aiUrl = "http://localhost:5000";

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

      if (response.statusCode != 200) {
        print("Session bitirilemedi: ${response.body}");
      }

      return response.statusCode == 200;
    } catch (e) {
      print("End session hatası: $e");
      return false;
    }
  }

  // --- GAME METRICS ---
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
        print("Game metric gönderilemedi: ${response.body}");
      }

      return response.statusCode == 200;
    } catch (e) {
      print("Save game metrics hatası: $e");
      return false;
    }
  }

  // --- SENSOR METRICS ---
  Future<bool> saveSensorMetrics({
    required int sessionId,
    double? avgMotion,
    double? avgGyro,
    double? tremorIndex,
    double? movementVariability,
    int pathCorrectionCount = 0,
    int sampleCount = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/save-sensor-metrics"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "session_id": sessionId,
          "avg_motion": avgMotion,
          "avg_gyro": avgGyro,
          "tremor_index": tremorIndex,
          "movement_variability": movementVariability,
          "path_correction_count": pathCorrectionCount,
          "sample_count": sampleCount,
        }),
      );

      if (response.statusCode != 200) {
        print("Sensor metric gönderilemedi: ${response.body}");
      }

      return response.statusCode == 200;
    } catch (e) {
      print("Save sensor metrics hatası: $e");
      return false;
    }
  }

  // --- TARGET MOVEMENT / FRUIT GAME METRICS ---
  Future<bool> saveTargetMovementMetrics({
    required int sessionId,
    int sliceHitCount = 0,
    int sliceMissCount = 0,
    int successfulCutCount = 0,
    int nearMissCount = 0,
    double? avgSliceLength,
    double? avgCutCoverage,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/save-target-movement-metrics"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "session_id": sessionId,
          "slice_hit_count": sliceHitCount,
          "slice_miss_count": sliceMissCount,
          "successful_cut_count": successfulCutCount,
          "near_miss_count": nearMissCount,
          "avg_slice_length": avgSliceLength,
          "avg_cut_coverage": avgCutCoverage,
        }),
      );

      if (response.statusCode != 200) {
        print("Target movement metric gönderilemedi: ${response.body}");
      }

      return response.statusCode == 200;
    } catch (e) {
      print("Save target movement metrics hatası: $e");
      return false;
    }
  }

  // --- VISUAL MEMORY METRICS ---
  Future<bool> saveVisualMemoryMetrics({
    required int sessionId,
    required int totalRounds,
    required int gridItemCount,
    required int changedCardCount,
    required int correctSelectionCount,
    required int falseSelectionCount,
    required int omissionCount,
    required int falseStartCount,
    required int totalTargets,
    required int totalMisses,
    required double avgReactionTimeMs,
    required double accuracyRate,
    required int memoryScore,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/save-visual-memory-metrics"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "session_id": sessionId,
          "total_rounds": totalRounds,
          "grid_item_count": gridItemCount,
          "changed_card_count": changedCardCount,
          "correct_selection_count": correctSelectionCount,
          "false_selection_count": falseSelectionCount,
          "omission_count": omissionCount,
          "false_start_count": falseStartCount,
          "total_targets": totalTargets,
          "total_misses": totalMisses,
          "avg_reaction_time_ms": avgReactionTimeMs,
          "accuracy_rate": accuracyRate,
          "memory_score": memoryScore,
        }),
      );

      if (response.statusCode != 200) {
        print("Visual memory metric gönderilemedi: ${response.body}");
      }

      return response.statusCode == 200;
    } catch (e) {
      print("Save visual memory metrics hatası: $e");
      return false;
    }
  }

  // --- AI ANALİZ ---
  Future<Map<String, dynamic>?> getAiPrediction({
    required List<double> mri,
    required List<double> clinical,
    required List<double> game,
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