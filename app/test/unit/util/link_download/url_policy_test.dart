import 'dart:io';

import 'package:localsend_app/util/link_download/link_problem.dart';
import 'package:localsend_app/util/link_download/url_policy.dart';
import 'package:test/test.dart';

Matcher _refused(LinkProblem problem) => throwsA(isA<LinkDownloadException>().having((e) => e.problem, 'problem', problem));

void main() {
  group('parseUserLink', () {
    test('accepts http and https links', () {
      expect(parseUserLink('https://exemple.org/photo.jpg').toString(), 'https://exemple.org/photo.jpg');
      expect(parseUserLink('  http://exemple.org/a.pdf  ').toString(), 'http://exemple.org/a.pdf');
    });

    test('adds https to a bare domain', () {
      expect(parseUserLink('exemple.org/fichier.pdf').toString(), 'https://exemple.org/fichier.pdf');
    });

    test('extracts the link from a shared sentence', () {
      expect(parseUserLink('Regarde ça : https://exemple.org/v.mp4 !').toString(), 'https://exemple.org/v.mp4');
      expect(parseUserLink('(voir https://exemple.org/a.pdf).').toString(), 'https://exemple.org/a.pdf');
      expect(parseUserLink('https://fr.wikipedia.org/wiki/Paris_(France)').toString(), 'https://fr.wikipedia.org/wiki/Paris_(France)');
    });

    test('drops the fragment', () {
      expect(parseUserLink('https://exemple.org/a.pdf#page=2').toString(), 'https://exemple.org/a.pdf');
    });

    test('refuses empty and malformed input', () {
      expect(() => parseUserLink('   '), _refused(LinkProblem.empty));
      expect(() => parseUserLink('pas un lien'), _refused(LinkProblem.malformed));
      expect(() => parseUserLink('a' * (maxLinkLength + 1)), _refused(LinkProblem.malformed));
    });

    test('refuses dangerous schemes', () {
      expect(() => parseUserLink('javascript:alert(1)'), _refused(LinkProblem.unsupportedScheme));
      expect(() => parseUserLink('file:///etc/passwd'), _refused(LinkProblem.unsupportedScheme));
      expect(() => parseUserLink('content://media/external/1'), _refused(LinkProblem.unsupportedScheme));
      expect(() => parseUserLink('ftp://exemple.org/a.zip'), _refused(LinkProblem.unsupportedScheme));
      expect(() => parseUserLink('data:text/html,<b>x</b>'), _refused(LinkProblem.unsupportedScheme));
    });

    test('refuses credentials in the link', () {
      expect(() => parseUserLink('https://user:secret@exemple.org/a.pdf'), _refused(LinkProblem.credentialsInUrl));
    });

    test('refuses local and reserved addresses written literally', () {
      for (final link in [
        'http://localhost/a',
        'http://127.0.0.1/a',
        'http://10.0.0.5/a',
        'http://192.168.1.10:53317/a',
        'http://172.20.0.1/a',
        'http://169.254.169.254/latest/meta-data',
        'http://[::1]/a',
        'http://[fd00::1]/a',
        'http://[::ffff:127.0.0.1]/a',
        'http://nas.local/a',
        'http://router.lan/a',
        'http://intranet/a',
        'http://2130706433/a',
      ]) {
        expect(() => parseUserLink(link), _refused(LinkProblem.localAddress), reason: link);
      }
    });
  });

  group('isNonPublicAddress', () {
    bool blocked(String ip) => isNonPublicAddress(InternetAddress(ip));

    test('blocks private, loopback, link-local and reserved IPv4', () {
      for (final ip in ['0.0.0.0', '10.1.2.3', '100.64.0.1', '127.0.0.1', '169.254.1.1', '172.16.0.1', '172.31.255.255', '192.168.0.1', '198.18.0.1', '224.0.0.1', '255.255.255.255']) {
        expect(blocked(ip), isTrue, reason: ip);
      }
    });

    test('allows public IPv4', () {
      for (final ip in ['1.1.1.1', '8.8.8.8', '172.32.0.1', '100.128.0.1', '93.184.215.14']) {
        expect(blocked(ip), isFalse, reason: ip);
      }
    });

    test('blocks local IPv6 and IPv6 embedding a private IPv4', () {
      for (final ip in ['::', '::1', 'fe80::1', 'fc00::1', 'fd12:3456::1', 'ff02::1', '::ffff:10.0.0.1', '64:ff9b::7f00:1', '2002:c0a8:0101::1', '2001:db8::1']) {
        expect(blocked(ip), isTrue, reason: ip);
      }
    });

    test('allows public IPv6', () {
      expect(blocked('2606:4700:4700::1111'), isFalse);
      expect(blocked('2a00:1450:4007:80b::200e'), isFalse);
    });
  });

  group('resolvePublicAddress', () {
    test('refuses a host name resolving to this device', () async {
      await expectLater(resolvePublicAddress('localhost'), _refused(LinkProblem.localAddress));
    });

    test('allows trusted test hosts', () async {
      final address = await resolvePublicAddress('127.0.0.1', trustedHosts: {'127.0.0.1'});
      expect(address.address, '127.0.0.1');
    });
  });
}
