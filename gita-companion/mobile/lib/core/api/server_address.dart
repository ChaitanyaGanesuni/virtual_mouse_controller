/// The AI teacher's server address.
///
/// Built into the app with `--dart-define=API_BASE_URL=https://...`, or
/// entered by the user in Settings. Only HTTPS is accepted, except for a
/// server on this device or the Android emulator's host during development.
library;

const builtInServerAddress = String.fromEnvironment('API_BASE_URL');

const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

enum ServerAddressProblem { invalid, httpsRequired }

String normalizeServerAddress(String input) {
  var s = input.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Null when the address is acceptable (an empty address is acceptable: it
/// means "use the built-in address").
ServerAddressProblem? checkServerAddress(String input) {
  final s = normalizeServerAddress(input);
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty || uri.hasQuery || uri.hasFragment) {
    return ServerAddressProblem.invalid;
  }
  if (uri.scheme == 'https') return null;
  if (uri.scheme == 'http') {
    return _localHosts.contains(uri.host) ? null : ServerAddressProblem.httpsRequired;
  }
  return ServerAddressProblem.invalid;
}

/// The address to use: the user's choice if valid, else the built-in one.
String effectiveServerAddress(String userChoice, {String builtIn = builtInServerAddress}) {
  final chosen = normalizeServerAddress(userChoice);
  if (chosen.isNotEmpty && checkServerAddress(chosen) == null) return chosen;
  final fallback = normalizeServerAddress(builtIn);
  return checkServerAddress(fallback) == null ? fallback : '';
}
