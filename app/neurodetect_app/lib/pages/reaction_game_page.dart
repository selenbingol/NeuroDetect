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

  static const int _maxRounds = 10;
  static const double _targetSize = 78;
  static const double _taskAreaHeight = 430;
  static const int _targetVisibleMs = 5000;

  int? _sessionId;
  bool _isLoadingSession = true;
  bool _isGameFinished = false;
  bool _isAiLoading = false;

  int _currentRound = 0;
  int _successCount = 0;
  int _missCount = 0;
  int _falseStartCount = 0;

  double _top = 180;
  double _left = 120;

  bool _isTargetVisible = false;
  bool _isWaitingForTarget = false;
  bool _isCountdownActive = true;

  String _message = "Preparing session...";
  int _countdown = 3;
  int _targetShownAt = 0;

  Timer? _countdownTimer;
  Timer? _targetDelayTimer;
  Timer? _targetTimeoutTimer;

  final List<int> _reactionTimes = [];

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
    final sessionId = await _apiService.startSession(widget.user.userId);
    if (!mounted) return;

    setState(() {
      _sessionId = sessionId;
      _isLoadingSession = false;
      _message = sessionId != null ? "Session ready" : "Connection error";
    });

    if (sessionId != null) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() {
      _isCountdownActive = true;
      _countdown = 3;
      _message = "Get ready...";
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        setState(() {
          _isCountdownActive = false;
          _message = "Wait for the target";
        });
        _startNextRound();
      }
    });
  }

  void _startNextRound() {
    if (_isGameFinished) return;

    if (_currentRound >= _maxRounds) {
      _finishGame();
      return;
    }

    _targetDelayTimer?.cancel();
    _targetTimeoutTimer?.cancel();

    final maxTop = _taskAreaHeight - _targetSize - 24;
    final maxLeft =
        (MediaQuery.of(context).size.width - 40 - _targetSize).clamp(120.0, double.infinity);

    setState(() {
      _currentRound++;
      _isTargetVisible = false;
      _isWaitingForTarget = true;
      _message = "Wait...";
      _top = 20 + _random.nextDouble() * (maxTop - 20);
      _left = 20 + _random.nextDouble() * (maxLeft - 20);
    });

    final delay = 900 + _random.nextInt(1600);

    _targetDelayTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted || _isGameFinished) return;

      setState(() {
        _isTargetVisible = true;
        _isWaitingForTarget = false;
        _targetShownAt = DateTime.now().millisecondsSinceEpoch;
        _message = "Tap now";
      });

      _startTargetTimeout();
    });
  }

  void _startTargetTimeout() {
    _targetTimeoutTimer?.cancel();
    _targetTimeoutTimer = Timer(const Duration(milliseconds: _targetVisibleMs), () {
      if (!mounted || !_isTargetVisible || _isGameFinished) return;

      setState(() {
        _isTargetVisible = false;
        _missCount++;
        _message = "Too late";
      });

      Future.delayed(const Duration(milliseconds: 700), _startNextRound);
    });
  }

  void _handleScreenTap() {
    if (_isLoadingSession || _isGameFinished || _isCountdownActive) return;

    if (_isWaitingForTarget && !_isTargetVisible) {
      _targetDelayTimer?.cancel();
      _targetTimeoutTimer?.cancel();

      setState(() {
        _falseStartCount++;
        _missCount++;
        _message = "Too early";
      });

      Future.delayed(const Duration(milliseconds: 700), _startNextRound);
      return;
    }

    if (_isTargetVisible) {
      _handleTargetHit();
      return;
    }

    setState(() {
      _message = "Wait for the target";
    });
  }

  void _handleTargetHit() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _targetTimeoutTimer?.cancel();

    setState(() {
      _successCount++;
      _isTargetVisible = false;
      _message = "Good";
      if (_targetShownAt != 0) {
        _reactionTimes.add(now - _targetShownAt);
      }
    });

    Future.delayed(const Duration(milliseconds: 600), _startNextRound);
  }

  Future<void> _finishGame() async {
    if (_sessionId == null || _isGameFinished) return;

    final totalAttempts = _maxRounds;
    final accuracy =
        totalAttempts == 0 ? 0.0 : (_successCount / totalAttempts) * 100;

    final avgReactionTime = _reactionTimes.isEmpty
        ? 0.0
        : _reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length;

    final score = (_successCount * 10) - (_falseStartCount * 2);

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

    await _apiService.sendGameMetrics(result, _sessionId!, _missCount);
    await _apiService.endSession(_sessionId!);

    try {
      await _apiService.getAiPrediction(
        mri: [1600.0, 0.75, 1.0],
        clinical: [75.0, 14.0, 2.0, 28.0, 0.0, 1.0],
        game: [avgReactionTime, accuracy, _missCount.toDouble()],
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

  String _reactionText() {
    if (_reactionTimes.isEmpty) return "-";
    final avg =
        _reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length;
    return "${avg.toStringAsFixed(0)} ms";
  }

  @override
  Widget build(BuildContext context) {
    final accuracy = _currentRound == 0
        ? 0.0
        : (_successCount / _currentRound) * 100;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Reaction Task - ${widget.user.username}",
          style: const TextStyle(
            color: Color(0xFF1C2430),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1C2430)),
      ),
      body: GestureDetector(
        onTap: _handleScreenTap,
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildTopPanel(accuracy),
                    const SizedBox(height: 18),
                    _buildTaskArea(),
                  ],
                ),
              ),
              if (_isLoadingSession || _isAiLoading || _isGameFinished)
                Container(
                  color: Colors.black.withOpacity(0.08),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopPanel(double accuracy) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildMetricCard(
                icon: Icons.flag_outlined,
                title: "Round",
                value: "$_currentRound / $_maxRounds",
              ),
              const SizedBox(width: 12),
              _buildMetricCard(
                icon: Icons.speed_outlined,
                title: "Avg Reaction",
                value: _reactionText(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetricCard(
                icon: Icons.check_circle_outline,
                title: "Accuracy",
                value: "%${accuracy.toStringAsFixed(1)}",
              ),
              const SizedBox(width: 12),
              _buildMetricCard(
                icon: Icons.warning_amber_rounded,
                title: "Misses",
                value: "$_missCount",
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF1E6BA8),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF1E6BA8), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C2430),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskArea() {
    return Container(
      height: _taskAreaHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDFEFF), Color(0xFFF3F7FB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Stack(
        children: [
          if (_isCountdownActive)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Starting in",
                    style: TextStyle(
                      fontSize: 22,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "$_countdown",
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E6BA8),
                    ),
                  ),
                ],
              ),
            ),

          if (!_isCountdownActive && !_isTargetVisible && !_isGameFinished)
            const Center(
              child: Text(
                "Wait for the target",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),

          if (_isTargetVisible && !_isGameFinished)
            Positioned(
              top: _top,
              left: _left,
              child: GestureDetector(
                onTap: _handleTargetHit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: _targetSize,
                  height: _targetSize,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      "TAP",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}