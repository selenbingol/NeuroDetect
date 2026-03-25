import 'dart:convert';
import 'package:http/http.dart' as http;

class AnalysisService {
  // ÖNEMLİ: Kendi terminalinde gördüğün IP adresini buraya yaz
  static const String baseUrl = "http://192.168.1.72:5000";

  static Future<Map<String, dynamic>?> getPrediction({
    required List<double> mri,
    required List<double> clinical,
    required List<double> game,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mri': mri,
          'clinical': clinical,
          'game': game,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Sunucu Hatası: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Bağlantı Hatası: $e");
      return null;
    }
  }
}