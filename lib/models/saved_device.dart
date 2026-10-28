/// 已保存的保护板设备（SharedPreferences 持久化）。
class SavedDevice {
  final String id;
  final String name;
  final int lastUsed;

  const SavedDevice({
    required this.id,
    this.name = '',
    this.lastUsed = 0,
  });

  String get label => name.trim().isEmpty ? id : name.trim();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastUsed': lastUsed,
      };

  static SavedDevice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final name = raw['name'];
    final lastUsed = raw['lastUsed'];
    return SavedDevice(
      id: id,
      name: name is String ? name : '',
      lastUsed: lastUsed is int ? lastUsed : 0,
    );
  }
}
