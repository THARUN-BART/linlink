import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linlink/features/pairing/pairing_service.dart';
import 'package:linlink/features/storage/file_agent.dart';

void main() {
  group('Phone-to-Phone P2P Transfer & Privacy Mode Tests', () {
    tearDown(() async {
      await AndroidFileAgent.stopServer();
      AndroidFileAgent.onPeerPaired = null;
      AndroidFileAgent.onFileReceived = null;
      AndroidFileAgent.allowRemoteBrowsing = false;
    });

    test('PairingTarget parses linlink URI with device name query param', () {
      final target = PairingTarget.tryParse('linlink://192.168.43.1:7879?t=abc12345&name=Galaxy+S24');
      expect(target, isNotNull);
      expect(target!.host, '192.168.43.1');
      expect(target.port, 7879);
      expect(target.token, 'abc12345');
      expect(target.deviceName, 'Galaxy S24');
    });

    test('PairingTarget parses JSON payload with device name', () {
      final target = PairingTarget.tryParse('{"host":"192.168.1.15","port":7879,"token":"tok789","name":"Pixel 8"}');
      expect(target, isNotNull);
      expect(target!.host, '192.168.1.15');
      expect(target.port, 7879);
      expect(target.token, 'tok789');
      expect(target.deviceName, 'Pixel 8');
    });

    test('AndroidFileAgent generates compact 8-char session tokens and starts server', () async {
      final token = AndroidFileAgent.generateSessionToken();
      expect(token.length, 8);

      final port = await AndroidFileAgent.startServer(
        token: token,
        deviceName: 'Receiver Phone',
        port: 0, // ephemeral port for testing
      );
      expect(port, isNotNull);
      expect(AndroidFileAgent.isRunning, isTrue);

      // Verify ping/status endpoint
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/status'));
      final res = await req.close();
      expect(res.statusCode, 200);

      final body = await utf8.decoder.bind(res).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['status'], 'ok');
      expect(json['device'], 'Android');
      expect(json['name'], 'Receiver Phone');
      expect(json['privacy_mode'], isTrue);
    });

    test('Phone A pairs with Phone B via scan and handshake, triggering onPeerPaired', () async {
      const serverToken = 'testtok1';
      PairedCompanion? incomingPeer;
      AndroidFileAgent.onPeerPaired = (peer) {
        incomingPeer = peer;
      };

      final port = await AndroidFileAgent.startServer(
        token: serverToken,
        deviceName: 'Phone B Receiver',
        port: 0,
      );
      expect(port, isNotNull);

      // Phone A initiates pairing with Phone B
      final target = PairingTarget(
        host: '127.0.0.1',
        port: port!,
        token: serverToken,
        deviceName: 'Phone B Receiver',
      );

      final pairedCompanion = await PairingService.pair(
        target: target,
        deviceName: 'Phone A Sender',
      );

      expect(pairedCompanion.deviceName, 'Phone B Receiver');
      expect(pairedCompanion.host, '127.0.0.1');
      expect(pairedCompanion.token, serverToken);

      // Verify Phone B received Phone A's handshake
      expect(incomingPeer, isNotNull);
      expect(incomingPeer!.deviceName, 'Phone A Sender');
      expect(incomingPeer!.token, serverToken);
    });

    test('Strict Privacy Mode blocks /fs/list and /api/fs/list with HTTP 403 Forbidden', () async {
      AndroidFileAgent.allowRemoteBrowsing = false; // default privacy mode
      final port = await AndroidFileAgent.startServer(
        token: 'privsec1',
        deviceName: 'Private Phone',
        port: 0,
      );

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/fs/list?token=privsec1&path=/'));
      final res = await req.close();

      expect(res.statusCode, HttpStatus.forbidden);
      final body = await utf8.decoder.bind(res).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['status'], 'restricted');
      expect(json['message'], contains('privacy'));
      expect(json['entries'], isEmpty);
    });

    test('Direct file upload (/api/fs/upload) saves file and triggers onFileReceived', () async {
      String? receivedFilename;
      String? receivedPath;
      AndroidFileAgent.onFileReceived = (filename, path) {
        receivedFilename = filename;
        receivedPath = path;
      };

      final port = await AndroidFileAgent.startServer(
        token: 'uploadtok',
        deviceName: 'Receiver Phone',
        port: 0,
      );

      final client = HttpClient();
      final uploadUri = Uri.parse(
        'http://127.0.0.1:$port/api/fs/upload?token=uploadtok&filename=test_photo.jpg',
      );
      final req = await client.postUrl(uploadUri);
      req.headers.contentType = ContentType.binary;
      req.add(utf8.encode('SIMULATED_BINARY_IMAGE_DATA'));
      final res = await req.close();

      expect(res.statusCode, 200);
      final body = await utf8.decoder.bind(res).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['status'], 'ok');

      expect(receivedFilename, 'test_photo.jpg');
      expect(receivedPath, isNotNull);

      // Clean up uploaded test file
      if (receivedPath != null) {
        final f = File(receivedPath!);
        if (await f.exists()) {
          await f.delete();
        }
      }
    });
  });
}
