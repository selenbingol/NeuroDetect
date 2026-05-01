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
  static const int _stimulusVisibleMs = 2000;

  double _currentTaskAreaHeight = 430;

  int? _sessionId;
  bool _isLoadingSession = true;
  bool _isGameFinished = false;
  bool _isAiLoading = false;

  int _currentRound = 0;

  // GO / NO-GO metrikleri
  int _tapCount = 0; // GREEN -> bastı
  int _correctNoGoCount = 0; // RED -> bekledi
  int _falseAlarmCount = 0; // RED -> bastı
  int _omissionCount = 0; // GREEN -> basmadı
  int _falseStartCount = 0; // stimulus gelmeden bastı

  final List<int> _reactionTimes = [];
  late final List<String> _stimulusSequence;

  String? _currentStimulus; // GREEN / RED
  int _stimulusShownAt = 0;

  bool _isWaitingForStimulus = false;
  bool _eventHandled = false;
  String _feedbackMessage = "";

  Timer? _stimulusDelayTimer;
  Timer? _stimulusTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _stimulusSequence = _buildStimulusSequence();
    _startSession();
  }

  @override
  void dispose() {
    _stimulusDelayTimer?.cancel();
    _stimulusTimeoutTimer?.cancel();
    super.dispose();
  }

  List<String> _buildStimulusSequence() {
    final sequence = <String>[
      ...List.filled(7, "GREEN"),
      ...List.filled(3, "RED"),
    ];
    sequence.shuffle(_random);
    return sequence;
  }

  Future<void> _startSession() async {
    final sessionId =
        await _apiService.startSession(widget.user.userId, "decision");

    if (!mounted) return;

    setState(() {
      _sessionId = sessionId;
      _isLoadingSession = false;
    });

    if (sessionId != null) {
      Future.delayed(const Duration(milliseconds: 900), _prepareNextRound);
    }
  }

  void _prepareNextRound() {
    if (_isGameFinished) return;

    if (_currentRound >= _maxRounds) {
      _finishGame();
      return;
    }

    setState(() {
      _currentRound++;
      _currentStimulus = null;
      _isWaitingForStimulus = true;
      _eventHandled = false;
      _feedbackMessage = "";
    });

    final delay = 1000 + _random.nextInt(1500);
    _stimulusDelayTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted || _isGameFinished) return;
      _showStimulus();
    });
  }

  void _showStimulus() {
    final stimulus = _stimulusSequence[_currentRound - 1];

    setState(() {
      _currentStimulus = stimulus;
      _isWaitingForStimulus = false;
      _stimulusShownAt = DateTime.now().millisecondsSinceEpoch;
    });

    _stimulusTimeoutTimer =
        Timer(const Duration(milliseconds: _stimulusVisibleMs), () {
      if (!mounted || _eventHandled) return;

      if (_currentStimulus == "GREEN") {
        _handleEvent(eventType: "omission");
      } else if (_currentStimulus == "RED") {
        _handleEvent(eventType: "correct_nogo");
      }
    });
  }

  void _handleEvent({required String eventType}) {
    if (_isGameFinished || _eventHandled) return;
    _eventHandled = true;

    _stimulusDelayTimer?.cancel();
    _stimulusTimeoutTimer?.cancel();

    setState(() {
      if (eventType == "tap") {
        _tapCount++;
        _reactionTimes
            .add(DateTime.now().millisecondsSinceEpoch - _stimulusShownAt);
        _feedbackMessage = "Correct";
      } else if (eventType == "false_alarm") {
        _falseAlarmCount++;
        _feedbackMessage = "Do not tap red";
      } else if (eventType == "omission") {
        _omissionCount++;
        _feedbackMessage = "Too slow";
      } else if (eventType == "correct_nogo") {
        _correctNoGoCount++;
        _feedbackMessage = "Good inhibition";
      } else if (eventType == "false_start") {
        _falseStartCount++;
        _feedbackMessage = "Too early";
      }

      _currentStimulus = null;
      _isWaitingForStimulus = false;
    });

    Future.delayed(const Duration(milliseconds: 800), _prepareNextRound);
  }

  void _handleTaskAreaTap() {
    if (_isLoadingSession || _isGameFinished || _eventHandled) return;

    if (_isWaitingForStimulus) {
      _handleEvent(eventType: "false_start");
    } else if (_currentStimulus == "GREEN") {
      _handleEvent(eventType: "tap");
    } else if (_currentStimulus == "RED") {
      _handleEvent(eventType: "false_alarm");
    }
  }

  Future<void> _finishGame() async {
    if (_isGameFinished || _sessionId == null) return;

    final totalCorrect = _tapCount + _correctNoGoCount;
    final totalAttempts = _tapCount +
        _correctNoGoCount +
        _falseAlarmCount +
        _omissionCount +
        _falseStartCount;

    final accuracy =
        totalAttempts == 0 ? 0.0 : (totalCorrect / totalAttempts) * 100;

    final avgReactionTime = _reactionTimes.isEmpty
        ? 0.0
        : _reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length;

    final falseAlarmRate =
        totalAttempts > 0 ? (_falseAlarmCount / totalAttempts) * 100 : 0.0;
    final omissionRate =
        totalAttempts > 0 ? (_omissionCount / totalAttempts) * 100 : 0.0;
    final falseStartRate =
        totalAttempts > 0 ? (_falseStartCount / totalAttempts) * 100 : 0.0;

    double rtStd = 0.0;
    if (_reactionTimes.length > 1) {
      final mean = avgReactionTime;
      final variance = _reactionTimes
              .map((rt) => (rt - mean) * (rt - mean))
              .reduce((a, b) => a + b) /
          _reactionTimes.length;
      rtStd = sqrt(variance);
    }

    debugPrint("=== DECISION GAME KLİNİK METRİKLER ===");
    debugPrint("Accuracy: ${accuracy.toStringAsFixed(1)}%");
    debugPrint("False Alarm Rate: ${falseAlarmRate.toStringAsFixed(1)}%");
    debugPrint("Omission Rate: ${omissionRate.toStringAsFixed(1)}%");
    debugPrint("False Start Rate: ${falseStartRate.toStringAsFixed(1)}%");
    debugPrint("Avg RT (tap only): ${avgReactionTime.toStringAsFixed(0)} ms");
    debugPrint("RT Std: ${rtStd.toStringAsFixed(1)} ms");

    final score = (totalCorrect * 10) -
        (_falseAlarmCount * 15) -
        (_falseStartCount * 5) -
        (_omissionCount * 2);

    final totalMisses =
        _falseAlarmCount + _omissionCount + _falseStartCount;

    final result = TestResult(
      reactionTime: avgReactionTime.round(),
      isSuccess: true,
      accuracy: accuracy,
      score: score,
      timestamp: DateTime.now(),
      tapCount: _tapCount + _correctNoGoCount,
      missCount: totalMisses,
      falseStartCount: _falseStartCount,
      wrongTapCount: 0,
      timeoutCount: 0,
      falseAlarmCount: _falseAlarmCount,
      omissionCount: _omissionCount,
    );

    setState(() {
      _isGameFinished = true;
      _isAiLoading = true;
    });

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

    try {
      await _apiService.getAiPrediction(
        mri: [1600.0, 0.75, 1.0],
        clinical: [75.0, 14.0, 2.0, 28.0, 0.0, 1.0],
        game: [avgReactionTime, accuracy, totalMisses.toDouble()],
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

  Color _stimulusColor() {
    if (_currentStimulus == "GREEN") return Colors.greenAccent.shade700;
    if (_currentStimulus == "RED") return Colors.redAccent.shade700;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final accuracy = _currentRound == 0
        ? 0.0
        : ((_tapCount + _correctNoGoCount) / _currentRound) * 100;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          "Decision Task - ${widget.user.username}",
          style: const TextStyle(
            color: Color(0xFF1C2430),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight - 40.0 - 18.0;
            final taskHeight = availableHeight.clamp(260.0, 520.0);

            if (_currentTaskAreaHeight != taskHeight) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _currentTaskAreaHeight = taskHeight);
              });
            }

            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    children: [
                      _buildTopPanel(accuracy),
                      const SizedBox(height: 18.0),
                      Expanded(child: _buildTaskArea(taskHeight)),
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
            );
          },
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
                title: "False Alarm",
                value: "$_falseAlarmCount",
                valueColor: Colors.redAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? const Color(0xFF1C2430),
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

  Widget _buildTaskArea(double taskHeight) {
    return GestureDetector(
      onTap: _handleTaskAreaTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: taskHeight,
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
            if (!_isLoadingSession && !_isGameFinished && _currentStimulus == null)
              Center(
                child: Text(
                  _feedbackMessage.isNotEmpty
                      ? _feedbackMessage
                      : "Wait for the next signal",
                  style: TextStyle(
                    fontSize: _feedbackMessage.isNotEmpty ? 28 : 22,
                    fontWeight: _feedbackMessage.isNotEmpty
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: const Color(0xFF1C2430),
                  ),
                ),
              ),
            if (!_isLoadingSession &&
                !_isGameFinished &&
                _currentStimulus != null)
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: _stimulusColor(),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 15),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _currentStimulus == "GREEN" ? "TAP" : "WAIT",
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
      ),
    );
  }
}