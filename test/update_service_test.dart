import 'package:flutter_test/flutter_test.dart';
import 'package:linlink/features/update/update_service.dart';

void main() {
  group('UpdateService Tests', () {
    test('Check for updates returns valid UpdateInfo model', () async {
      final info = await UpdateService.checkForUpdates();
      expect(info.currentVersion, equals('1.0.0'));
      expect(info.tagName, isNotEmpty);
      expect(info.htmlUrl, isNotEmpty);
    });
  });
}
