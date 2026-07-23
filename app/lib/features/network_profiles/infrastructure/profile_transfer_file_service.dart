import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

abstract interface class ProfileTransferFileService {
  Future<bool> save(String content);

  Future<String?> pick();

  /// Path of an image the user picked, for reading a QR code out of it.
  ///
  /// A path rather than bytes, because the barcode decoder reads the file
  /// itself. Returns null when the user cancels.
  Future<String?> pickImagePath();
}

class PlatformProfileTransferFileService implements ProfileTransferFileService {
  const PlatformProfileTransferFileService();

  @override
  Future<bool> save(String content) async {
    final path = await FilePicker.saveFile(
      dialogTitle: '네트워크 프로필 내보내기',
      fileName: 'wifiscan_profiles.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: utf8.encode(content),
    );
    if (path == null) return false;
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsString(content, flush: true);
    }
    return true;
  }

  @override
  Future<String?> pickImagePath() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Wi-Fi QR 이미지 선택',
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  @override
  Future<String?> pick() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '네트워크 프로필 가져오기',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: Platform.isAndroid || Platform.isIOS,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    if (selected.bytes != null) return utf8.decode(selected.bytes!);
    final path = selected.path;
    return path == null ? null : File(path).readAsString();
  }
}
