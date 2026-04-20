/// A discoverable streaming host (Mac + Apollo/Sunshine-class server).
class HostInfo {
  const HostInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.paired,
  });

  final String id;
  final String name;
  final String address;
  final bool paired;

  factory HostInfo.fromMap(Map<dynamic, dynamic> map) {
    return HostInfo(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      paired: map['paired'] == true,
    );
  }
}
