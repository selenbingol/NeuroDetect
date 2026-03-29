import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/doctor_user_model.dart';
import '../models/patient_summary_model.dart';
import '../models/session_report_model.dart';

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
}