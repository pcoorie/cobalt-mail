// test/services/srv_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/services/srv_resolver.dart';

void main() {
  group('parseSrvRecordData', () {
    test('parses a well-formed SRV answer and strips the trailing dot', () {
      final target = parseSrvRecordData('0 5 993 imap.example.com.');
      expect(target, isNotNull);
      expect(target!.priority, 0);
      expect(target.weight, 5);
      expect(target.port, 993);
      expect(target.target, 'imap.example.com');
    });

    test('recognizes a "." target as explicitly not offered', () {
      final target = parseSrvRecordData('0 0 0 .');
      expect(target, isNotNull);
      expect(target!.isNotOffered, isTrue);
    });

    test('returns null for malformed data', () {
      expect(parseSrvRecordData('not a valid record'), isNull);
      expect(parseSrvRecordData('0 5 not-a-port imap.example.com.'), isNull);
      expect(parseSrvRecordData(''), isNull);
    });
  });

  group('pickBestTarget', () {
    test('picks the lowest-priority target', () {
      const low = SrvTarget(priority: 0, weight: 1, port: 993, target: 'a.example.com');
      const high = SrvTarget(priority: 10, weight: 1, port: 993, target: 'b.example.com');
      expect(pickBestTarget([high, low]), same(low));
    });

    test('skips "not offered" targets', () {
      const notOffered = SrvTarget(priority: 0, weight: 0, port: 0, target: '.');
      const usable = SrvTarget(priority: 10, weight: 1, port: 993, target: 'a.example.com');
      expect(pickBestTarget([notOffered, usable]), same(usable));
    });

    test('returns null when nothing is usable', () {
      const notOffered = SrvTarget(priority: 0, weight: 0, port: 0, target: '.');
      expect(pickBestTarget([notOffered]), isNull);
      expect(pickBestTarget(const []), isNull);
    });
  });
}
