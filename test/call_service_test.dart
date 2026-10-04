import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linlink/features/call/call_service.dart';
import 'package:linlink/features/pairing/pairing_service.dart';
import 'package:linlink/features/storage/file_agent.dart';

void main() {
  group('Remote Call & Directory Listing Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('linlink_test_fs_');
      // Create test files and folders
      await Directory('${tempDir.path}/SubFolder').create();
      await File('${tempDir.path}/document.pdf').writeAsString('Hello PDF content');
      await File('${tempDir.path}/photo.jpg').writeAsBytes([1, 2, 3, 4, 5]);
    });

    tearDown(() async {
      await AndroidFileAgent.stopServer();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('CallService state transitions and duration formatting', () {
      expect(CallService.formatDuration(0), '00:00');
      expect(CallService.formatDuration(65), '01:05');
      expect(CallService.formatDuration(3600), '60:00');

      // Test incoming call handling
      CallService.handleIncomingCall(callerName: 'Linux Workstation');
      expect(CallService.state, CallState.ringing);
      expect(CallService.remoteDeviceName, 'Linux Workstation');

      // Test mute & speaker toggles
      expect(CallService.isMuted, false);
      CallService.toggleMute();
      expect(CallService.isMuted, true);
      CallService.toggleMute();
      expect(CallService.isMuted, false);

      expect(CallService.isSpeakerOn, true);
      CallService.toggleSpeaker();
      expect(CallService.isSpeakerOn, false);
      CallService.toggleSpeaker();
      expect(CallService.isSpeakerOn, true);

      // Hangup
      CallService.hangup();
      expect(CallService.state, CallState.ended);
    });

    test('AndroidFileAgent handles call signaling endpoints (/call/invite, /call/status, /call/hangup)', () async {
      AndroidFileAgent.allowRemoteBrowsing = true;
      final port = await AndroidFileAgent.startServer(
        token: 'testtoken',
        deviceName: 'Test Phone',
        port: 0,
      );
      expect(port, isNotNull);

      final client = HttpClient();

      // Test Call Status endpoint
      final statusUri = Uri.parse('http://127.0.0.1:$port/call/status?token=testtoken');
      final statusReq = await client.getUrl(statusUri);
      final statusRes = await statusReq.close();
      expect(statusRes.statusCode, 200);

      // Test Call Invite endpoint
      final inviteUri = Uri.parse('http://127.0.0.1:$port/call/invite?token=testtoken');
      final inviteReq = await client.postUrl(inviteUri);
      inviteReq.headers.contentType = ContentType.json;
      inviteReq.write('{"caller":"Linux Companion","action":"call"}');
      final inviteRes = await inviteReq.close();
      expect(inviteRes.statusCode, 200);
      expect(CallService.state, CallState.ringing);

      // Test Call Hangup endpoint
      final hangupUri = Uri.parse('http://127.0.0.1:$port/call/hangup?token=testtoken');
      final hangupReq = await client.postUrl(hangupUri);
      final hangupRes = await hangupReq.close();
      expect(hangupRes.statusCode, 200);
      expect(CallService.state, CallState.ended);
    });

    test('AndroidFileAgent /fs/list returns both directories and files with sizes and types', () async {
      AndroidFileAgent.allowRemoteBrowsing = true;
      final port = await AndroidFileAgent.startServer(
        token: 'testtoken',
        deviceName: 'Test Phone',
        port: 0,
      );

      final client = HttpClient();
      final listUri = Uri.parse('http://127.0.0.1:$port/fs/list?token=testtoken&path=${Uri.encodeComponent(tempDir.path)}');
      final listReq = await client.getUrl(listUri);
      final listRes = await listReq.close();
      expect(listRes.statusCode, 200);

      final body = await listRes.transform(const SystemEncoding().decoder).join();
      expect(body, contains('"is_dir":true'));
      expect(body, contains('"is_dir":false'));
      expect(body, contains('SubFolder'));
      expect(body, contains('document.pdf'));
      expect(body, contains('photo.jpg'));
    });

    test('AndroidFileAgent /call/dial initiates remote cellular call with PC audio bridge', () async {
      AndroidFileAgent.allowRemoteBrowsing = true;
      final port = await AndroidFileAgent.startServer(
        token: 'testtoken',
        deviceName: 'Test Phone',
        port: 0,
      );

      final client = HttpClient();
      final dialUri = Uri.parse('http://127.0.0.1:$port/call/dial?token=testtoken');
      final dialReq = await client.postUrl(dialUri);
      dialReq.headers.contentType = ContentType.json;
      dialReq.write('{"phone_number":"+15551234567","caller":"Linux Companion"}');
      final dialRes = await dialReq.close();
      expect(dialRes.statusCode, 200);

      final body = await dialRes.transform(const SystemEncoding().decoder).join();
      expect(body, contains('dialed_number'));
      expect(body, contains('+15551234567'));
      expect(CallService.state, CallState.inCall);
      expect(CallService.dialedNumber, '+15551234567');
    });
  });
}
