import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:localsend_isolates/rust/api/chat.dart';
import 'package:localsend_isolates/rust/api/server.dart';
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end check of the chat WebSocket through the generated Dart
/// bindings and the real Rust library (not the isolate plumbing).
///
/// Needs the native library built for the host:
///   cd packages/localsend_isolates/rust && cargo build
/// and `openssl` on the PATH; skipped otherwise.
final _library = p.normalize(
  p.join(Directory.current.path, '..', 'packages', 'localsend_isolates', 'rust', 'target', 'debug', 'librust_lib_localsend_app.so'),
);

class _Identity {
  final String cert;
  final String key;
  final String fingerprint;

  _Identity(this.cert, this.key, this.fingerprint);
}

Future<_Identity> _identity(Directory dir, String name) async {
  final keyPath = p.join(dir.path, '$name.key');
  final certPath = p.join(dir.path, '$name.crt');
  final gen = await Process.run('openssl', [
    'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
    '-subj', '/CN=$name', '-keyout', keyPath, '-out', certPath,
  ]);
  expect(gen.exitCode, 0, reason: '${gen.stderr}');
  final fp = await Process.run('openssl', ['x509', '-in', certPath, '-noout', '-fingerprint', '-sha256']);
  final fingerprint = (fp.stdout as String).split('=').last.trim().replaceAll(':', '').toUpperCase();
  return _Identity(File(certPath).readAsStringSync(), File(keyPath).readAsStringSync(), fingerprint);
}

Future<T> _next<T>(StreamIterator<RsChatEvent> events) async {
  final hasNext = await events.moveNext().timeout(const Duration(seconds: 5));
  expect(hasNext, true);
  expect(events.current, isA<T>());
  return events.current as T;
}

void main() {
  final available = Platform.isLinux && File(_library).existsSync() && Process.runSync('which', ['openssl']).exitCode == 0;

  group('chat hub (native)', skip: available ? false : 'native library not built or openssl missing', () {
    late Directory tmp;
    late _Identity alice;
    late _Identity bob;

    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(_library));
      tmp = Directory.systemTemp.createTempSync('aika_chat_native');
      alice = await _identity(tmp, 'alice');
      bob = await _identity(tmp, 'bob');
    });

    tearDownAll(() => tmp.deleteSync(recursive: true));

    test('Should exchange frames between two hubs over mTLS', () async {
      const port = 47851;
      final server = await startServer(
        port: port,
        tls: TlsConfig(cert: bob.cert, privateKey: bob.key),
        alias: 'Bob',
        version: '2.1',
        fingerprint: bob.fingerprint,
      );
      addTearDown(server.stop);
      final bobHub = createChatHub(cert: bob.cert, privateKey: bob.key);
      server.attachChatHub(hub: bobHub);
      final aliceHub = createChatHub(cert: alice.cert, privateKey: alice.key);
      final bobEvents = StreamIterator(bobHub.listen());
      final aliceEvents = StreamIterator(aliceHub.listen());

      final aliceId = await aliceHub.connect(ip: '127.0.0.1', port: port, fingerprint: bob.fingerprint);

      final atAlice = await _next<RsChatEvent_Connected>(aliceEvents);
      expect((atAlice.connectionId, atAlice.fingerprint, atAlice.outbound), (aliceId, bob.fingerprint, true));
      final atBob = await _next<RsChatEvent_Connected>(bobEvents);
      expect((atBob.fingerprint, atBob.outbound), (alice.fingerprint, false));

      await aliceHub.send(connectionId: aliceId, text: '{"t":"typing","on":true}');
      expect((await _next<RsChatEvent_Message>(bobEvents)).text, '{"t":"typing","on":true}');

      await bobHub.send(connectionId: atBob.connectionId, text: 'réponse');
      expect((await _next<RsChatEvent_Message>(aliceEvents)).text, 'réponse');

      await aliceHub.close(connectionId: aliceId);
      await _next<RsChatEvent_Disconnected>(aliceEvents);
      await _next<RsChatEvent_Disconnected>(bobEvents);
    });

    test('Should refuse a device presenting another certificate', () async {
      const port = 47852;
      // Bob's address, but Alice's certificate answers.
      final server = await startServer(
        port: port,
        tls: TlsConfig(cert: alice.cert, privateKey: alice.key),
        alias: 'Mallory',
        version: '2.1',
        fingerprint: alice.fingerprint,
      );
      addTearDown(server.stop);
      server.attachChatHub(
        hub: createChatHub(cert: alice.cert, privateKey: alice.key),
      );
      final hub = createChatHub(cert: bob.cert, privateKey: bob.key);

      await expectLater(
        hub.connect(ip: '127.0.0.1', port: port, fingerprint: bob.fingerprint),
        throwsA(isA<RsChatError_FingerprintMismatch>()),
      );
    });

    test('Should report a server without chat as unsupported (v1.0.3)', () async {
      const port = 47853;
      final server = await startServer(
        port: port,
        tls: TlsConfig(cert: bob.cert, privateKey: bob.key),
        alias: 'Bob',
        version: '2.1',
        fingerprint: bob.fingerprint,
      );
      addTearDown(server.stop);
      final hub = createChatHub(cert: alice.cert, privateKey: alice.key);

      await expectLater(
        hub.connect(ip: '127.0.0.1', port: port, fingerprint: bob.fingerprint),
        throwsA(isA<RsChatError_Unsupported>().having((e) => e.status, 'status', 404)),
      );
    });
  });
}
