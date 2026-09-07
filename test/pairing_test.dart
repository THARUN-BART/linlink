import 'package:flutter_test/flutter_test.dart';
import 'package:linlink/features/pairing/pairing_service.dart';

void main() {
  group('PairingTarget parsing', () {
    test('parses linlink URI with custom port', () {
      final target = PairingTarget.tryParse('linlink://192.168.1.50:8080?t=1234abcd');
      expect(target, isNotNull);
      expect(target!.host, '192.168.1.50');
      expect(target.port, 8080);
      expect(target.token, '1234abcd');
    });

    test('parses linlink URI with default port', () {
      final target = PairingTarget.tryParse('linlink://10.0.0.5?t=token999');
      expect(target, isNotNull);
      expect(target!.host, '10.0.0.5');
      expect(target.port, 7878);
      expect(target.token, 'token999');
    });

    test('returns null for invalid URI without token', () {
      final target = PairingTarget.tryParse('linlink://10.0.0.5:7878');
      expect(target, isNull);
    });

    test('returns null for unhandled scheme', () {
      final target = PairingTarget.tryParse('ftp://10.0.0.5:7878?t=123');
      expect(target, isNull);
    });
  });
}
