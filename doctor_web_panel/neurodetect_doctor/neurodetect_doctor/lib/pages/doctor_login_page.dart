import 'package:flutter/material.dart';
import '../models/doctor_user_model.dart';
import '../services/api_service.dart';
import 'doctor_dashboard.dart';

class DoctorLoginPage extends StatefulWidget {
  const DoctorLoginPage({super.key});

  @override
  State<DoctorLoginPage> createState() => _DoctorLoginPageState();
}

class _DoctorLoginPageState extends State<DoctorLoginPage> {
  final ApiService _apiService = ApiService();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String _errorMessage = "";

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginDoctor() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    final DoctorUserModel? doctor = await _apiService.loginDoctor(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (doctor != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DoctorDashboardPage(doctor: doctor),
        ),
      );
    } else {
      setState(() {
        _errorMessage =
            "Doctor login failed. Please verify your credentials and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(48),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF123C69),
                      Color(0xFF1E5F92),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.local_hospital_rounded,
                      size: 58,
                      color: Colors.white,
                    ),
                    SizedBox(height: 24),
                    Text(
                      "NeuroDetect",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      "Doctor Access Portal",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      "Access patient assessment history, monitor cognitive-motor test performance, and review clinical summaries through the secure NeuroDetect dashboard.",
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 56,
                              color: Color(0xFF1E5F92),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "Doctor Sign In",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Enter your professional credentials to continue.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF6B7280),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 28),

                            _buildTextField(
                              controller: _usernameController,
                              label: "Doctor Username",
                              hint: "Enter your username",
                              icon: Icons.person_outline_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Username is required.";
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 16),

                            _buildTextField(
                              controller: _passwordController,
                              label: "Password",
                              hint: "Enter your password",
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscurePassword,
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Password is required.";
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 18),

                            if (_errorMessage.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFFDA4AF),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: Color(0xFFBE123C),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage,
                                        style: const TextStyle(
                                          color: Color(0xFF9F1239),
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _loginDoctor,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E5F92),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Sign In",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 22),
                            const Divider(),
                            const SizedBox(height: 14),

                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.security_rounded,
                                  size: 18,
                                  color: Color(0xFF6B7280),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "This portal is restricted to authorised medical staff and clinical supervisors. Access activity may be logged for security and audit purposes.",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF6B7280),
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD7DEE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD7DEE7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E5F92), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
        ),
      ),
    );
  }
}