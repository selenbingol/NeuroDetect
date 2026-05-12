import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../models/test_result.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';

class VisualMemoryGamePage extends StatefulWidget {
  final UserModel user;
  final BleService? bleService;

  const VisualMemoryGamePage({
    super.key,
    required this.user,
    this.bleService,
  });

  @override
  State<VisualMemoryGamePage> createState() => _VisualMemoryGamePageState();
}

class _VisualMemoryGamePageState extends State<VisualMemoryGamePage> {
  final ApiService _apiService = ApiService();
  final Random _random = Random();

  static const int _maxRounds = 8;
  static const int _countdownStart = 3;

  static const int _initialBlueMs = 1000;
  static const int _changedRedMs = 3000;
  static const int _answerMs = 7000;

  static const int _gridItemCount = 9;
  static const int _changedCardCount = 3;

  static const Color _baseBlue = Color(0xFF2563EB);
  static const Color _changedRed = Color(0xFFEF4444);
  static const Color _selectedBorder = Color(0xFF111827);

  int? _sessionId;

  bool _isLoadingSession = true;
  bool _isCountdownActive = true;
  bool _isGameFinished = false;
  bool _isRoundFinalizing = false;

  int _countdown = _countdownStart;
  int _currentRound = 0;

  bool _isInitialBluePhase = false;
  bool _isChangedRedPhase = false;
  bool _isAnswerPhase = false;

  String _feedbackMessage = "";

  Timer? _countdownTimer;
  Timer? _initialBlueTimer;
  Timer? _changedRedTimer;
  Timer? _answerTimer;

  Set<int> _changedIndexes = {};
  Set<int> _selectedIndexes = {};

  int _roundShownAt = 0;
  final List<int> _reactionTimes = [];

  int _correctSelectionCount = 0;
  int _falseSelectionCount = 0;
  int _omissionCount = 0;
  int _falseStartCount = 0;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _initialBlueTimer?.cancel();
    _changedRedTimer?.cancel();
    _answerTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSession() async {
    final sessionId =
        await _apiService.startSession(widget.user.userId, "visual_memory");

    if (!mounted) return;

    setState(() {
      _sessionId = sessionId;
      _isLoadingSession = false;
    });

    if (sessionId != null) {
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
    if (!mounted || _isGameFinished) return;

    if (_currentRound >= _maxRounds) {
      _finishGame();
      return;
    }

    _currentRound++;

    final changed = <int>{};
    while (changed.length < _changedCardCount) {
      changed.add(_random.nextInt(_gridItemCount));
    }

    setState(() {
      _feedbackMessage = "";
      _changedIndexes = changed;
      _selectedIndexes = {};
      _isRoundFinalizing = false;

      _isInitialBluePhase = true;
      _isChangedRedPhase = false;
      _isAnswerPhase = false;
    });

    _initialBlueTimer = Timer(
      const Duration(milliseconds: _initialBlueMs),
      _startChangedRedPhase,
    );
  }

  void _startChangedRedPhase() {
    if (!mounted) return;

    setState(() {
      _isInitialBluePhase = false;
      _isChangedRedPhase = true;
      _isAnswerPhase = false;
    });

    _changedRedTimer = Timer(
      const Duration(milliseconds: _changedRedMs),
      _startAnswerPhase,
    );
  }

  void _startAnswerPhase() {
    if (!mounted) return;

    setState(() {
      _isInitialBluePhase = false;
      _isChangedRedPhase = false;
      _isAnswerPhase = true;
      _roundShownAt = DateTime.now().millisecondsSinceEpoch;
    });

    _answerTimer = Timer(const Duration(milliseconds: _answerMs), () {
      if (!mounted) return;
      _finalizeRound();
    });
  }

  void _onCardTap(int index) {
    if (_isLoadingSession || _isGameFinished || _isRoundFinalizing) return;

    if (_isInitialBluePhase || _isChangedRedPhase) {
      _falseStartCount++;
      setState(() {
        _feedbackMessage = "Too early";
      });
      return;
    }

    if (!_isAnswerPhase) return;

    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
      } else {
        _selectedIndexes.add(index);
      }
    });

    if (_selectedIndexes.length == _changedCardCount) {
      _isRoundFinalizing = true;

      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        _finalizeRound();
      });
    }
  }

  void _finalizeRound() {
    if (!_isAnswerPhase) return;

    _answerTimer?.cancel();

    final correctSelections =
        _selectedIndexes.intersection(_changedIndexes).length;
    final falseSelections =
        _selectedIndexes.difference(_changedIndexes).length;
    final omissions = _changedIndexes.difference(_selectedIndexes).length;

    _correctSelectionCount += correctSelections;
    _falseSelectionCount += falseSelections;
    _omissionCount += omissions;

    final rt = DateTime.now().millisecondsSinceEpoch - _roundShownAt;
    _reactionTimes.add(rt);

    String feedback;
    if (correctSelections == _changedCardCount &&
        falseSelections == 0 &&
        omissions == 0) {
      feedback = "Correct";
    } else if (correctSelections > 0) {
      feedback = "Partially correct";
    } else {
      feedback = "Incorrect";
    }

    setState(() {
      _isAnswerPhase = false;
      _isRoundFinalizing = false;
      _feedbackMessage = feedback;
    });

    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _prepareNextRound();
    });
  }

  Future<void> _finishGame() async {
    if (_isGameFinished || _sessionId == null) return;

    setState(() => _isGameFinished = true);

    final totalTargets = _maxRounds * _changedCardCount;

    final accuracy =
        totalTargets == 0 ? 0.0 : (_correctSelectionCount / totalTargets) * 100;

    final avgReactionTime = _reactionTimes.isEmpty
        ? 0.0
        : _reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length;

    final totalMisses = _falseSelectionCount + _omissionCount;

    final result = TestResult(
      reactionTime: avgReactionTime.round(),
      isSuccess: true,
      accuracy: accuracy,
      score: (_correctSelectionCount * 10) -
          (_falseSelectionCount * 4) -
          (_omissionCount * 5) -
          (_falseStartCount * 3),
      timestamp: DateTime.now(),
      tapCount: _correctSelectionCount,
      missCount: totalMisses,
      falseStartCount: _falseStartCount,
      wrongTapCount: _falseSelectionCount,
      timeoutCount: 0,
      falseAlarmCount: 0,
      omissionCount: _omissionCount,
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

    if (!mounted) return;
    Navigator.pop(context);
  }

  bool _isChangedCardVisible(int index) {
    return _isChangedRedPhase && _changedIndexes.contains(index);
  }

  Color _feedbackColor() {
    if (_feedbackMessage == "Too early" || _feedbackMessage == "Incorrect") {
      return const Color(0xFFDC2626);
    }

    if (_feedbackMessage == "Correct" ||
        _feedbackMessage == "Partially correct") {
      return const Color(0xFF16A34A);
    }

    return const Color(0xFF1C2430);
  }

  FontWeight _feedbackWeight() {
    if (_feedbackMessage.isNotEmpty) {
      return FontWeight.w800;
    }

    return FontWeight.w500;
  }

  Border _tileBorder(int index) {
    if (_isAnswerPhase && _selectedIndexes.contains(index)) {
      return Border.all(color: _selectedBorder, width: 4);
    }

    return Border.all(color: const Color(0xFFCBD5E1), width: 1.5);
  }

  List<BoxShadow> _tileShadow(int index) {
    if (_isAnswerPhase && _selectedIndexes.contains(index)) {
      return const [
        BoxShadow(
          color: Color(0x30000000),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ];
    }

    return const [
      BoxShadow(
        color: Color(0x18000000),
        blurRadius: 5,
        offset: Offset(0, 3),
      ),
    ];
  }

  String _instructionText() {
    if (_feedbackMessage.isNotEmpty) {
      return _feedbackMessage;
    }

    if (_isInitialBluePhase) {
      return "Get ready";
    }

    if (_isChangedRedPhase) {
      return "Memorize the red cards";
    }

    if (_isAnswerPhase) {
      return "Which cards changed? Tap them";
    }

    return "Wait for the next round";
  }

  Widget _buildMemoryCard(int index) {
    final isRed = _isChangedCardVisible(index);
    final isSelected = _isAnswerPhase && _selectedIndexes.contains(index);

    return GestureDetector(
      onTap: () => _onCardTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: isSelected ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isRed ? _changedRed : _baseBlue,
            borderRadius: BorderRadius.circular(22),
            border: _tileBorder(index),
            boxShadow: _tileShadow(index),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 10,
                left: 12,
                child: Container(
                  width: 34,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              if (isSelected)
                const Center(
                  child: Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: _isLoadingSession
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Container(
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
                      Column(
                        children: [
                          const SizedBox(height: 24),
                          Text(
                            "Round $_currentRound / $_maxRounds",
                            style: const TextStyle(
                              fontSize: 18,
                              color: Color(0xFF1C2430),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _instructionText(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize:
                                  _feedbackMessage.isNotEmpty ? 28 : 18,
                              fontWeight: _feedbackWeight(),
                              color: _feedbackColor(),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 500,
                                  maxHeight: 410,
                                ),
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: _gridItemCount,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: 14,
                                    childAspectRatio: 1.25,
                                  ),
                                  itemBuilder: (context, index) {
                                    return RepaintBoundary(
                                      child: _buildMemoryCard(index),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                      if (_isCountdownActive)
                        Container(
                          color: const Color(0xCCF4F7FB),
                          child: Center(
                            child: Text(
                              "$_countdown",
                              style: const TextStyle(
                                fontSize: 100,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E6BA8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}