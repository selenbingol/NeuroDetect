import 'dart:math';

class TestService {
  final Random _random = Random();

  // Ekran boyutuna göre rastgele koordinat üretir
  double getNextCoordinate(double maxSize) {
    // 70 birimlik dairenin ekran dışına taşmaması için 150 birim pay bırakıyoruz
    return _random.nextDouble() * (maxSize - 150) + 50;
  }

  // Capstone raporundaki Accuracy (Doğruluk) hesabı
  double calculateAccuracy(int success, int total) {
    if (total == 0) return 100.0;
    return (success / total) * 100;
  }
}