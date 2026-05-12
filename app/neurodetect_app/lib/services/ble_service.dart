import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';

class SensorData {
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final double motion;
  final double gyro;
  final DateTime timestamp;

  SensorData({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.motion,
    required this.gyro,
    required this.timestamp,
  });

  factory SensorData.fromCsv(String csv) {
    final parts = csv.split(',').map((e) => double.tryParse(e.trim()) ?? 0.0).toList();

    return SensorData(
      ax: parts.isNotEmpty ? parts[0] : 0,
      ay: parts.length > 1 ? parts[1] : 0,
      az: parts.length > 2 ? parts[2] : 0,
      gx: parts.length > 3 ? parts[3] : 0,
      gy: parts.length > 4 ? parts[4] : 0,
      gz: parts.length > 5 ? parts[5] : 0,
      motion: parts.length > 6 ? parts[6] : 0,
      gyro: parts.length > 7 ? parts[7] : 0,
      timestamp: DateTime.now(),
    );
  }
}

class BleService {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _imuCharacteristic;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _imuSubscription;

  final StreamController<List<ScanResult>> _scanResultsController =
      StreamController<List<ScanResult>>.broadcast();

  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();

  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast();

  Stream<List<ScanResult>> get scanResultsStream => _scanResultsController.stream;
  Stream<BluetoothConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;

  BluetoothDevice? get connectedDevice => _connectedDevice;

  static final Guid serviceUuid =
      Guid("19B10000-E8F2-537E-4F6C-D104768A1214");

  static final Guid characteristicUuid =
      Guid("19B10001-E8F2-537E-4F6C-D104768A1214");

  Future<void> startScan() async {
  await FlutterBluePlus.stopScan();

  await _scanSubscription?.cancel();
  _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
    _scanResultsController.add(results);
  });

  await FlutterBluePlus.startScan(
    timeout: const Duration(seconds: 5),
    withServices: [serviceUuid],
  );
}

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    await stopScan();

    try {
      await device.connect(timeout: const Duration(seconds: 10));
    } catch (_) {
      // already connected olabilir
    }

    _connectedDevice = device;

    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      _connectionStateController.add(state);

      if (state == BluetoothConnectionState.disconnected) {
        _connectedDevice = null;
        _imuCharacteristic = null;
      }
    });

    await _discoverImuCharacteristic(device);
    print("CONNECT FONKSIYONU CALISTI");
  }

  Future<void> _discoverImuCharacteristic(BluetoothDevice device) async {
  debugPrint("BLE: service discovery basladi");

  final services = await device.discoverServices();

  debugPrint("BLE: bulunan service sayisi: ${services.length}");

  for (final service in services) {
    debugPrint("SERVICE UUID: ${service.uuid}");

    for (final characteristic in service.characteristics) {
      debugPrint("  CHARACTERISTIC UUID: ${characteristic.uuid}");
      debugPrint("  properties: ${characteristic.properties}");
    }

    if (service.uuid == serviceUuid) {
      debugPrint("BLE: NeuroDetect service bulundu");

      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == characteristicUuid) {
          debugPrint("BLE: IMU characteristic bulundu");
          _imuCharacteristic = characteristic;
          await _startListeningToImu(characteristic);
          return;
        }
      }
    }
  }

  debugPrint("BLE ERROR: IMU characteristic bulunamadi");
}
  Future<void> _startListeningToImu(
  BluetoothCharacteristic characteristic,
) async {
  await _imuSubscription?.cancel();

  print("START LISTENING FONKSIYONU GIRDI");

  _imuSubscription = characteristic.onValueReceived.listen((value) {
    final rawText = utf8.decode(value);

    print("RAW BLE DATA: $rawText");

    try {
      final sensorData = SensorData.fromCsv(rawText);
      _sensorDataController.add(sensorData);

      print(
        "BLE SENSOR => motion: ${sensorData.motion}, gyro: ${sensorData.gyro}",
      );
    } catch (e) {
      print("BLE parse error: $e | raw: $rawText");
    }
  });

  print("BLE: notify aciliyor");

  try {
    await characteristic.setNotifyValue(true);
    print("BLE: notify enabled");
  } catch (e) {
    print("BLE notify error: $e");
  }

  try {
    final firstValue = await characteristic.read();
    final rawText = utf8.decode(firstValue);
    print("FIRST READ DATA: $rawText");
  } catch (e) {
    print("BLE read error: $e");
  }
}

  Future<void> disconnect() async {
    await _imuSubscription?.cancel();
    _imuSubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
  }

  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _imuSubscription?.cancel();

    _scanResultsController.close();
    _connectionStateController.close();
    _sensorDataController.close();
  }
}