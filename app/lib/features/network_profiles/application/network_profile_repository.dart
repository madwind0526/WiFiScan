import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

class NetworkProfileRepository {
  const NetworkProfileRepository();

  Future<List<NetworkProfile>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => NetworkProfile.fromJson(item.cast<String, Object?>()))
          .where((profile) => profile.ssid.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> save(List<NetworkProfile> profiles) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
      flush: true,
    );
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}network_profiles.json',
    );
  }
}
