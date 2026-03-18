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

  // Ortalama reaction time için
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
      _message = sessionId != null
          ? "Oturum hazır (ID: $sessionId)"
          : "Oturum başlatılamadı";
    });
  }

  Future<void> _finishGame() async {
    if (_sessionId == null) return;

    final double accuracy =
    _totalClicks == 0 ? 0.0 : (_successCount / _totalClicks) * 100.0;

    final avgReactionTime = _reactionTimes.isEmpty
        ? 0
        : (_reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length)
            .round();

    final result = TestResult(
      reactionTime: avgReactionTime,
      isSuccess: true, // artık özet kayıt olduğu için kritik değil
      accuracy: accuracy,
      score: _successCount * 10,
      timestamp: DateTime.now(),
    );

    final saved = await _apiService.sendGameMetrics(
      result,
      _sessionId!,
      _missCount,
    );

    final ended = await _apiService.endSession(_sessionId!);

    if (!mounted) return;

    setState(() {
      _isGameFinished = true;
      _message = (saved && ended)
          ? "Oyun bitti, veri kaydedildi"
          : "Oyun bitti ama kayıt/kapanışta hata oluştu";
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
          final rt = now - _lastTimestamp;
          _reactionTimes.add(rt);
        }

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

  @override
  Widget build(BuildContext context) {
    final accuracy =
        _totalClicks == 0 ? 0 : (_successCount / _totalClicks) * 100;

    return Scaffold(
      appBar: AppBar(
        title: Text("Welcome ${widget.user.username}"),
      ),
      body: GestureDetector(
        onTap: () => _handleInteraction(false),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Başarılı: $_successCount"),
                    Text("Iskalama: $_missCount"),
                    Text("Doğruluk: %${accuracy.toStringAsFixed(1)}"),
                    Text("Toplam Tıklama: $_totalClicks / $_maxClicks"),
                    Text(_message),
                  ],
                ),
              ),
            ),
            if (!_isLoadingSession && !_isGameFinished)
              Positioned(
                top: _top,
                left: _left,
                child: GestureDetector(
                  onTap: () => _handleInteraction(true),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        "DOKUN",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            if (_isGameFinished)
              const Center(
                child: Text(
                  "Oyun tamamlandı",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}