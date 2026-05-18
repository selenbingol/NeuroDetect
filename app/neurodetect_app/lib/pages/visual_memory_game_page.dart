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

  static const String _cardsBackgroundAsset = 'assets/backgrounds/cards.png';

  int? _sessionId;
  StreamSubscription<SensorData>? _sensorSub;
  final List<SensorData> _sensorSamples = [];

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
    _startSensorTracking();
    _startSession();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _initialBlueTimer?.cancel();
    _changedRedTimer?.cancel();
    _answerTimer?.cancel();
    _sensorSub?.cancel();
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

    final memoryScore = (_correctSelectionCount * 10) -
        (_falseSelectionCount * 4) -
        (_omissionCount * 5) -
        (_falseStartCount * 3);

    final result = TestResult(
      reactionTime: avgReactionTime.round(),
      isSuccess: true,
      accuracy: accuracy,
      score: memoryScore,
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

    await _apiService.saveVisualMemoryMetrics(
      sessionId: _sessionId!,
      totalRounds: _maxRounds,
      gridItemCount: _gridItemCount,
      changedCardCount: _changedCardCount,
      correctSelectionCount: _correctSelectionCount,
      falseSelectionCount: _falseSelectionCount,
      omissionCount: _omissionCount,
      falseStartCount: _falseStartCount,
      totalTargets: totalTargets,
      totalMisses: totalMisses,
      avgReactionTimeMs: avgReactionTime,
      accuracyRate: accuracy,
      memoryScore: memoryScore,
    );

    final sensorMetrics = _calculateSensorMetrics(_sensorSamples);
    await _apiService.saveSensorMetrics(
      sessionId: _sessionId!,
      avgMotion: sensorMetrics["avgMotion"],
      avgGyro: sensorMetrics["avgGyro"],
      tremorIndex: sensorMetrics["tremorIndex"],
      movementVariability: sensorMetrics["movementVariability"],
      pathCorrectionCount: 0,
      sampleCount: _sensorSamples.length,
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

  IconData _feedbackIcon() {
    if (_feedbackMessage == "Correct" ||
        _feedbackMessage == "Partially correct") {
      return Icons.check_circle_rounded;
    }

    if (_feedbackMessage == "Too early" || _feedbackMessage == "Incorrect") {
      return Icons.error_rounded;
    }

    return Icons.info_rounded;
  }

  FontWeight _feedbackWeight() {
    if (_feedbackMessage.isNotEmpty) {
      return FontWeight.w900;
    }

    return FontWeight.w600;
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

  String _phaseText() {
    if (_isInitialBluePhase) return "Preparation";
    if (_isChangedRedPhase) return "Encoding";
    if (_isAnswerPhase) return "Recall";
    if (_feedbackMessage.isNotEmpty) return "Feedback";
    return "Ready";
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
    final progressValue = _currentRound == 0 ? 0.0 : _currentRound / _maxRounds;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: _isLoadingSession
            ? _buildLoadingView()
            : Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      children: [
                        _buildHeaderPanel(progressValue),
                        const SizedBox(height: 10),
                        Expanded(
                          child: _buildPlayArea(),
                        ),
                      ],
                    ),
                  ),
                  if (_isCountdownActive) _buildCountdownOverlay(),
                ],
              ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Container(
        width: 290,
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
              "Preparing memory task...",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1C2430),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Please wait while the visual memory session is initialized.",
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

  Widget _buildHeaderPanel(double progressValue) {
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
                  Icons.grid_view_rounded,
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
                      "Visual Memory Task",
                      style: TextStyle(
                        color: Color(0xFF1C2430),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${widget.user.username} · Short-term visual memory assessment",
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
              _buildStatusBadge(),
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
                value: "$_currentRound / $_maxRounds",
              ),
              const SizedBox(width: 8),
              _buildMetricCard(
                icon: Icons.style_rounded,
                title: "Cards",
                value: "$_gridItemCount cards",
              ),
              const SizedBox(width: 8),
              _buildMetricCard(
                icon: Icons.visibility_rounded,
                title: "Changed",
                value: "$_changedCardCount cards",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.psychology_alt_rounded,
            size: 15,
            color: Color(0xFF0369A1),
          ),
          const SizedBox(width: 5),
          Text(
            _phaseText(),
            style: const TextStyle(
              color: Color(0xFF0369A1),
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

  Widget _buildPlayArea() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          _buildCardsBackground(),
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.14),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildInstructionBanner(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 520,
                          maxHeight: 430,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double availableWidth = constraints.maxWidth;
                            final double availableHeight = constraints.maxHeight;

                            // Horizontal and vertical spacing = 2 * 14 = 28
                            final double itemWidth = (availableWidth - 28) / 3;
                            final double itemHeight = (availableHeight - 28) / 3;

                            // Dynamically calculate aspect ratio to fit the available space
                            double ratio = itemWidth / itemHeight;
                            
                            // Keep it within reasonable bounds so cards still look beautiful
                            if (ratio < 0.85) ratio = 0.85;
                            if (ratio > 1.35) ratio = 1.35;

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _gridItemCount,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: ratio,
                              ),
                              itemBuilder: (context, index) {
                                return RepaintBoundary(
                                  child: _buildMemoryCard(index),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardsBackground() {
    return Positioned.fill(
      child: Image.asset(
        _cardsBackgroundAsset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E3A8A),
                  Color(0xFF0F766E),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInstructionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _feedbackMessage.isNotEmpty
                ? _feedbackIcon()
                : Icons.visibility_rounded,
            color: _feedbackMessage.isNotEmpty
                ? _feedbackColor()
                : const Color(0xFF1E6BA8),
            size: 23,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _instructionText(),
              textAlign: TextAlign.left,
              style: TextStyle(
                color: _feedbackMessage.isNotEmpty
                    ? _feedbackColor()
                    : const Color(0xFF334155),
                fontSize: _feedbackMessage.isNotEmpty ? 17 : 14.5,
                fontWeight: _feedbackWeight(),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    final progress = (_countdown / 3).clamp(0.0, 1.0);

    return Container(
      color: const Color(0xDDF4F7FB),
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = min(
              max(constraints.maxWidth - 40, 280.0),
              360.0,
            );

            return Container(
              width: cardWidth,
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
                    "Memory task starting",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF1C2430),
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Focus on the cards and remember which ones change color.",
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
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
                            "Avoid tapping before the recall question appears.",
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
            );
          },
        ),
      ),
    );
  }

  void _startSensorTracking() {
    final bleService = widget.bleService;
    if (bleService == null) return;

    _sensorSub = bleService.sensorDataStream.listen((data) {
      if (_isGameFinished) return;
      _sensorSamples.add(data);
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
}