import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../models/test_result.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';

class TargetMovementGamePage extends StatefulWidget {
  final UserModel user;
  final BleService? bleService;

  const TargetMovementGamePage({
    super.key,
    required this.user,
    this.bleService,
  });

  @override
  State<TargetMovementGamePage> createState() => _TargetMovementGamePageState();
}

class _TargetMovementGamePageState extends State<TargetMovementGamePage> {
  final ApiService _apiService = ApiService();
  final Random _random = Random();

  static const int _maxRounds = 10;
  static const int _countdownStart = 3;
  static const int _fruitLifeMs = 5000;

  static const double _fruitSize = 220;

  static const double _minSlashDistance = 55;
  static const double _requiredCutCoverageRatio = 0.55;

  static const String _woodBackgroundAsset =
      'assets/backgrounds/background.png';

  int? _sessionId;

  bool _isLoadingSession = true;
  bool _isCountdownActive = true;
  bool _isGameFinished = false;
  bool _isWaitingForFruit = false;
  bool _isFruitVisible = false;

  int _countdown = _countdownStart;
  int _currentRound = 0;

  int _hitCount = 0;
  int _falseStartCount = 0;
  int _wrongMoveCount = 0;
  int _nearMissCount = 0;
  int _timeoutCount = 0;

  final List<int> _reachTimes = [];
  final List<SensorData> _sensorSamples = [];

  StreamSubscription<SensorData>? _sensorSub;
  Timer? _countdownTimer;
  Timer? _roundDelayTimer;
  Timer? _fruitLifeTimer;
  Timer? _fruitMotionTimer;

  double _playWidth = 0;
  double _playHeight = 0;

  double _fruitX = 0;
  double _fruitY = 0;
  double _fruitVx = 3.0;
  double _fruitVy = -2.4;

  String _currentFruitAsset = 'assets/fruits/apple.png';
  String _currentFruitFallback = '🍎';
  double _currentFruitScale = 1.0;

  String _feedbackMessage = "";
  int _fruitShownAt = 0;
  bool _fruitAlreadyCutThisRound = false;

  Offset? _dragStartPoint;
  Offset? _dragCurrentPoint;
  Offset? _slashStart;
  Offset? _slashEnd;
  bool _showSlash = false;
  bool _dragStartedWithFruitVisible = false;

  double _avgMotion = 0;
double _avgGyro = 0;

// 0-100 normalized clinical tremor score
double _tremorIndex = 0;

// Raw gyro variability before normalization
double _rawMovementVariability = 0;

  final List<_FruitVisual> _fruitPool = [
    _FruitVisual(assetPath: 'assets/fruits/apple.png', fallback: '🍎', scale: 1.00),
    _FruitVisual(assetPath: 'assets/fruits/banana.png', fallback: '🍌', scale: 1.18),
    _FruitVisual(assetPath: 'assets/fruits/mango.png', fallback: '🥭', scale: 1.02),
    _FruitVisual(assetPath: 'assets/fruits/orange.png', fallback: '🍊', scale: 0.94),
    _FruitVisual(assetPath: 'assets/fruits/peach.png', fallback: '🍑', scale: 0.98),
    _FruitVisual(assetPath: 'assets/fruits/pear.png', fallback: '🍐', scale: 1.02),
    _FruitVisual(assetPath: 'assets/fruits/pineapple.png', fallback: '🍍', scale: 1.18),
    _FruitVisual(assetPath: 'assets/fruits/pomegranate.png', fallback: '🍎', scale: 0.96),
    _FruitVisual(assetPath: 'assets/fruits/strawberry.png', fallback: '🍓', scale: 1.12),
    _FruitVisual(assetPath: 'assets/fruits/watermelon.png', fallback: '🍉', scale: 1.08),
  ];

  int _fruitIndex = 0;

  @override
  void initState() {
    super.initState();
    _fruitPool.shuffle(_random);
    _startSession();
    _startSensorTracking();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _roundDelayTimer?.cancel();
    _fruitLifeTimer?.cancel();
    _fruitMotionTimer?.cancel();
    _sensorSub?.cancel();
    super.dispose();
  }

  Future<void> _startSession() async {
    final sessionId =
        await _apiService.startSession(widget.user.userId, "target_movement");

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

  void _startSensorTracking() {
  final bleService = widget.bleService;
  if (bleService == null) return;

  _sensorSub = bleService.sensorDataStream.listen((data) {
    if (_isGameFinished) return;

    _sensorSamples.add(data);

    // IMPORTANT:
    // BLE is used only for motor/tremor data collection.
    // It must not trigger automatic slicing.
  });
}
double _normalizeTremorIndex(double rawVariability) {
  // Based on current prototype observations:
  // ~0.10 = stable / no visible tremor
  // ~60+  = very high irregular movement
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

  void _updateSensorSummaries() {
  if (_sensorSamples.isEmpty) return;

  _avgMotion =
      _sensorSamples.map((e) => e.motion).reduce((a, b) => a + b) /
          _sensorSamples.length;

  _avgGyro =
      _sensorSamples.map((e) => e.gyro).reduce((a, b) => a + b) /
          _sensorSamples.length;

  double variance = 0;

  if (_sensorSamples.length > 1) {
    variance = _sensorSamples
            .map((e) => (e.gyro - _avgGyro) * (e.gyro - _avgGyro))
            .reduce((a, b) => a + b) /
        _sensorSamples.length;
  }

  final rawVariability = sqrt(variance);

  _rawMovementVariability = rawVariability;
  _tremorIndex = _normalizeTremorIndex(rawVariability);
}


  void _prepareNextRound() {
    if (_isGameFinished) return;

    if (_currentRound >= _maxRounds) {
      _finishGame();
      return;
    }

    setState(() {
      _currentRound++;
      _isWaitingForFruit = true;
      _isFruitVisible = false;
      _feedbackMessage = "";
      _fruitAlreadyCutThisRound = false;
      _showSlash = false;
      _dragStartPoint = null;
      _dragCurrentPoint = null;
      _slashStart = null;
      _slashEnd = null;
      _dragStartedWithFruitVisible = false;
    });

    _roundDelayTimer = Timer(
      Duration(milliseconds: 700 + _random.nextInt(500)),
      () {
        if (!mounted || _isGameFinished) return;
        _spawnFruit();
      },
    );
  }

  void _spawnFruit() {
    final fruit = _fruitPool[_fruitIndex % _fruitPool.length];
    _fruitIndex++;

    final displaySize = _fruitSize * fruit.scale;

    const minX = 30.0;
    const minY = 112.0;

    final maxX = max(minX, _playWidth - displaySize - 30);
    final maxY = max(minY, _playHeight - displaySize - 30);

    setState(() {
      _isWaitingForFruit = false;
      _isFruitVisible = true;

      _currentFruitAsset = fruit.assetPath;
      _currentFruitFallback = fruit.fallback;
      _currentFruitScale = fruit.scale;

      _fruitX = minX + _random.nextDouble() * (maxX - minX);
      _fruitY = minY + _random.nextDouble() * (maxY - minY);

      final speedX = 2.6 + _random.nextDouble() * 1.8;
      final speedY = 2.0 + _random.nextDouble() * 1.8;

      _fruitVx = _random.nextBool() ? speedX : -speedX;
      _fruitVy = _random.nextBool() ? speedY : -speedY;

      _fruitShownAt = DateTime.now().millisecondsSinceEpoch;
      _fruitAlreadyCutThisRound = false;
    });

    _startFruitMotion();

    _fruitLifeTimer = Timer(
      const Duration(milliseconds: _fruitLifeMs),
      () {
        if (!mounted || !_isFruitVisible) return;
        _handleRoundEvent(eventType: "timeout");
      },
    );
  }

  void _startFruitMotion() {
    _fruitMotionTimer?.cancel();

    _fruitMotionTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || _isGameFinished || !_isFruitVisible) {
        timer.cancel();
        return;
      }

      final displaySize = _fruitSize * _currentFruitScale;
      final maxX = max(0.0, _playWidth - displaySize);
      final minY = 92.0;
      final maxY = max(minY, _playHeight - displaySize - 4);

      setState(() {
        _fruitX += _fruitVx;
        _fruitY += _fruitVy;

        if (_fruitX <= 0) {
          _fruitX = 0;
          _fruitVx = _fruitVx.abs();
        } else if (_fruitX >= maxX) {
          _fruitX = maxX;
          _fruitVx = -_fruitVx.abs();
        }

        if (_fruitY <= minY) {
          _fruitY = minY;
          _fruitVy = _fruitVy.abs();
        } else if (_fruitY >= maxY) {
          _fruitY = maxY;
          _fruitVy = -_fruitVy.abs();
        }
      });
    });
  }

  void _handleSlash(Offset start, Offset end, {bool fromBle = false}) {
    if (_isLoadingSession || _isCountdownActive || _isGameFinished) return;

    setState(() {
      _slashStart = start;
      _slashEnd = end;
      _showSlash = true;
    });

    Future.delayed(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      setState(() {
        _showSlash = false;
        _slashStart = null;
        _slashEnd = null;
      });
    });

    if (_isWaitingForFruit) {
      _handleRoundEvent(eventType: "false_start");
      return;
    }

    if (!_isFruitVisible || _fruitAlreadyCutThisRound) return;

    final displaySize = _fruitSize * _currentFruitScale;
    final fruitRect = Rect.fromLTWH(_fruitX, _fruitY, displaySize, displaySize);
    final fruitCenter = Offset(
      _fruitX + displaySize / 2,
      _fruitY + displaySize / 2,
    );

    final slashDx = end.dx - start.dx;
    final slashDy = end.dy - start.dy;
    final slashLength = sqrt(slashDx * slashDx + slashDy * slashDy);

    if (slashLength < _minSlashDistance) return;

    final distanceToCenter = _distancePointToSegment(fruitCenter, start, end);

    final effectiveRadius = displaySize * 0.38;

    if (distanceToCenter > effectiveRadius) {
      _handleRoundEvent(eventType: "wrong_move");
      return;
    }

    final chordLength =
        2 * sqrt((effectiveRadius * effectiveRadius) -
            (distanceToCenter * distanceToCenter));

    final requiredChordLength = displaySize * _requiredCutCoverageRatio;
    final intersectsRect = _lineIntersectsRect(start, end, fruitRect);

    if (intersectsRect &&
        slashLength >= _minSlashDistance &&
        chordLength >= requiredChordLength) {
      _fruitAlreadyCutThisRound = true;
      _handleRoundEvent(eventType: "hit");
    } else if (distanceToCenter <= effectiveRadius) {
      // Slash meyveye dokundu ama kesim yeterince derin değil → near miss
      _handleRoundEvent(eventType: "near_miss");
    } else {
      _handleRoundEvent(eventType: "wrong_move");
    }
  }

  bool _lineIntersectsRect(Offset p1, Offset p2, Rect rect) {
    if (rect.contains(p1) || rect.contains(p2)) return true;

    final edges = [
      [rect.topLeft, rect.topRight],
      [rect.topRight, rect.bottomRight],
      [rect.bottomRight, rect.bottomLeft],
      [rect.bottomLeft, rect.topLeft],
    ];

    for (final edge in edges) {
      if (_segmentsIntersect(p1, p2, edge[0], edge[1])) return true;
    }
    return false;
  }

  bool _segmentsIntersect(Offset p1, Offset p2, Offset q1, Offset q2) {
    double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

    final r = p2 - p1;
    final s = q2 - q1;
    final denominator = cross(r, s);
    final qp = q1 - p1;

    if (denominator == 0) return false;

    final t = cross(qp, s) / denominator;
    final u = cross(qp, r) / denominator;

    return t >= 0 && t <= 1 && u >= 0 && u <= 1;
  }

  double _distancePointToSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final ap = point - a;

    final abLengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLengthSquared == 0) {
      final dx = point.dx - a.dx;
      final dy = point.dy - a.dy;
      return sqrt(dx * dx + dy * dy);
    }

    final t = ((ap.dx * ab.dx) + (ap.dy * ab.dy)) / abLengthSquared;
    final clampedT = t.clamp(0.0, 1.0);

    final projection = Offset(
      a.dx + ab.dx * clampedT,
      a.dy + ab.dy * clampedT,
    );

    final dx = point.dx - projection.dx;
    final dy = point.dy - projection.dy;
    return sqrt(dx * dx + dy * dy);
  }

  void _handleRoundEvent({required String eventType}) {
    if (_isGameFinished) return;

    _roundDelayTimer?.cancel();
    _fruitLifeTimer?.cancel();
    _fruitMotionTimer?.cancel();

    setState(() {
      _isFruitVisible = false;
      _isWaitingForFruit = false;
      _dragStartPoint = null;
      _dragCurrentPoint = null;
      _slashStart = null;
      _slashEnd = null;
      _dragStartedWithFruitVisible = false;

      if (eventType == "hit") {
        _hitCount++;
        final rt = DateTime.now().millisecondsSinceEpoch - _fruitShownAt;
        _reachTimes.add(rt);
        _feedbackMessage = "Perfect slice";
      } else if (eventType == "false_start") {
        _falseStartCount++;
        _feedbackMessage = "Too early";
      } else if (eventType == "near_miss") {
        _nearMissCount++;
        _feedbackMessage = "Almost!";
      } else if (eventType == "wrong_move") {
        _wrongMoveCount++;
        _feedbackMessage = "Missed slice";
      } else if (eventType == "timeout") {
        _timeoutCount++;
        _feedbackMessage = "Fruit escaped";
      }
    });

    Future.delayed(const Duration(milliseconds: 650), _prepareNextRound);
  }

  Future<void> _finishGame() async {
    if (_isGameFinished || _sessionId == null) return;

    setState(() => _isGameFinished = true);

    // Sunucuya göndermeden önce tüm sensör metriklerini tek seferde hesapla (UI donmasını önlemek için)
    _updateSensorSummaries();

    final totalAttempts =
        _hitCount + _falseStartCount + _wrongMoveCount + _timeoutCount;

    final avgReachTime = _reachTimes.isEmpty
        ? 0.0
        : _reachTimes.reduce((a, b) => a + b) / _reachTimes.length;

    final accuracy =
        totalAttempts == 0 ? 0.0 : (_hitCount / totalAttempts) * 100;

    final totalMisses = _wrongMoveCount + _timeoutCount;

    final result = TestResult(
      reactionTime: avgReachTime.round(),
      isSuccess: true,
      accuracy: accuracy,
      score: (_hitCount * 12) -
          (_falseStartCount * 5) -
          (_wrongMoveCount * 3) -
          (_timeoutCount * 4),
      timestamp: DateTime.now(),
      tapCount: _hitCount,
      missCount: totalMisses,
      falseStartCount: _falseStartCount,
      wrongTapCount: _wrongMoveCount,
      timeoutCount: _timeoutCount,
      falseAlarmCount: 0,
      omissionCount: 0,
    );

    // Show a beautiful, professional, non-dismissible saving overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E6BA8)),
                  ),
                  SizedBox(height: 20),
                  Text(
                    "Saving results...",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C2430),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
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

      await _apiService.saveSensorMetrics(
        sessionId: _sessionId!,
        avgMotion: _sensorSamples.isEmpty ? null : _avgMotion,
        avgGyro: _sensorSamples.isEmpty ? null : _avgGyro,
        tremorIndex: _sensorSamples.isEmpty ? null : _tremorIndex,
        movementVariability: _sensorSamples.isEmpty ? null : _rawMovementVariability,
        pathCorrectionCount: _wrongMoveCount,
        sampleCount: _sensorSamples.length,
      );

      await _apiService.saveTargetMovementMetrics(
        sessionId: _sessionId!,
        sliceHitCount: _hitCount,
        sliceMissCount: _wrongMoveCount,
        successfulCutCount: _hitCount,
        nearMissCount: _nearMissCount,
        avgSliceLength: null,
        avgCutCoverage: accuracy,
      );

      await _apiService.endSession(_sessionId!);
    } catch (e) {
      debugPrint("Error saving target movement metrics: $e");
    } finally {
      if (mounted) {
        Navigator.pop(context); // Pop saving dialog
        Navigator.pop(context); // Pop game page
      }
    }
  }

  Color _feedbackColor() {
    if (_feedbackMessage == "Perfect slice") {
      return const Color(0xFF16A34A);
    }

    if (_feedbackMessage == "Too early" ||
        _feedbackMessage == "Missed slice" ||
        _feedbackMessage == "Fruit escaped") {
      return const Color(0xFFDC2626);
    }

    return const Color(0xFF1C2430);
  }

  IconData _feedbackIcon() {
    if (_feedbackMessage == "Perfect slice") {
      return Icons.check_circle_rounded;
    }

    if (_feedbackMessage == "Too early" ||
        _feedbackMessage == "Missed slice" ||
        _feedbackMessage == "Fruit escaped") {
      return Icons.error_rounded;
    }

    return Icons.info_rounded;
  }

  String _instructionText() {
    if (_feedbackMessage.isNotEmpty) return _feedbackMessage;

    if (_isWaitingForFruit) {
      return "Wait for the moving target";
    }

    if (_isFruitVisible) {
      return "Slice the fruit with a controlled hand movement";
    }

    return "Get ready for the next target";
  }

  @override
  Widget build(BuildContext context) {
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
                        _buildHeaderPanel(),
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
              "Preparing movement task...",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1C2430),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "Please wait while the sensor-supported task session is initialized.",
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

  Widget _buildHeaderPanel() {
  final progressValue = _currentRound == 0 ? 0.0 : _currentRound / _maxRounds;

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
                Icons.track_changes_rounded,
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
                    "Target Movement Task",
                    style: TextStyle(
                      color: Color(0xFF1C2430),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "${widget.user.username} · Motor control assessment",
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
              icon: Icons.cut_rounded,
              title: "Task",
              value: "Slicing",
            ),
            const SizedBox(width: 8),
            _buildMetricCard(
              icon: Icons.sensors_rounded,
              title: "Mode",
              value: widget.bleService == null ? "Touch" : "BLE",
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildStatusBadge() {
    final hasSensor = widget.bleService != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: hasSensor ? const Color(0xFFECFCCB) : const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: hasSensor ? const Color(0xFFD9F99D) : const Color(0xFFBAE6FD),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSensor ? Icons.sensors_rounded : Icons.touch_app_rounded,
            size: 17,
            color:
                hasSensor ? const Color(0xFF4D7C0F) : const Color(0xFF0369A1),
          ),
          const SizedBox(width: 6),
          Text(
            hasSensor ? "Sensor linked" : "Touch mode",
            style: TextStyle(
              color:
                  hasSensor ? const Color(0xFF4D7C0F) : const Color(0xFF0369A1),
              fontSize: 13,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        _playWidth = constraints.maxWidth;
        _playHeight = constraints.maxHeight;

        return GestureDetector(
          onPanStart: (details) {
            _dragStartPoint = details.localPosition;
            _dragCurrentPoint = details.localPosition;
            _dragStartedWithFruitVisible = _isFruitVisible;
          },
          onPanUpdate: (details) {
            setState(() {
              _dragCurrentPoint = details.localPosition;
              _slashStart = _dragStartPoint;
              _slashEnd = _dragCurrentPoint;
              _showSlash = true;
            });
          },
          onPanEnd: (_) {
            if (_dragStartPoint != null && _dragCurrentPoint != null) {
              final dx = _dragCurrentPoint!.dx - _dragStartPoint!.dx;
              final dy = _dragCurrentPoint!.dy - _dragStartPoint!.dy;
              final distance = sqrt(dx * dx + dy * dy);

              if (distance >= _minSlashDistance) {
                if (_dragStartedWithFruitVisible) {
                  _handleSlash(_dragStartPoint!, _dragCurrentPoint!);
                } else {
                  if (_isWaitingForFruit) {
                    _handleRoundEvent(eventType: "false_start");
                  } else {
                    setState(() {
                      _showSlash = false;
                    });
                  }
                }
              } else {
                setState(() {
                  _showSlash = false;
                });
              }
            }

            _dragStartPoint = null;
            _dragCurrentPoint = null;
            _dragStartedWithFruitVisible = false;
          },
          child: Container(
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
                _buildWoodBackground(),
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: _buildInstructionBanner(),
                ),
                if (!_isFruitVisible && !_isCountdownActive && !_isGameFinished)
                  Center(
                    child: _buildCenterInstruction(),
                  ),
                if (_isFruitVisible)
                  Positioned(
                    left: _fruitX,
                    top: _fruitY,
                    child: _buildFruit(),
                  ),
                if (_showSlash && _slashStart != null && _slashEnd != null)
                  CustomPaint(
                    painter: _SlashPainter(
                      start: _slashStart!,
                      end: _slashEnd!,
                    ),
                    size: Size.infinite,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWoodBackground() {
    return Positioned.fill(
      child: Image.asset(
        _woodBackgroundAsset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFD9A441),
                  Color(0xFFB7791F),
                  Color(0xFF8B5A2B),
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
      child: const Row(
        children: [
          Icon(
            Icons.swipe_rounded,
            color: Color(0xFF1E6BA8),
            size: 23,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Use a quick and controlled slicing movement when the fruit appears.",
              style: TextStyle(
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
          color: _feedbackColor().withOpacity(0.12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _feedbackColor().withOpacity(0.28)),
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
              _instructionText(),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
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
              Icons.track_changes_rounded,
              color: Color(0xFF1E6BA8),
              size: 36,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _instructionText(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C2430),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Keep your movement smooth and controlled.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    final progress = (_countdown / 3).clamp(0.0, 1.0);
    final double overlayWidth =
        min(MediaQuery.of(context).size.width - 32, 340.0).toDouble();

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
                "Movement task starting",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1C2430),
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Focus on the play area and wait for the moving fruit.",
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
                        "Avoid moving before the target appears.",
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

  Widget _buildFruit() {
    final displaySize = _fruitSize * _currentFruitScale;

    return IgnorePointer(
      child: SizedBox(
        width: displaySize,
        height: displaySize,
        child: Image.asset(
          _currentFruitAsset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) {
            return Center(
              child: Text(
                _currentFruitFallback,
                style: TextStyle(fontSize: displaySize * 0.42),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FruitVisual {
  final String assetPath;
  final String fallback;
  final double scale;

  const _FruitVisual({
    required this.assetPath,
    required this.fallback,
    required this.scale,
  });
}

class _SlashPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _SlashPainter({
    required this.start,
    required this.end,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final mainPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          Color(0xFFFFFFFF),
          Color(0xFFFFF3B0),
          Colors.transparent,
        ],
      ).createShader(Rect.fromPoints(start, end))
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, glowPaint);
    canvas.drawLine(start, end, mainPaint);
  }

  @override
  bool shouldRepaint(covariant _SlashPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}