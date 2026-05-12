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
  static const double _bleMotionThreshold = 0.90;
  static const double _bleGyroThreshold = 0.35;

  static const double _minSlashDistance = 55;
  static const double _requiredCutCoverageRatio = 0.55;

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

  double _avgMotion = 0;
  double _avgGyro = 0;
  double _tremorIndex = 0;

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
      _sensorSamples.add(data);
      _updateSensorSummaries();

      final trigger =
          data.motion > _bleMotionThreshold || data.gyro > _bleGyroThreshold;

      if (!trigger || !_isFruitVisible) return;

      final displaySize = _fruitSize * _currentFruitScale;
      final fruitCenter = Offset(
        _fruitX + displaySize / 2,
        _fruitY + displaySize / 2,
      );

      final sensorSlashLength = 180.0;
      final angle = atan2(data.gy, data.gx == 0 ? 0.001 : data.gx);

      final start = Offset(
        fruitCenter.dx - cos(angle) * sensorSlashLength / 2,
        fruitCenter.dy - sin(angle) * sensorSlashLength / 2,
      );
      final end = Offset(
        fruitCenter.dx + cos(angle) * sensorSlashLength / 2,
        fruitCenter.dy + sin(angle) * sensorSlashLength / 2,
      );

      _handleSlash(start, end, fromBle: true);
    });
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

    _tremorIndex = sqrt(variance);
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
    final maxX = (_playWidth - displaySize).clamp(140.0, double.infinity);
    final maxY = (_playHeight - displaySize).clamp(180.0, double.infinity);

    setState(() {
      _isWaitingForFruit = false;
      _isFruitVisible = true;

      _currentFruitAsset = fruit.assetPath;
      _currentFruitFallback = fruit.fallback;
      _currentFruitScale = fruit.scale;

      _fruitX = 30 + _random.nextDouble() * (maxX - 30);
      _fruitY = 80 + _random.nextDouble() * (maxY - 80);

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

      setState(() {
        _fruitX += _fruitVx;
        _fruitY += _fruitVy;

        if (_fruitX <= 0) {
          _fruitX = 0;
          _fruitVx = _fruitVx.abs();
        } else if (_fruitX >= _playWidth - displaySize) {
          _fruitX = _playWidth - displaySize;
          _fruitVx = -_fruitVx.abs();
        }

        if (_fruitY <= 55) {
          _fruitY = 55;
          _fruitVy = _fruitVy.abs();
        } else if (_fruitY >= _playHeight - displaySize) {
          _fruitY = _playHeight - displaySize;
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

      if (eventType == "hit") {
        _hitCount++;
        final rt = DateTime.now().millisecondsSinceEpoch - _fruitShownAt;
        _reachTimes.add(rt);
        _feedbackMessage = "Perfect slice";
      } else if (eventType == "false_start") {
        _falseStartCount++;
        _feedbackMessage = "Too early";
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _playWidth = constraints.maxWidth - 40;
            _playHeight = constraints.maxHeight - 30;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: GestureDetector(
                onPanStart: (details) {
                  _dragStartPoint = details.localPosition;
                  _dragCurrentPoint = details.localPosition;
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
                      _handleSlash(_dragStartPoint!, _dragCurrentPoint!);
                    } else {
                      setState(() {
                        _showSlash = false;
                      });
                    }
                  }

                  _dragStartPoint = null;
                  _dragCurrentPoint = null;
                },
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
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
                      Positioned(
                        top: 24,
                        left: 20,
                        right: 20,
                        child: Column(
                          children: [
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
                              _feedbackMessage.isNotEmpty
                                  ? _feedbackMessage
                                  : "Slice the moving fruit with a fast hand movement",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: _feedbackMessage.isNotEmpty ? 26 : 18,
                                fontWeight: _feedbackMessage.isNotEmpty
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: const Color(0xFF1C2430),
                              ),
                            ),
                          ],
                        ),
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
                      if (_isCountdownActive)
                        Center(
                          child: Text(
                            "$_countdown",
                            style: const TextStyle(
                              fontSize: 100,
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
          },
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
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final mainPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          Color(0xFFFFFFFF),
          Color(0xFFFFE082),
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