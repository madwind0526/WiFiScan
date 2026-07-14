import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

abstract interface class ProfileTransferFileService {
  Future<bool> save(String content);

  Future<String?> pick();
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
