import 'dart:io';

/// Minimal `.env` support so local secrets (the router admin password) can live
/// in a gitignored `.env` file instead of an OS environment variable.
///
/// No dependency: parses `KEY=VALUE` lines. Real process environment variables
/// still take precedence, so `.env` only fills in what is not already set.
class DotEnv {
  const DotEnv._();

  /// Parses `.env` file [content] into a map.
  ///
  /// Ignores blank lines and `#` comments, splits on the first `=`, trims keys
  /// and values, and strips one layer of matching single/double quotes.
  static Map<String, String> parse(String content) {
    final values = <String, String>{};
    for (var line in content.split(RegExp(r'\r?\n'))) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trimLeft();
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      if (key.isEmpty) continue;
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
    return values;
  }

  /// Finds a `.env` file: an explicit `WIFISCAN_ENV_FILE` path if set,
  /// otherwise the nearest `.env` walking up from [start] (the current
  /// directory by default). Returns null when none exists.
  static File? locate({Directory? start, Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final explicit = env['WIFISCAN_ENV_FILE'];
    if (explicit != null && explicit.isNotEmpty) {
      final file = File(explicit);
      return file.existsSync() ? file : null;
    }
    var dir = start ?? Directory.current;
    for (var depth = 0; depth < 5; depth++) {
      final candidate = File('${dir.path}${Platform.pathSeparator}.env');
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// The process environment overlaid with any `.env` values, where real
  /// environment variables win. Safe to call when no `.env` exists.
  static Map<String, String> merged({
    Map<String, String>? environment,
    Directory? start,
  }) {
    final base = {...(environment ?? Platform.environment)};
    final file = locate(start: start, environment: environment);
    if (file == null) return base;
    try {
      final fromFile = parse(file.readAsStringSync());
      for (final entry in fromFile.entries) {
        base.putIfAbsent(entry.key, () => entry.value);
      }
    } catch (_) {
      // A malformed or unreadable .env should never break startup.
    }
    return base;
  }
}
