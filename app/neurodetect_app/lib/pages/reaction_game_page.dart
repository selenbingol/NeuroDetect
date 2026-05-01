import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/test_result.dart';
import '../services/api_service.dart';

class ReactionGamePage extends StatefulWidget {
  final UserModel user;

  const ReactionGamePage({super.key, required this.user});

  @override
  State<ReactionGamePage> createState() => _ReactionGamePageState();
}

class _ReactionGamePageState extends State<ReactionGamePage> {
  final ApiService _apiService = ApiService();
  final Random _random = Random();

  // Klinik Parametreler (Protokol Madde 7)
  static const int _maxRounds = 10;
  static const double _targetSize = 78; 
  static const int _targetVisibleMs = 2000; // 5 sn'den 2 sn'ye düşürüldü

  // Veri Seti ve Sayaçlar (Protokol Madde 3)
  int _currentRound = 0;
  int _tapCount = 0;          // Doğru vuruş
  int _falseStartCount = 0;   // Erken basış
  int _wrongTapCount = 0;     // Yanlış alan
  int _timeoutCount = 0;      // Süre aşımı
  final List<int> _reactionTimes = [];

  // Durum Yönetimi
  int? _sessionId;
  bool _isGameFinished = false;
  bool _isTargetVisible = false;
  bool _isWaitingForTarget = false; 
  bool _isCountdownActive = true;
  int _countdown = 3;
  String _feedbackMessage = ""; // Kullanıcıya geri bildirim mesajı
  
  double _top = 150;
  double _left = 100;
  int _targetShownAt = 0;

  Timer? _countdownTimer;
  Timer? _targetDelayTimer;
  Timer? _targetTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _targetDelayTimer?.cancel();
    _targetTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSession() async {
    final sessionId = await _apiService.startSession(widget.user.userId, "reaction");
    if (!mounted) return;
    setState(() {
      _sessionId = sessionId;
    });
    if (sessionId != null) _runCountdown();
  }

  void _runCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        setState(() => _isCountdownActive = false);
        _prepareNextRound();
      }
    });
  }

  void _prepareNextRound() {
    if (_isGameFinished) return;

    if (_currentRound >= _maxRounds) {
      _finishGame();
      return;
    }

    setState(() {
      _currentRound++;
      _isTargetVisible = false;
      _isWaitingForTarget = true;
      _feedbackMessage = "";
    });

    // Random Delay (1000ms - 2500ms)
    final delay = 1000 + _random.nextInt(1500);
    _targetDelayTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted || _isGameFinished) return;
      _showTarget();
    });
  }

  void _showTarget() {
    final size = MediaQuery.of(context).size;
    final maxTop = (size.height - 300).clamp(100.0, double.infinity);
    final maxLeft = (size.width - 100).clamp(50.0, double.infinity);

    setState(() {
      _isWaitingForTarget = false;
      _isTargetVisible = true;
      _top = 100 + _random.nextDouble() * (maxTop - 100);
      _left = 20 + _random.nextDouble() * (maxLeft - 20);
      _targetShownAt = DateTime.now().millisecondsSinceEpoch;
    });

    // Timeout Timer (Protokol Madde 5 & 6)
    _targetTimeoutTimer = Timer(const Duration(milliseconds: _targetVisibleMs), () {
      if (!mounted || !_isTargetVisible) return;
      _handleEvent(eventType: "timeout");
    });
  }

  // --- MERKEZİ EVENT YÖNETİCİSİ (Protokol Madde 2, 6, 10) ---
  void _handleEvent({required String eventType}) {
    if (_isGameFinished) return;

    _targetDelayTimer?.cancel();
    _targetTimeoutTimer?.cancel();

    setState(() {
      _isTargetVisible = false;
      _isWaitingForTarget = false;

      if (eventType == "tap") {
        _tapCount++;
        final rt = DateTime.now().millisecondsSinceEpoch - _targetShownAt;
        _reactionTimes.add(rt);
        _feedbackMessage = "Correct";
      } else if (eventType == "false_start") {
        _falseStartCount++;
        _feedbackMessage = "Too early";
      } else if (eventType == "wrong_area") {
        _wrongTapCount++;
        _feedbackMessage = "Wrong area";
      } else if (eventType == "timeout") {
        _timeoutCount++;
        _feedbackMessage = "Too slow";
      }
    });

    // Round bitti, kısa bir bekleme ve yeni round (Madde 5)
    Future.delayed(const Duration(milliseconds: 800), _prepareNextRound);
  }

  // Ekranın herhangi bir yerine dokunulduğunda
  void _onScreenTap() {
    if (_isCountdownActive || _isGameFinished) return;

    if (_isWaitingForTarget) {
      _handleEvent(eventType: "false_start"); // Henüz çıkmadan bastı
    } else if (_isTargetVisible) {
      _handleEvent(eventType: "wrong_area");  // Çıktı ama dışarı bastı
    }
  }

  Future<void> _finishGame() async {
    if (_isGameFinished || _sessionId == null) return;
    setState(() => _isGameFinished = true);

    final totalAttempts = _tapCount + _falseStartCount + _wrongTapCount + _timeoutCount;
    final avgRT = _reactionTimes.isEmpty ? 0.0 : _reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length;
    final accuracy = totalAttempts == 0 ? 0.0 : (_tapCount / totalAttempts) * 100;

    // Ek Klinik Metrikler (Protokol Madde 8)
    final tapRate = totalAttempts > 0 ? (_tapCount / totalAttempts) * 100 : 0.0;
    final falseStartRate = totalAttempts > 0 ? (_falseStartCount / totalAttempts) * 100 : 0.0;
    final wrongTapRate = totalAttempts > 0 ? (_wrongTapCount / totalAttempts) * 100 : 0.0;
    final timeoutRate = totalAttempts > 0 ? (_timeoutCount / totalAttempts) * 100 : 0.0;

    // RT Variability (Standart Sapma)
    double rtStd = 0.0;
    if (_reactionTimes.length > 1) {
      final mean = avgRT;
      final variance = _reactionTimes.map((rt) => (rt - mean) * (rt - mean)).reduce((a, b) => a + b) / _reactionTimes.length;
      rtStd = sqrt(variance);
    }

    debugPrint("=== REACTION GAME KLİNİK METRİKLER ===");
    debugPrint("Tap Rate: ${tapRate.toStringAsFixed(1)}%");
    debugPrint("False Start Rate: ${falseStartRate.toStringAsFixed(1)}%");
    debugPrint("Wrong Tap Rate: ${wrongTapRate.toStringAsFixed(1)}%");
    debugPrint("Timeout Rate: ${timeoutRate.toStringAsFixed(1)}%");
    debugPrint("Avg RT (tap only): ${avgRT.toStringAsFixed(0)} ms");
    debugPrint("RT Std: ${rtStd.toStringAsFixed(1)} ms");

    final totalMisses = _wrongTapCount + _timeoutCount;

    final result = TestResult(
      reactionTime: avgRT.round(),
      isSuccess: true,
      accuracy: accuracy,
      score: (_tapCount * 10) - (_falseStartCount * 5) - (_wrongTapCount * 2),
      timestamp: DateTime.now(),

      tapCount: _tapCount,
      missCount: totalMisses,
      falseStartCount: _falseStartCount,
      wrongTapCount: _wrongTapCount,
      timeoutCount: _timeoutCount,
      falseAlarmCount: 0,
      omissionCount: 0,
);

    await _apiService.sendGameMetrics(
  sessionId: _sessionId!,
  score: result.score,
  reactionTimeMs: result.reactionTime,
  accuracyRate: result.accuracy,
  missCount: result.missCount,
  tapCount: result.tapCount,
  falseStartCount: result.falseStartCount,
  wrongTapCount: result.wrongTapCount,
  timeoutCount: result.timeoutCount,
  falseAlarmCount: result.falseAlarmCount,
  omissionCount: result.omissionCount,
);
    await _apiService.endSession(_sessionId!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text("Reaction Task", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: GestureDetector(
        onTap: _onScreenTap, // Tüm ekranı kapsayan ana dinleyici
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            _buildLiveMetrics(),
            
            if (_isCountdownActive)
              Center(child: Text("$_countdown", style: const TextStyle(fontSize: 90, fontWeight: FontWeight.w900, color: Color(0xFF1E6BA8)))),

            if (_isTargetVisible)
              Positioned(
                top: _top,
                left: _left,
                child: GestureDetector(
                  onTap: () => _handleEvent(eventType: "tap"),
                  child: Container(
                    width: _targetSize,
                    height: _targetSize,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: const Center(
                      child: Text(
                        "TAP",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            if (!_isTargetVisible && !_isCountdownActive && !_isGameFinished)
              Center(
                child: Text(
                  _feedbackMessage.isNotEmpty ? _feedbackMessage : "Wait...",
                  style: TextStyle(
                    fontSize: _feedbackMessage.isNotEmpty ? 28 : 20,
                    fontWeight: _feedbackMessage.isNotEmpty ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMetrics() {
    return Positioned(
      top: 10, left: 20, right: 20,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statItem("Round", "$_currentRound/$_maxRounds"),
            _statItem("Tap", "$_tapCount", color: Colors.green),
            _statItem("Wrong", "$_wrongTapCount", color: Colors.orange),
            _statItem("False", "$_falseStartCount", color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, {Color color = Colors.black87}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}