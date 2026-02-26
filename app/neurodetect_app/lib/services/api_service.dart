import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/test_result.dart';

class ApiService {
  // Bu adres ileride Python Backend'e bağlanacak, şu an hazırlık aşamasında.
  final String _baseUrl = "http://localhost:8000"; 

  Future<bool> sendGameMetrics(TestResult result) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/save-metrics"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(result.toJson()), 
      );

      return response.statusCode == 200;
    } catch (e) {
      // Veritabanı henüz kurulu olmadığı için burada hata verecektir, normaldir.
      print("Bağlantı Kurulamadı (Beklenen durum): $e");
      return false;
    }
  }
}