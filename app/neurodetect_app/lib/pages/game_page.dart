import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/test_result.dart';
import '../services/api_service.dart';

class GamePage extends StatefulWidget {
  final UserModel user;

  const GamePage({super.key, required this.user});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final ApiService _apiService = ApiService();

  static const int _maxClicks = 10;

  int? _sessionId;
  bool _isLoadingSession = true;
  bool _isGameFinished = false;
  String _message = "Oturum başlatılıyor...";

  int _successCount = 0;
  int _missCount = 0;
  int _totalClicks = 0;
  double _top = 250;
  double _left = 150;
  int _lastTimestamp = 0;

  // AI sonuçlarını (göstermesek de) arka planda tutmak için
  bool _isAiLoading = false;
  String? _aiResult;

  final List<int> _reactionTimes = [];

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    final sessionId = await _apiService.startSession(widget.user.userId);
    if (!mounted) return;

    setState(() {
      _sessionId = sessionId;
      _isLoadingSession = false;
      _message = sessionId != null ? "Oturum Hazır" : "Bağlantı Hatası";
    });
  }

  void _handleInteraction(bool hitTarget) {
    if (_isGameFinished || _isLoadingSession) return;

    final int now = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _totalClicks++;
      if (hitTarget) {
        _successCount++;
        if (_lastTimestamp != 0) {
          _reactionTimes.add(now - _lastTimestamp);
        }
        // Hedefi rastgele yere taşı
        _top = 100 + (now % 300).toDouble();
        _left = 50 + (now % 200).toDouble();
        _lastTimestamp = now;
      } else {
        _missCount++;
      }
    });

    if (_totalClicks >= _maxClicks) {
      _finishGame();
    }
  }

  Future<void> _finishGame() async {
    if (_sessionId == null) return;

    final double accuracy = _totalClicks == 0 ? 0.0 : (_successCount / _totalClicks);
    final avgReactionTime = _reactionTimes.isEmpty
        ? 0.0
        : (_reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length);

    final result = TestResult(
      reactionTime: avgReactionTime.round(),
      isSuccess: true,
      accuracy: accuracy * 100,
      score: _successCount * 10,
      timestamp: DateTime.now(),
    );

    setState(() { 
      _isGameFinished = true;
      _message = "Analiz tamamlanıyor..."; 
      _isAiLoading = true;
    });

    // 1. Standart kayıtlar
    await _apiService.sendGameMetrics(result, _sessionId!, _missCount);
    await _apiService.endSession(_sessionId!);

    // 2. Arka Planda AI Analizi (Sonuç doktora gidecek)
    try {
      final aiResponse = await _apiService.getAiPrediction(
        mri: [1600.0, 0.75, 1.0], // Örnek/Sabit MRI
        clinical: [75.0, 14.0, 2.0, 28.0, 0.0, 1.0], 
        game: [avgReactionTime, accuracy, _missCount.toDouble()],
      );
      if (aiResponse != null) {
        _aiResult = aiResponse['prediction'];
      }
    } catch (e) {
      debugPrint("AI hatası: $e");
    }

    if (!mounted) return;
    setState(() { _isAiLoading = false; });

    // 3. Hastaya sadece teşekkür et
    _showPatientFinishedDialog();
  }

  void _showPatientFinishedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Icon(Icons.check_circle_outline, color: Colors.green, size: 60),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Değerlendirme Tamamlandı", 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 15),
            Text("Verileriniz analiz edilmek üzere güvenli bir şekilde doktorunuza iletilmiştir.",
              textAlign: TextAlign.center),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Dialog'u kapat
                Navigator.pop(context); // Oyun sayfasından çık (Ana Menüye dön)
              },
              child: const Text("Ana Menüye Dön"),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accuracy = _totalClicks == 0 ? 0 : (_successCount / _totalClicks) * 100;

    return Scaffold(
      appBar: AppBar(title: Text("Kullanıcı: ${widget.user.username}")),
      body: GestureDetector(
        onTap: () => _handleInteraction(false),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Skor Tablosu
            Positioned(
              top: 20, left: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Doğruluk: %${accuracy.toStringAsFixed(1)}"),
                    Text("Tıklama: $_totalClicks / $_maxClicks"),
                    Text("Durum: $_message"),
                  ],
                ),
              ),
            ),
            // Hedef Daire
            if (!_isLoadingSession && !_isGameFinished)
              Positioned(
                top: _top, left: _left,
                child: GestureDetector(
                  onTap: () => _handleInteraction(true),
                  child: Container(
                    width: 70, height: 70,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    child: const Center(child: Text("DOKUN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ),
                ),
              ),
            if (_isGameFinished)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}