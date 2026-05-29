// lib/screens/qr_scan_screen.dart — QR現場チェックイン
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../main.dart' show JsColors;

class QrScanResult {
  final String? siteId;
  final String? siteName;
  final String? address;
  final String rawValue;

  const QrScanResult({
    this.siteId,
    this.siteName,
    this.address,
    required this.rawValue,
  });
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  bool _detected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    _detected = true;
    _controller.stop();

    QrScanResult result;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      result = QrScanResult(
        siteId:   json['site_id']   as String?,
        siteName: (json['name'] ?? json['site_name']) as String?,
        address:  json['address']   as String?,
        rawValue: raw,
      );
    } catch (_) {
      // JSONでなければそのままアドレスとして扱う
      result = QrScanResult(rawValue: raw, address: raw);
    }

    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: JsColors.gold,
        title: const Text('QR 現場チェックイン'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'フラッシュ',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            tooltip: 'カメラ切替',
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // スキャン枠
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: JsColors.gold, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // 説明テキスト
          const Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Text(
              '現場のQRコードをスキャン',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const Positioned(
            bottom: 55,
            left: 0,
            right: 0,
            child: Text(
              '現場名・住所が自動入力されます',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
