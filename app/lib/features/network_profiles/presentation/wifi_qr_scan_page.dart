import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wifi_scan/features/network_profiles/domain/wifi_qr_payload.dart';

/// Camera view that reads one Wi-Fi QR code and returns what it holds.
///
/// Android's Wi-Fi settings print exactly this code for a saved network, so it
/// can be handed to the app without the passphrase ever being typed. Nothing is
/// stored here: the payload is returned to the caller, which decides whether to
/// keep it.
class WifiQrScanPage extends StatefulWidget {
  const WifiQrScanPage({super.key});

  @override
  State<WifiQrScanPage> createState() => _WifiQrScanPageState();
}

class _WifiQrScanPageState extends State<WifiQrScanPage> {
  // The camera keeps delivering frames after a hit, so the first accepted code
  // latches this and every later frame is ignored.
  bool _handled = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final payload = parseWifiQr(raw);
      if (payload == null) {
        // Keep scanning, but say why nothing happened.
        if (mounted && _error == null) {
          setState(() => _error = 'Wi-Fi QR 코드가 아닙니다. 공유기나 휴대폰의 Wi-Fi 공유 QR을 비춰 주세요.');
        }
        continue;
      }
      _handled = true;
      Navigator.of(context).pop(payload);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi QR 스캔')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '카메라를 사용할 수 없습니다. 설정에서 카메라 권한을 허용해 주세요.\n\n${error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Text(
                _error ??
                    '휴대폰 설정 → Wi-Fi → 네트워크 → 공유에서 나오는 QR을 비춰 주세요.\n'
                        '읽은 정보는 이 기기에만 저장됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _error == null ? Colors.white : scheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
