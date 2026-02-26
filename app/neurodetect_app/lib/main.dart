import 'package:flutter/material.dart';
import 'package:neurodetect_app/models/test_result.dart'; 
import 'package:neurodetect_app/services/test_service.dart';
import 'package:neurodetect_app/services/api_service.dart';

void main() {
  runApp(const NeuroDetectApp());
}

class NeuroDetectApp extends StatelessWidget {
  const NeuroDetectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NeuroDetect Prototip',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const NeuroDetectTestPage(title: 'NeuroDetect: Motor Test'),
    );
  }
}

class NeuroDetectTestPage extends StatefulWidget {
  const NeuroDetectTestPage({super.key, required this.title});
  final String title;

  @override
  State<NeuroDetectTestPage> createState() => _NeuroDetectTestPageState();
}

class _NeuroDetectTestPageState extends State<NeuroDetectTestPage> {
  // Servislerimizi tanımlıyoruz
  final TestService _testService = TestService();
  final ApiService _apiService = ApiService();
  
  // Veri listesi
  final List<TestResult> _allResults = [];

  // Durum değişkenleri
  int _successCount = 0;
  int _totalClicks = 0;
  double _top = 250;
  double _left = 150;
  int _lastTimestamp = 0;
  bool _isTestActive = false;

  // Ana etkileşim yöneticisi
  void _handleInteraction(bool hitTarget) {
    final int now = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _totalClicks++;

      if (hitTarget) {
        _successCount++;
        double currentAccuracy = _testService.calculateAccuracy(_successCount, _totalClicks);
        
        // Eğer bu ilk dokunuş değilse tepki süresi ve sonuçları kaydet
        if (_lastTimestamp != 0) {
          final result = TestResult(
            reactionTime: now - _lastTimestamp,
            isSuccess: true,
            accuracy: currentAccuracy,
            score: _successCount * 10,
            timestamp: DateTime.now(),
          );

          // 1. Yerel listeye ekle
          _allResults.add(result);

          // 2. Sunucuya/Veritabanına gönder (İlmek ilmek bağlanan kısım)
          _apiService.sendGameMetrics(result).then((success) {
            if (success) {
              debugPrint("Veri başarıyla buluta iletildi.");
            } else {
              debugPrint("Bulut bağlantısı kurulamadı (Backend henüz çalışmıyor olabilir).");
            }
          });
        }

        // Hedefi yeni konuma taşı
        _top = _testService.getNextCoordinate(MediaQuery.of(context).size.height);
        _left = _testService.getNextCoordinate(MediaQuery.of(context).size.width);
        
        _lastTimestamp = now;
        _isTestActive = true;
      } else {
        // Iskalama (Miss) durumunu kaydet
        _allResults.add(TestResult(
          reactionTime: 0,
          isSuccess: false,
          accuracy: _testService.calculateAccuracy(_successCount, _totalClicks),
          score: _successCount * 10,
          timestamp: DateTime.now(),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double accuracy = _testService.calculateAccuracy(_successCount, _totalClicks);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: GestureDetector(
        onTap: () => _handleInteraction(false),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            _buildStatPanel(accuracy),
            Positioned(
              top: _top,
              left: _left,
              child: _buildTargetView(),
            ),
            if (!_isTestActive)
              const Center(child: Text("Testi başlatmak için hedefe dokunun")),
          ],
        ),
      ),
    );
  }

  // UI Bileşeni: İstatistik Paneli
  Widget _buildStatPanel(double accuracy) {
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Başarılı: $_successCount", 
                 style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            Text("Iskalama: ${_totalClicks - _successCount}", 
                 style: const TextStyle(color: Colors.red)),
            Text("Doğruluk: %${accuracy.toStringAsFixed(1)}"),
          ],
        ),
      ),
    );
  }

  // UI Bileşeni: Kırmızı Hedef
  Widget _buildTargetView() {
    return GestureDetector(
      onTap: () => _handleInteraction(true),
      child: Container(
        width: 70,
        height: 70,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
        ),
        child: const Center(
          child: Text("DOKUN", 
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}