import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'reaction_game_page.dart';
import 'decision_game_page.dart';
import 'completion_page.dart';

class AssessmentFlowPage extends StatefulWidget {
  final UserModel user;

  const AssessmentFlowPage({super.key, required this.user});

  @override
  State<AssessmentFlowPage> createState() => _AssessmentFlowPageState();
}

class _AssessmentFlowPageState extends State<AssessmentFlowPage> {
  int _currentStep = 0;

  late final List<_AssessmentTask> _tasks = [
    _AssessmentTask(
      title: "Reaction Task",
      description:
          "First, you will complete a basic reaction task to measure response speed and accuracy.",
      buttonText: "Start Reaction Task",
      pageBuilder: () => ReactionGamePage(user: widget.user),
    ),
    _AssessmentTask(
      title: "Decision Task",
      description:
          "Next, you will complete a decision task to measure attention and response control.",
      buttonText: "Start Decision Task",
      pageBuilder: () => DecisionGamePage(user: widget.user),
    ),
  ];

  Future<void> _openCurrentTask() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _tasks[_currentStep].pageBuilder(),
      ),
    );

    if (!mounted) return;

    if (_currentStep < _tasks.length - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const CompletionPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTask = _tasks[_currentStep];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Assessment Sequence",
          style: TextStyle(
            color: Color(0xFF1C2430),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1C2430)),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProgressCard(),
                  const SizedBox(height: 20),
                  _buildTaskCard(currentTask),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F4C81), Color(0xFF1E6BA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Structured Task Progression",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "The assessment tasks are presented in a fixed sequence from simpler to more demanding activities.",
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "Task ${_currentStep + 1} of ${_tasks.length}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (_currentStep + 1) / _tasks.length,
            minHeight: 8,
            borderRadius: BorderRadius.circular(20),
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(_AssessmentTask task) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C2430),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            task.description,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF4B5563),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _openCurrentTask,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E6BA8),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                task.buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentTask {
  final String title;
  final String description;
  final String buttonText;
  final Widget Function() pageBuilder;

  _AssessmentTask({
    required this.title,
    required this.description,
    required this.buttonText,
    required this.pageBuilder,
  });
}