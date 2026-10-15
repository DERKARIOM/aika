import 'dart:io';
import 'dart:typed_data';

import 'package:localsend_app/util/link_download/link_problem.dart';

/// Longest link accepted, far above any real media link.
const maxLinkLength = 4096;

final _urlInText = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
final _bareDomain = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,63}(:\d{1,5})?([/?#].*)?$', caseSensitive: false);

/// Local-only host names that never belong to a public site.
const _localSuffixes = ['.localhost', '.local', '.internal', '.lan', '.home.arpa', '.intranet', '.corp'];

/// Turns what the user pasted into a safe-looking web address.
///
/// - keeps the first `http(s)://` link of a shared text ("Regarde ça :
///   https://…");
/// - adds `https://` to a bare domain (`exemple.org/fichier.pdf`);
/// - refuses other schemes, credentials in the link and local addresses
///   written literally (the resolved address is checked again before
///   connecting, see [resolvePublicAddress]);
/// - drops the `#fragment`, which is never sent to the server.
///
/// Throws a [LinkDownloadException] when the link is refused.
Uri parseUserLink(String input) {
  var text = input.trim();
  if (text.isEmpty) {
    throw const LinkDownloadException(LinkProblem.empty);
  }
  if (text.length > maxLinkLength) {
    throw const LinkDownloadException(LinkProblem.malformed);
  }

  final embedded = _urlInText.firstMatch(text);
  if (embedded != null) {
    text = embedded.group(0)!;
    // Trailing punctuation of the surrounding sentence.
    while (text.isNotEmpty && _endsWithSentencePunctuation(text)) {
      text = text.substring(0, text.length - 1);
    }
  } else if (text.contains(':') && !_bareDomain.hasMatch(text)) {
    // `javascript:…`, `file:…`, `content://…`, `ftp://…`
    final scheme = text.split(':').first.toLowerCase();
    if (RegExp(r'^[a-z][a-z0-9+.-]*$').hasMatch(scheme) && scheme != 'http' && scheme != 'https') {
      throw const LinkDownloadException(LinkProblem.unsupportedScheme);
    }
    throw const LinkDownloadException(LinkProblem.malformed);
  } else if (_bareDomain.hasMatch(text)) {
    text = 'https://$text';
  } else {
    throw const LinkDownloadException(LinkProblem.malformed);
  }

  return checkLink(Uri.tryParse(text));
}

/// Checks a link (typed by the user or received in a redirection) before
/// any request: scheme, host, credentials and literal local addresses.
Uri checkLink(Uri? uri, {Set<String> trustedHosts = const {}}) {
  if (uri == null || !uri.hasScheme) {
    throw const LinkDownloadException(LinkProblem.malformed);
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const LinkDownloadException(LinkProblem.unsupportedScheme);
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty || host.contains('%')) {
    throw const LinkDownloadException(LinkProblem.malformed);
  }
  if (uri.userInfo.isNotEmpty) {
    throw const LinkDownloadException(LinkProblem.credentialsInUrl);
  }
  if (uri.hasPort && (uri.port <= 0 || uri.port > 65535)) {
    throw const LinkDownloadException(LinkProblem.malformed);
  }
  if (trustedHosts.contains(host)) {
    return uri.removeFragment();
  }
  if (host == 'localhost' || _localSuffixes.any(host.endsWith) || !host.contains('.') && !host.contains(':')) {
    throw const LinkDownloadException(LinkProblem.localAddress);
  }
  final literal = InternetAddress.tryParse(host);
  if (literal != null && isNonPublicAddress(literal)) {
    throw const LinkDownloadException(LinkProblem.localAddress);
  }
  return uri.removeFragment();
}

/// Resolves [host] and returns the address to connect to, refusing hosts
/// that resolve to a non-public address (this device, the local network,
/// cloud metadata endpoints, ...). The caller must connect to the returned
/// address itself so a second DNS answer cannot point elsewhere (DNS
/// rebinding).
///
/// [trustedHosts] exists for tests that serve files from `127.0.0.1`; the
/// app never passes it.
Future<InternetAddress> resolvePublicAddress(String host, {Set<String> trustedHosts = const {}}) async {
  final literal = InternetAddress.tryParse(host);
  final List<InternetAddress> addresses;
  if (literal != null) {
    addresses = [literal];
  } else {
    try {
      addresses = await InternetAddress.lookup(host).timeout(const Duration(seconds: 10));
    } on SocketException {
      throw const LinkDownloadException(LinkProblem.network);
    } catch (_) {
      throw const LinkDownloadException(LinkProblem.timeout);
    }
  }
  if (addresses.isEmpty) {
    throw const LinkDownloadException(LinkProblem.network);
  }
  // Refuse when ANY answer is non-public: a host mixing public and private
  // addresses is a classic way to reach the local network.
  if (!trustedHosts.contains(host.toLowerCase()) && addresses.any(isNonPublicAddress)) {
    throw const LinkDownloadException(LinkProblem.localAddress);
  }
  return addresses.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => addresses.first);
}

/// Whether [address] is not reachable on the public Internet: loopback,
/// private, link-local, carrier-grade NAT, multicast, documentation and
/// reserved ranges, plus IPv6 forms embedding such an IPv4 address.
bool isNonPublicAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 4) {
    return _isNonPublicIpv4(b);
  }
  if (b.length != 16) {
    return true;
  }

  final allZeroPrefix = b.sublist(0, 10).every((x) => x == 0);
  // :: and ::1
  if (allZeroPrefix && b[10] == 0 && b[11] == 0 && b.sublist(12, 15).every((x) => x == 0) && b[15] <= 1) {
    return true;
  }
  // ::ffff:a.b.c.d (IPv4-mapped) and ::a.b.c.d (IPv4-compatible)
  if (allZeroPrefix && ((b[10] == 0xff && b[11] == 0xff) || (b[10] == 0 && b[11] == 0))) {
    return _isNonPublicIpv4(b.sublist(12, 16));
  }
  // 64:ff9b::/96 (NAT64) embeds an IPv4 address.
  if (b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b && b.sublist(4, 12).every((x) => x == 0)) {
    return _isNonPublicIpv4(b.sublist(12, 16));
  }
  // 2002::/16 (6to4) embeds an IPv4 address.
  if (b[0] == 0x20 && b[1] == 0x02) {
    return _isNonPublicIpv4(b.sublist(2, 6));
  }
  return (b[0] & 0xfe) == 0xfc || // fc00::/7 unique local
      (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) || // fe80::/10 link-local
      (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) || // fec0::/10 site-local (deprecated)
      b[0] == 0xff || // ff00::/8 multicast
      (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8) || // 2001:db8::/32 documentation
      (b[0] == 0x01 && b[1] == 0x00 && b.sublist(2, 8).every((x) => x == 0)); // 100::/64 discard
}

bool _isNonPublicIpv4(Uint8List b) {
  final a0 = b[0], a1 = b[1], a2 = b[2];
  return a0 == 0 || // 0.0.0.0/8
      a0 == 10 || // 10/8
      a0 == 127 || // loopback
      (a0 == 100 && a1 >= 64 && a1 <= 127) || // 100.64/10 carrier-grade NAT
      (a0 == 169 && a1 == 254) || // link-local, cloud metadata
      (a0 == 172 && a1 >= 16 && a1 <= 31) || // 172.16/12
      (a0 == 192 && a1 == 0 && a2 == 0) || // 192.0.0/24
      (a0 == 192 && a1 == 0 && a2 == 2) || // TEST-NET-1
      (a0 == 192 && a1 == 88 && a2 == 99) || // 6to4 relay
      (a0 == 192 && a1 == 168) || // 192.168/16
      (a0 == 198 && (a1 == 18 || a1 == 19)) || // benchmarking
      (a0 == 198 && a1 == 51 && a2 == 100) || // TEST-NET-2
      (a0 == 203 && a1 == 0 && a2 == 113) || // TEST-NET-3
      a0 >= 224; // multicast, reserved, broadcast
}

/// Whether the last character closes the surrounding sentence rather than
/// the link (`(voir https://exemple.org/a.pdf).`); a `)` that closes a
/// parenthesis opened inside the link is kept.
bool _endsWithSentencePunctuation(String text) {
  final last = text[text.length - 1];
  if (last == ')') {
    return ')'.allMatches(text).length > '('.allMatches(text).length;
  }
  return '.,;:!?]}»\'"'.contains(last);
}
