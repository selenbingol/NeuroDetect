import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/doctor_user_model.dart';
import '../models/patient_summary_model.dart';
import '../models/session_report_model.dart';
import '../models/fusion_assessment_model.dart';

class ApiService {
  final String _baseUrl = "http://127.0.0.1:8000";

  Future<DoctorUserModel?> loginDoctor(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password_hash": password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["role"] != "doctor") {
          return null;
        }

        return DoctorUserModel.fromJson(data);
      } else {
        return null;
      }
    } catch (e) {
      print("Doctor login hatası: $e");
      return null;
    }
  }

  Future<List<PatientSummaryModel>> getPatients() async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/patients"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => PatientSummaryModel.fromJson(e)).toList();
      } else {
        print("Patients alınamadı: ${response.body}");
        return [];
      }
    } catch (e) {
      print("Get patients hatası: $e");
      return [];
    }
  }

  Future<PatientReportModel?> getPatientReport(int userId) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/patients/$userId/report"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PatientReportModel.fromJson(data);
      } else {
        print("Patient report alınamadı: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Get patient report hatası: $e");
      return null;
    }
  }

  Future<FusionAssessmentModel> getFusionAssessment(int sessionId) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/fusion/assess/$sessionId"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return FusionAssessmentModel.fromJson(data);
      } else {
        throw Exception(
          "Fusion assessment alınamadı: ${response.statusCode} ${response.body}",
        );
      }
    } catch (e) {
      throw Exception("Get fusion assessment hatası: $e");
    }
  }

  // Eski widget'ların bundan veri alıyorsa kalsın diye bırakıyorum.
  // Yeni patient_detail_page.dart tarafında getFusionAssessment() kullanılacak.
  Future<Map<String, dynamic>?> fetchFusionData(int sessionId) async {
    final url = Uri.parse("$_baseUrl/api/fusion/assess/$sessionId");

    try {
      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Fusion data alınamadı: ${response.body}");
        return null;
      }
    } catch (e) {
      print("Fetch fusion data hatası: $e");
      return null;
    }
  }
  Future<List<RiskTrendPoint>> getRiskTrend(int userId) async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/api/fusion/trend/$userId"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List trendList = data["trend"] ?? [];

        return trendList.map((item) {
          return RiskTrendPoint(
            sessionId: item["session_id"] ?? 0,
            date: DateTime.tryParse(item["date"] ?? "") ?? DateTime.now(),
            cognitiveRiskScore: _toDouble(item["cognitive_risk"]),
            motorRiskScore: _toDouble(item["motor_risk"]),
            overallRiskScore: _toDouble(item["overall_risk"]),
            alzheimerProbability: _toDouble(item["alzheimer_probability"]),
            alsProbability: _toDouble(item["als_probability"]),
            riskLevel: item["risk_level"] ?? "low",
          );
        }).toList();
      } else {
        print("Risk trend alınamadı: ${response.body}");
        return [];
      }
    } catch (e) {
      print("Get risk trend hatası: $e");
      return [];
    }
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}