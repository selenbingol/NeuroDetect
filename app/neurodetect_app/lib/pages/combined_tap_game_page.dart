import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../models/test_result.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';

enum _CombinedPhase { reaction, decision }

class CombinedTapGamePage extends StatefulWidget {
  final UserModel user;
  final BleService? bleService;

  const CombinedTapGamePage({
    super.key,
    required this.user,
    this.bleService,
  });

  @override
  State<CombinedTapGamePage> createState() => _CombinedTapGamePageState();
}

class _CombinedTapGamePageState extends State<CombinedTapGamePage> {
  final ApiService _apiService = ApiService();
  final Random _random = Random();

  static const int _reactionRounds = 5;
  static const int _decisionRounds = 5;
  static const int _totalRounds = _reactionRounds + _decisionRounds;

  static const double _targetSize = 78;
  static const int _stimulusVisibleMs = 2000;

  _CombinedPhase _phase = _CombinedPhase.reaction;

  // session ids
  int? _reactionSessionId;
  int? _decisionSessionId;

  bool _isLoadingSession = true;
  bool _isGameFinished = false;
  bool _isCountdownActive = true;
  int _countdown = 3;

  int _globalRound = 0;
  int _phaseRound = 0;

  // common stimulus state
  bool _isStimulusVisible = false;
  bool _isWaitingForStimulus = false;
  bool _eventHandled = false;
  String _feedbackMessage = "";

  double _top = 150;
  double _left = 100;
  int _stimulusShownAt = 0;

  String? _decisionStimulus; // GREEN / RED
  late final List<String> _decisionSequence;

  Timer? _countdownTimer;
  Timer? _stimulusDelayTimer;
  Timer? _stimulusTimeoutTimer;

  // reaction metrics
  int _reactionTapCount = 0;
  int _reactionFalseStartCount = 0;
  int _reactionWrongTapCount = 0;
  int _reactionTimeoutCount = 0;
  final List<int> _reactionTimes = [];

  // decision metrics
  int _decisionTapCount = 0;
  int _decisionCorrectNoGoCount = 0;
  int _decisionFalseAlarmCount = 0;
  int _decisionOmissionCount = 0;
  int _decisionFalseStartCount = 0;
  final List<int> _decisionReactionTimes = [];

  @override
  void initState() {
    super.initState();
    _decisionSequence = _buildDecisionSequence();
    _startSessions();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _stimulusDelayTimer?.cancel();
    _stimulusTimeoutTimer?.cancel();
    super.dispose();
  }

  List<String> _buildDecisionSequence() {
    final sequence = <String>[
      ...List.filled(3, "GREEN"),
      ...List.filled(2, "RED"),
    ];
    sequence.shuffle(_random);
    return sequence;
  }

  Future<void> _startSessions() async {
    final reactionId =
        await _apiService.startSession(widget.user.userId, "reaction");
    final decisionId =
        await _apiService.startSession(widget.user.userId, "decision");

    if (!mounted) return;

    setState(() {
      _reactionSessionId = reactionId;
      _decisionSessionId = decisionId;
      _isLoadingSession = false;
    });

    if (reactionId != null && decisionId != null) {
      _runCountdown();
    }
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

    if (_globalRound >= _totalRounds) {
      _finishCombinedGame();
      return;
    }

    if (_globalRound < _reactionRounds) {
      _phase = _CombinedPhase.reaction;
      _phaseRound = _globalRound + 1;
    } else {
      _phase = _CombinedPhase.decision;
      _phaseRound = (_globalRound - _reactionRounds) + 1;
    }

    setState(() {
      _globalRound++;
      _isStimulusVisible = false;
      _isWaitingForStimulus = true;
      _eventHandled = false;
      _feedbackMessage = "";
      _decisionStimulus = null;
    });

    final delay = 1000 + _random.nextInt(1500);
    _stimulusDelayTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted || _isGameFinished) return;
      _showStimulus();
    });
  }

  void _showStimulus() {
    final size = MediaQuery.of(context).size;
    final maxTop = (size.height - 320).clamp(100.0, double.infinity);
    final maxLeft = (size.width - 120).clamp(50.0, double.infinity);

    setState(() {
      _isWaitingForStimulus = false;
      _isStimulusVisible = true;
      _top = 110 + _random.nextDouble() * (maxTop - 110);
      _left = 20 + _random.nextDouble() * (maxLeft - 20);
      _stimulusShownAt = DateTime.now().millisecondsSinceEpoch;

      if (_phase == _CombinedPhase.decision) {
        _decisionStimulus = _decisionSequence[_phaseRound - 1];
      }
    });

    _stimulusTimeoutTimer =
        Timer(const Duration(milliseconds: _stimulusVisibleMs), () {
      if (!mounted || _eventHandled) return;

      if (_phase == _CombinedPhase.reaction) {
        _handleReactionEvent(eventType: "timeout");
      } else {
        if (_decisionStimulus == "GREEN") {
          _handleDecisionEvent(eventType: "omission");
        } else {
          _handleDecisionEvent(eventType: "correct_nogo");
        }
      }
    });
  }

  void _handleScreenTap() {
    if (_isCountdownActive || _isGameFinished || _eventHandled) return;

    if (_phase == _CombinedPhase.reaction) {
      if (_isWaitingForStimulus) {
        _handleReactionEvent(eventType: "false_start");
      } else if (_isStimulusVisible) {
        _handleReactionEvent(eventType: "wrong_area");
      }
    } else {
      if (_isWaitingForStimulus) {
        _handleDecisionEvent(eventType: "false_start");
      } else if (_isStimulusVisible) {
        if (_decisionStimulus == "GREEN") {
          _handleDecisionEvent(eventType: "tap");
        } else {
          _handleDecisionEvent(eventType: "false_alarm");
        }
      }
    }
  }

  void _handleReactionTargetTap() {
    if (_phase != _CombinedPhase.reaction || _eventHandled) return;
    _handleReactionEvent(eventType: "tap");
  }

  void _handleReactionEvent({required String eventType}) {
    if (_isGameFinished || _eventHandled) return;
    _eventHandled = true;

    _stimulusDelayTimer?.cancel();
    _stimulusTimeoutTimer?.cancel();

    setState(() {
      _isStimulusVisible = false;
      _isWaitingForStimulus = false;

      if (eventType == "tap") {
        _reactionTapCount++;
        final rt = DateTime.now().millisecondsSinceEpoch - _stimulusShownAt;
        _reactionTimes.add(rt);
        _feedbackMessage = "Correct";
      } else if (eventType == "false_start") {
        _reactionFalseStartCount++;
        _feedbackMessage = "Too early";
      } else if (eventType == "wrong_area") {
        _reactionWrongTapCount++;
        _feedbackMessage = "Wrong area";
      } else if (eventType == "timeout") {
        _reactionTimeoutCount++;
        _feedbackMessage = "Too slow";
      }
    });

    Future.delayed(const Duration(milliseconds: 800), _prepareNextRound);
  }

  void _handleDecisionEvent({required String eventType}) {
    if (_isGameFinished || _eventHandled) return;
    _eventHandled = true;

    _stimulusDelayTimer?.cancel();
    _stimulusTimeoutTimer?.cancel();

    setState(() {
      if (eventType == "tap") {
        _decisionTapCount++;
        _decisionReactionTimes
            .add(DateTime.now().millisecondsSinceEpoch - _stimulusShownAt);
        _feedbackMessage = "Correct";
      } else if (eventType == "false_alarm") {
        _decisionFalseAlarmCount++;
        _feedbackMessage = "Do not tap red";
      } else if (eventType == "omission") {
        _decisionOmissionCount++;
        _feedbackMessage = "Too slow";
      } else if (eventType == "correct_nogo") {
        _decisionCorrectNoGoCount++;
        _feedbackMessage = "Good inhibition";
      } else if (eventType == "false_start") {
        _decisionFalseStartCount++;
        _feedbackMessage = "Too early";
      }

      _isStimulusVisible = false;
      _isWaitingForStimulus = false;
      _decisionStimulus = null;
    });

    Future.delayed(const Duration(milliseconds: 800), _prepareNextRound);
  }

  Future<void> _finishCombinedGame() async {
    if (_isGameFinished) return;
    setState(() => _isGameFinished = true);

    if (_reactionSessionId != null) {
      final reactionAttempts = _reactionTapCount +
          _reactionFalseStartCount +
          _reactionWrongTapCount +
          _reactionTimeoutCount;

      final reactionAvgRT = _reactionTimes.isEmpty
          ? 0.0
          : _reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length;

      final reactionAccuracy = reactionAttempts == 0
          ? 0.0
          : (_reactionTapCount / reactionAttempts) * 100;

      final reactionMisses = _reactionWrongTapCount + _reactionTimeoutCount;

      final reactionResult = TestResult(
        reactionTime: reactionAvgRT.round(),
        isSuccess: true,
        accuracy: reactionAccuracy,
        score: (_reactionTapCount * 10) -
            (_reactionFalseStartCount * 5) -
            (_reactionWrongTapCount * 2),
        timestamp: DateTime.now(),
        tapCount: _reactionTapCount,
        missCount: reactionMisses,
        falseStartCount: _reactionFalseStartCount,
        wrongTapCount: _reactionWrongTapCount,
        timeoutCount: _reactionTimeoutCount,
        falseAlarmCount: 0,
        omissionCount: 0,
      );

      await _apiService.sendGameMetrics(
        sessionId: _reactionSessionId!,
        score: reactionResult.score,
        reactionTimeMs: reactionResult.reactionTime,
        accuracyRate: reactionResult.accuracy,
        missCount: reactionResult.missCount,
        tapCount: reactionResult.tapCount,
        falseStartCount: reactionResult.falseStartCount,
        wrongTapCount: reactionResult.wrongTapCount,
        timeoutCount: reactionResult.timeoutCount,
        falseAlarmCount: reactionResult.falseAlarmCount,
        omissionCount: reactionResult.omissionCount,
      );

      await _apiService.endSession(_reactionSessionId!);
    }

    if (_decisionSessionId != null) {
      final decisionCorrect = _decisionTapCount + _decisionCorrectNoGoCount;
      final decisionAttempts = _decisionTapCount +
          _decisionCorrectNoGoCount +
          _decisionFalseAlarmCount +
          _decisionOmissionCount +
          _decisionFalseStartCount;

      final decisionAccuracy = decisionAttempts == 0
          ? 0.0
          : (decisionCorrect / decisionAttempts) * 100;

      final decisionAvgRT = _decisionReactionTimes.isEmpty
          ? 0.0
          : _decisionReactionTimes.reduce((a, b) => a + b) /
              _decisionReactionTimes.length;

      final decisionMisses =
          _decisionFalseAlarmCount + _decisionOmissionCount + _decisionFalseStartCount;

      final decisionScore = (decisionCorrect * 10) -
          (_decisionFalseAlarmCount * 15) -
          (_decisionFalseStartCount * 5) -
          (_decisionOmissionCount * 2);

      final decisionResult = TestResult(
        reactionTime: decisionAvgRT.round(),
        isSuccess: true,
        accuracy: decisionAccuracy,
        score: decisionScore,
        timestamp: DateTime.now(),
        tapCount: _decisionTapCount + _decisionCorrectNoGoCount,
        missCount: decisionMisses,
        falseStartCount: _decisionFalseStartCount,
        wrongTapCount: 0,
        timeoutCount: 0,
        falseAlarmCount: _decisionFalseAlarmCount,
        omissionCount: _decisionOmissionCount,
      );

      await _apiService.sendGameMetrics(
        sessionId: _decisionSessionId!,
        score: decisionResult.score,
        reactionTimeMs: decisionResult.reactionTime,
        accuracyRate: decisionResult.accuracy,
        missCount: decisionResult.missCount,
        tapCount: decisionResult.tapCount,
        falseStartCount: decisionResult.falseStartCount,
        wrongTapCount: decisionResult.wrongTapCount,
        timeoutCount: decisionResult.timeoutCount,
        falseAlarmCount: decisionResult.falseAlarmCount,
        omissionCount: decisionResult.omissionCount,
      );

      await _apiService.endSession(_decisionSessionId!);

      try {
        await _apiService.getAiPrediction(
          mri: [1600.0, 0.75, 1.0],
          clinical: [75.0, 14.0, 2.0, 28.0, 0.0, 1.0],
          game: [
            decisionAvgRT,
            decisionAccuracy,
            decisionMisses.toDouble(),
          ],
        );
      } catch (e) {
        debugPrint("AI error: $e");
      }
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  String _phaseTitle() {
    return _phase == _CombinedPhase.reaction
        ? "Reaction Block"
        : "Decision Block";
  }

  String _phaseInstruction() {
    if (_feedbackMessage.isNotEmpty) return _feedbackMessage;

    if (_phase == _CombinedPhase.reaction) {
      return _isStimulusVisible ? "" : "Wait for the target";
    } else {
      return _isStimulusVisible ? "" : "Wait for the next signal";
    }
  }

  Color _decisionColor() {
    if (_decisionStimulus == "GREEN") return Colors.greenAccent.shade700;
    if (_decisionStimulus == "RED") return Colors.redAccent.shade700;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final reactionAccuracy = (_reactionTapCount +
                _reactionFalseStartCount +
                _reactionWrongTapCount +
                _reactionTimeoutCount) ==
            0
        ? 0.0
        : (_reactionTapCount /
                (_reactionTapCount +
                    _reactionFalseStartCount +
                    _reactionWrongTapCount +
                    _reactionTimeoutCount)) *
            100;

    final decisionDenom = _decisionTapCount +
        _decisionCorrectNoGoCount +
        _decisionFalseAlarmCount +
        _decisionOmissionCount +
        _decisionFalseStartCount;

    final decisionAccuracy = decisionDenom == 0
        ? 0.0
        : ((_decisionTapCount + _decisionCorrectNoGoCount) / decisionDenom) *
            100;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: _isLoadingSession
            ? const Center(child: CircularProgressIndicator())
            : GestureDetector(
                onTap: _handleScreenTap,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          _buildTopPanel(reactionAccuracy, decisionAccuracy),
                          const SizedBox(height: 18),
                          Expanded(
                            child: _buildTaskArea(),
                          ),
                        ],
                      ),
                    ),
                    if (_isCountdownActive)
                      Center(
                        child: Text(
                          "$_countdown",
                          style: const TextStyle(
                            fontSize: 90,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E6BA8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTopPanel(double reactionAccuracy, double decisionAccuracy) {
    final overallProgress = _globalRound == 0 ? 0 : _globalRound;
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
                value: "$overallProgress / $_totalRounds",
              ),
              const SizedBox(width: 12),
              _buildMetricCard(
                icon: Icons.layers_outlined,
                title: "Phase",
                value: _phaseTitle(),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          if (!_isStimulusVisible && !_isCountdownActive && !_isGameFinished)
            Center(
              child: Text(
                _phaseInstruction(),
                style: TextStyle(
                  fontSize: _feedbackMessage.isNotEmpty ? 28 : 22,
                  fontWeight: _feedbackMessage.isNotEmpty
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: const Color(0xFF1C2430),
                ),
              ),
            ),
          if (_phase == _CombinedPhase.reaction && _isStimulusVisible)
            Positioned(
              top: _top,
              left: _left,
              child: GestureDetector(
                onTap: _handleReactionTargetTap,
                child: Container(
                  width: _targetSize,
                  height: _targetSize,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
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
          if (_phase == _CombinedPhase.decision && _isStimulusVisible)
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: _decisionColor(),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 15),
                  ],
                ),
                child: Center(
                  child: Text(
                    _decisionStimulus == "GREEN" ? "TAP" : "WAIT",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
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