class DoctorUserModel {
  final int userId;
  final String username;
  final String email;
  final String role;

  DoctorUserModel({
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
  });

  factory DoctorUserModel.fromJson(Map<String, dynamic> json) {
    return DoctorUserModel(
      userId: json['user_id'],
      username: json['username'],
      email: json['email'],
      role: json['role'],
    );
  }
}