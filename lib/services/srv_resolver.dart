import 'package:basic_utils/basic_utils.dart' as dns;

/// One answer from an RFC 6186 SRV lookup.
class SrvTarget {
  const SrvTarget({
    required this.priority,
    required this.weight,
    required this.port,
    required this.target,
  });

  final int priority;
  final int weight;
  final int port;
  final String target;

  /// RFC 6186 §5: a lone SRV record with Target "." means the service is
  /// explicitly declared unavailable — distinct from no record existing.
  bool get isNotOffered => target == '.';
}

/// Parses one SRV record's raw presentation-format `data` string
/// (`"<priority> <weight> <port> <target>"`, as returned by the DNS-over-
/// HTTPS provider `basic_utils` queries), stripping the target's trailing
/// root dot. Returns null if [raw] isn't a well-formed SRV record.
SrvTarget? parseSrvRecordData(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+'));
  if (parts.length != 4) return null;
  final priority = int.tryParse(parts[0]);
  final weight = int.tryParse(parts[1]);
  final port = int.tryParse(parts[2]);
  if (priority == null || weight == null || port == null) return null;
  var target = parts[3];
  if (target.length > 1 && target.endsWith('.')) {
    target = target.substring(0, target.length - 1);
  }
  return SrvTarget(priority: priority, weight: weight, port: port, target: target);
}

/// Picks the most-preferred usable target: lowest priority number wins
/// (RFC 2782); a target of "." ("not offered") is never returned. Returns
/// null if [targets] is empty or every entry is "not offered".
SrvTarget? pickBestTarget(List<SrvTarget> targets) {
  final usable = targets.where((t) => !t.isNotOffered).toList()
    ..sort((a, b) => a.priority.compareTo(b.priority));
  return usable.isEmpty ? null : usable.first;
}

/// Looks up SRV records for a fully-qualified service name (e.g.
/// `_imaps._tcp.example.com`).
abstract class SrvResolver {
  Future<List<SrvTarget>> lookup(String serviceName);
}

/// Real implementation, backed by `basic_utils`'s DNS-over-HTTPS lookup
/// (the same mechanism `enough_mail`'s own MX-based discovery already uses
/// in this codebase).
class DnsSrvResolver implements SrvResolver {
  @override
  Future<List<SrvTarget>> lookup(String serviceName) async {
    final records = await dns.DnsUtils.lookupRecord(serviceName, dns.RRecordType.SRV);
    if (records == null) return [];
    return records.map((r) => parseSrvRecordData(r.data)).whereType<SrvTarget>().toList();
  }
}
