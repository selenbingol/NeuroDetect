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

  static const double _targetSize = 84;
  static const double _decisionSignalSize = 240;
  static const int _stimulusVisibleMs = 2000;

  _CombinedPhase _phase = _CombinedPhase.reaction;

  int? _reactionSessionId;
  int? _decisionSessionId;

  bool _isLoadingSession = true;
  bool _isGameFinished = false;
  bool _isCountdownActive = true;
  bool _stimulusPressedVisual = false;

  int _countdown = 3;
  int _globalRound = 0;
  int _phaseRound = 0;

  bool _isStimulusVisible = false;
  bool _isWaitingForStimulus = false;
  bool _eventHandled = false;
  String _feedbackMessage = "";

  double _top = 150;
  double _left = 100;
  int _stimulusShownAt = 0;

  double _taskAreaWidth = 0;
  double _taskAreaHeight = 0;

  String? _decisionStimulus;
  late final List<String> _decisionSequence;

  Timer? _countdownTimer;
  Timer? _stimulusDelayTimer;
  Timer? _stimulusTimeoutTimer;

  int _reactionTapCount = 0;
  int _reactionFalseStartCount = 0;
  int _reactionWrongTapCount = 0;
  int _reactionTimeoutCount = 0;
  final List<int> _reactionTimes = [];

  int _decisionTapCount = 0;
  int _decisionCorrectNoGoCount = 0;
  int _decisionFalseAlarmCount = 0;
  int _decisionOmissionCount = 0;
  int _decisionFalseStartCount = 0;
  final List<int> _decisionReactionTimes = [];

  StreamSubscription<SensorData>? _sensorSub;
  final List<SensorData> _reactionSensorSamples = [];
  final List<SensorData> _decisionSensorSamples = [];

  @override
  void initState() {
    super.initState();
    _decisionSequence = _buildDecisionSequence();
    _startSessions();
    _startSensorTracking();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _stimulusDelayTimer?.cancel();
    _stimulusTimeoutTimer?.cancel();
    _sensorSub?.cancel();
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

  void _startSensorTracking() {
    final bleService = widget.bleService;
    if (bleService == null) return;

    _sensorSub = bleService.sensorDataStream.listen((data) {
      if (_isGameFinished) return;

      if (_phase == _CombinedPhase.reaction) {
        _reactionSensorSamples.add(data);
      } else {
        _decisionSensorSamples.add(data);
      }
    });
  }

  double _normalizeTremorIndex(double rawVariability) {
    const double stableBaseline = 0.10;
    const double highTremorReference = 60.0;

    if (rawVariability <= stableBaseline) {
      return 0.0;
    }

    final normalized =
        ((rawVariability - stableBaseline) /
                (highTremorReference - stableBaseline)) *
            100;

    return normalized.clamp(0.0, 100.0).toDouble();
  }

  Map<String, double?> _calculateSensorMetrics(List<SensorData> samples) {
    if (samples.isEmpty) {
      return {
        "avgMotion": null,
        "avgGyro": null,
        "tremorIndex": null,
        "movementVariability": null,
      };
    }

    final avgMotion =
        samples.map((e) => e.motion).reduce((a, b) => a + b) / samples.length;

    final avgGyro =
        samples.map((e) => e.gyro).reduce((a, b) => a + b) / samples.length;

    double variance = 0;
    if (samples.length > 1) {
      variance = samples
              .map((e) => (e.gyro - avgGyro) * (e.gyro - avgGyro))
              .reduce((a, b) => a + b) /
          samples.length;
    }

    final rawVariability = sqrt(variance);
    final tremorIndex = _normalizeTremorIndex(rawVariability);

    return {
      "avgMotion": avgMotion,
      "avgGyro": avgGyro,
      "tremorIndex": tremorIndex,
      "movementVariability": rawVariability,
    };
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
      _stimulusPressedVisual = false;
    });

    final delay = 1000 + _random.nextInt(1500);
    _stimulusDelayTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted || _isGameFinished) return;
      _showStimulus();
    });
  }

  void _showStimulus() {
    final screenSize = MediaQuery.of(context).size;
    final areaWidth = _taskAreaWidth > 0 ? _taskAreaWidth : screenSize.width - 40;
    final areaHeight =
        _taskAreaHeight > 0 ? _taskAreaHeight : screenSize.height - 240;

    const double leftPadding = 24;
    const double rightPadding = 24;
    const double topPadding = 130;
    const double bottomPadding = 24;

    final availableX =
        max(0.0, areaWidth - _targetSize - leftPadding - rightPadding);
    final availableY =
        max(0.0, areaHeight - _targetSize - topPadding - bottomPadding);

    setState(() {
      _isWaitingForStimulus = false;
      _isStimulusVisible = true;
      _stimulusPressedVisual = false;

      _left = leftPadding + (_random.nextDouble() * availableX);
      _top = topPadding + (_random.nextDouble() * availableY);

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
    if (!_isStimulusVisible) return;

    _eventHandled = true;

    setState(() {
      _stimulusPressedVisual = true;
    });

    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || _isGameFinished) return;
      _handleReactionEvent(eventType: "tap", alreadyHandled: true);
    });
  }

  void _handleDecisionSignalTap() {
    if (_phase != _CombinedPhase.decision || _eventHandled) return;
    if (!_isStimulusVisible) return;

    _eventHandled = true;

    setState(() {
      _stimulusPressedVisual = true;
    });

    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || _isGameFinished) return;

      if (_decisionStimulus == "GREEN") {
        _handleDecisionEvent(eventType: "tap", alreadyHandled: true);
      } else {
        _handleDecisionEvent(eventType: "false_alarm", alreadyHandled: true);
      }
    });
  }

  void _handleReactionEvent({
    required String eventType,
    bool alreadyHandled = false,
  }) {
    if (_isGameFinished || (_eventHandled && !alreadyHandled)) return;
    _eventHandled = true;

    _stimulusDelayTimer?.cancel();
    _stimulusTimeoutTimer?.cancel();

    setState(() {
      _isStimulusVisible = false;
      _isWaitingForStimulus = false;
      _stimulusPressedVisual = false;

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

  void _handleDecisionEvent({
    required String eventType,
    bool alreadyHandled = false,
  }) {
    if (_isGameFinished || (_eventHandled && !alreadyHandled)) return;
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
      _stimulusPressedVisual = false;
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

      final rxMetrics = _calculateSensorMetrics(_reactionSensorSamples);
      await _apiService.saveSensorMetrics(
        sessionId: _reactionSessionId!,
        avgMotion: rxMetrics["avgMotion"],
        avgGyro: rxMetrics["avgGyro"],
        tremorIndex: rxMetrics["tremorIndex"],
        movementVariability: rxMetrics["movementVariability"],
        pathCorrectionCount: 0,
        sampleCount: _reactionSensorSamples.length,
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

      final decisionMisses = _decisionFalseAlarmCount +
          _decisionOmissionCount +
          _decisionFalseStartCount;

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

      final decMetrics = _calculateSensorMetrics(_decisionSensorSamples);
      await _apiService.saveSensorMetrics(
        sessionId: _decisionSessionId!,
        avgMotion: decMetrics["avgMotion"],
        avgGyro: decMetrics["avgGyro"],
        tremorIndex: decMetrics["tremorIndex"],
        movementVariability: decMetrics["movementVariability"],
        pathCorrectionCount: 0,
        sampleCount: _decisionSensorSamples.length,
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

  String _phaseSubtitle() {
    return _phase == _CombinedPhase.reaction
        ? "Tap only when the target appears."
        : "Tap green signals. Do not tap red signals.";
  }

  String _phaseInstruction() {
    if (_feedbackMessage.isNotEmpty) return _feedbackMessage;

    if (_phase == _CombinedPhase.reaction) {
      return _isStimulusVisible ? "" : "Wait for the target";
    } else {
      return _isStimulusVisible ? "" : "Wait for the next signal";
    }
  }

  Color _feedbackColor() {
    if (_feedbackMessage == "Correct" ||
        _feedbackMessage == "Good inhibition") {
      return const Color(0xFF16A34A);
    }

    if (_feedbackMessage == "Too early" ||
        _feedbackMessage == "Wrong area" ||
        _feedbackMessage == "Too slow" ||
        _feedbackMessage == "Do not tap red") {
      return const Color(0xFFDC2626);
    }

    return const Color(0xFF1C2430);
  }

  IconData _feedbackIcon() {
    if (_feedbackMessage == "Correct" ||
        _feedbackMessage == "Good inhibition") {
      return Icons.check_circle_rounded;
    }

    if (_feedbackMessage == "Too early" ||
        _feedbackMessage == "Wrong area" ||
        _feedbackMessage == "Too slow" ||
        _feedbackMessage == "Do not tap red") {
      return Icons.error_rounded;
    }

    return Icons.info_rounded;
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
            ? _buildLoadingView()
            : GestureDetector(
                onTap: _handleScreenTap,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Column(
                        children: [
                          _buildHeaderPanel(reactionAccuracy, decisionAccuracy),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _buildTaskArea(),
                            ),
                        ],
                      ),
                    ),
                    if (_isCountdownActive) _buildCountdownOverlay(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF1E6BA8),
            ),
            SizedBox(height: 18),
            Text(
              "Preparing assessment...",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1C2430),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Please wait while the clinical task session is initialized.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderPanel(double reactionAccuracy, double decisionAccuracy) {
  final overallProgress = _globalRound == 0 ? 0 : _globalRound;
  final progressValue = overallProgress / _totalRounds;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F4C81), Color(0xFF1E6BA8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.psychology_alt_rounded,
                color: Colors.white,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Combined Tap Task",
                    style: TextStyle(
                      color: Color(0xFF1C2430),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "${widget.user.username} · Cognitive-motor assessment",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _buildPhaseBadge(),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: LinearProgressIndicator(
            value: progressValue,
            minHeight: 6,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFF1E6BA8),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildMetricCard(
              icon: Icons.flag_outlined,
              title: "Round",
              value: "$overallProgress / $_totalRounds",
            ),
            const SizedBox(width: 8),
            _buildMetricCard(
              icon: Icons.layers_outlined,
              title: "Block",
              value: _phase == _CombinedPhase.reaction ? "Reaction" : "Go / No-Go",
            ),
            const SizedBox(width: 8),
            _buildMetricCard(
              icon: Icons.insights_rounded,
              title: "Block Round",
              value: "$_phaseRound / 5",
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildPhaseBadge() {
  final isReaction = _phase == _CombinedPhase.reaction;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: isReaction ? const Color(0xFFE0F2FE) : const Color(0xFFF3E8FF),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: isReaction ? const Color(0xFFBAE6FD) : const Color(0xFFE9D5FF),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isReaction ? Icons.touch_app_rounded : Icons.traffic_rounded,
          size: 15,
          color: isReaction ? const Color(0xFF0369A1) : const Color(0xFF7E22CE),
        ),
        const SizedBox(width: 5),
        Text(
          isReaction ? "Reaction" : "Go / No-Go",
          style: TextStyle(
            color:
                isReaction ? const Color(0xFF0369A1) : const Color(0xFF7E22CE),
            fontSize: 12,
            fontWeight: FontWeight.w800,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF1E6BA8),
            size: 17,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.8,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        _taskAreaWidth = constraints.maxWidth;
        _taskAreaHeight = constraints.maxHeight;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFDFEFF), Color(0xFFF3F7FB)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: _buildInstructionBanner(),
              ),
              if (!_isStimulusVisible && !_isCountdownActive && !_isGameFinished)
                Center(
                  child: _buildCenterInstruction(),
                ),
              if (_phase == _CombinedPhase.reaction && _isStimulusVisible)
                Positioned(
                  top: _top,
                  left: _left,
                  child: GestureDetector(
                    onTap: _handleReactionTargetTap,
                    behavior: HitTestBehavior.opaque,
                    child: _buildReactionTarget(),
                  ),
                ),
              if (_phase == _CombinedPhase.decision && _isStimulusVisible)
                Center(
                  child: GestureDetector(
                    onTap: _handleDecisionSignalTap,
                    behavior: HitTestBehavior.opaque,
                    child: _buildDecisionSignal(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInstructionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(
            _phase == _CombinedPhase.reaction
                ? Icons.touch_app_rounded
                : Icons.rule_rounded,
            color: const Color(0xFF1E6BA8),
            size: 23,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _phaseSubtitle(),
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterInstruction() {
    if (_feedbackMessage.isNotEmpty) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          color: _feedbackColor().withOpacity(0.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _feedbackColor().withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _feedbackIcon(),
              color: _feedbackColor(),
              size: 30,
            ),
            const SizedBox(width: 12),
            Text(
              _phaseInstruction(),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _feedbackColor(),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.visibility_rounded,
            color: Color(0xFF1E6BA8),
            size: 36,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _phaseInstruction(),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1C2430),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Keep your hand ready and respond only when instructed.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildReactionTarget() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: _targetSize,
      height: _targetSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _stimulusPressedVisual
            ? const LinearGradient(
                colors: [Color(0xFFD1D5DB), Color(0xFF9CA3AF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: _targetSize - 18,
          height: _targetSize - 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 2,
            ),
          ),
          child: const Center(
            child: Text(
              "TAP",
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDecisionSignal() {
    final isGreen = _decisionStimulus == "GREEN";

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: _decisionSignalSize,
      height: _decisionSignalSize,
      decoration: BoxDecoration(
        gradient: _stimulusPressedVisual
            ? const LinearGradient(
                colors: [Color(0xFFD1D5DB), Color(0xFF9CA3AF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: isGreen
                    ? const [Color(0xFF4ADE80), Color(0xFF16A34A)]
                    : const [Color(0xFFF87171), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(38),
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isGreen ? Icons.touch_app_rounded : Icons.pan_tool_alt_rounded,
            color: Colors.white,
            size: 46,
          ),
          const SizedBox(height: 14),
          Text(
            isGreen ? "TAP" : "WAIT",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isGreen ? "Respond now" : "Do not tap",
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    final progress = (_countdown / 3).clamp(0.0, 1.0);
    final double overlayWidth =
        min(MediaQuery.of(context).size.width - 32, 320.0).toDouble();

    return Container(
      color: const Color(0xDDF4F7FB),
      child: Center(
        child: Container(
          width: overlayWidth,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Assessment starting",
                style: TextStyle(
                  color: Color(0xFF1C2430),
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Focus on the task area and wait for the signal.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 132,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 9,
                        backgroundColor: const Color(0xFFE5E7EB),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF1E6BA8),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        "$_countdown",
                        key: ValueKey<int>(_countdown),
                        style: const TextStyle(
                          fontSize: 58,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E6BA8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF1E6BA8),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Avoid tapping before the signal appears.",
                        style: TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}