import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/test_result.dart';
import '../services/api_service.dart';

class DecisionGamePage extends StatefulWidget {
  final UserModel user;

  const DecisionGamePage({super.key, required this.user});

  @override
  State<DecisionGamePage> createState() => _DecisionGamePageState();
}

class _DecisionGamePageState extends State<DecisionGamePage> {
  final ApiService _apiService = ApiService();
  final Random _random = Random();

  static const int _maxRounds = 10;

  int? _sessionId;
  bool _isLoadingSession = true;
  bool _isGameFinished = false;
  bool _isAiLoading = false;

  String _message = "Session is starting...";
  int _currentRound = 0;
  int _correctCount = 0;
  int _missCount = 0;
  int _falseTapCount = 0;

  String? _currentStimulus; // "GREEN" or "RED"
  int _stimulusShownAt = 0;
  bool _awaitingResponse = false;
  Timer? _roundTimer;

  final List<int> _reactionTimes = [];

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _roundTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSession() async {
    final sessionId = await _apiService.startSession(widget.user.userId);

    if (!mounted) return;

    setState(() {
      _sessionId = sessionId;
      _isLoadingSession = false;
      _message = sessionId != null ? "Session ready" : "Connection error";
    });

    if (sessionId != null) {
      Future.delayed(const Duration(milliseconds: 900), _startNextRound);
    }
  }

  bool _isGoStimulus(String stimulus) {
    return stimulus == "GREEN";
  }

  void _startNextRound() {
    if (_isGameFinished) return;

    if (_currentRound >= _maxRounds) {
      _finishGame();
      return;
    }

    _roundTimer?.cancel();

    final stimulus = _random.nextBool() ? "GREEN" : "RED";

    setState(() {
      _currentRound++;
      _currentStimulus = stimulus;
      _awaitingResponse = true;
      _stimulusShownAt = DateTime.now().millisecondsSinceEpoch;
      _message = stimulus == "GREEN"
          ? "Tap the screen"
          : "Do not tap the screen";
    });

    _roundTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!_awaitingResponse || !mounted) return;

      final isGo = _isGoStimulus(_currentStimulus!);

      setState(() {
        if (isGo) {
          _missCount++;
        } else {
          _correctCount++;
        }

        _awaitingResponse = false;
        _currentStimulus = null;
        _message = "Get ready for the next round...";
      });

      Future.delayed(const Duration(milliseconds: 800), _startNextRound);
    });
  }

  void _handleTap() {
    if (_isLoadingSession || _isGameFinished || !_awaitingResponse) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final reactionTime = now - _stimulusShownAt;
    final isGo = _isGoStimulus(_currentStimulus!);

    _roundTimer?.cancel();

    setState(() {
      if (isGo) {
        _correctCount++;
        _reactionTimes.add(reactionTime);
      } else {
        _falseTapCount++;
      }

      _awaitingResponse = false;
      _currentStimulus = null;
      _message = "Get ready for the next round...";
    });

    Future.delayed(const Duration(milliseconds: 800), _startNextRound);
  }

  Future<void> _finishGame() async {
    if (_isGameFinished || _sessionId == null) return;

    final totalRounds = _maxRounds;
    final accuracy =
        totalRounds == 0 ? 0.0 : (_correctCount / totalRounds) * 100;

    final avgReactionTime = _reactionTimes.isEmpty
        ? 0.0
        : _reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length;

    final score = (_correctCount * 10) - (_falseTapCount * 5);
    final totalMisses = _missCount + _falseTapCount;

    final result = TestResult(
      reactionTime: avgReactionTime.round(),
      isSuccess: true,
      accuracy: accuracy,
      score: score < 0 ? 0 : score,
      timestamp: DateTime.now(),
    );

    setState(() {
      _isGameFinished = true;
      _isAiLoading = true;
      _message = "Finalising assessment...";
    });

    await _apiService.sendGameMetrics(result, _sessionId!, totalMisses);
    await _apiService.endSession(_sessionId!);

    try {
      await _apiService.getAiPrediction(
        mri: [1600.0, 0.75, 1.0],
        clinical: [75.0, 14.0, 2.0, 28.0, 0.0, 1.0],
        game: [
          avgReactionTime,
          accuracy,
          totalMisses.toDouble(),
        ],
      );
    } catch (e) {
      debugPrint("AI error: $e");
    }

    if (!mounted) return;

    setState(() {
      _isAiLoading = false;
    });

    Navigator.pop(context);
  }

  Color _stimulusColor() {
    if (_currentStimulus == "GREEN") return Colors.green;
    return Colors.redAccent;
  }

  String _stimulusText() {
    if (_currentStimulus == "GREEN") return "TAP";
    return "WAIT";
  }

  @override
  Widget build(BuildContext context) {
    final accuracy = _currentRound == 0
        ? 0.0
        : (_correctCount / _currentRound) * 100;

    return Scaffold(
      appBar: AppBar(
        title: Text("Decision Task - ${widget.user.username}"),
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Rule: Tap GREEN, do not tap RED.",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E5F92),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("Round: $_currentRound / $_maxRounds"),
                    Text("Accuracy: %${accuracy.toStringAsFixed(1)}"),
                    Text("Correct Responses: $_correctCount"),
                    Text("Misses / False Taps: ${_missCount + _falseTapCount}"),
                    Text("Status: $_message"),
                  ],
                ),
              ),
            ),

            if (_isLoadingSession)
              const Center(child: CircularProgressIndicator()),

            if (!_isLoadingSession && !_isGameFinished && _currentStimulus != null)
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    color: _stimulusColor(),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _stimulusText(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),

            if (_isGameFinished || _isAiLoading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}