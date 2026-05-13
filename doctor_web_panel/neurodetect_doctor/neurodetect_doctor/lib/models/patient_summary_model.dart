class PatientSummaryModel {
  final int userId;
  final String firstName;
  final String lastName;
  final String? dob;
  final String phone;
  final String gender;
  final List<String> sessionDates;

  PatientSummaryModel({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.dob,
    required this.phone,
    required this.gender,
    required this.sessionDates,
  });

  factory PatientSummaryModel.fromJson(Map<String, dynamic> json) {
    return PatientSummaryModel(
      userId: json["user_id"] ?? 0,
      firstName: json["first_name"] ?? "",
      lastName: json["last_name"] ?? "",
      dob: json["dob"],
      phone: json["phone"] ?? "",
      gender: json["gender"] ?? "",
      sessionDates: json["session_dates"] == null
          ? []
          : List<String>.from(json["session_dates"]),
    );
  }
}