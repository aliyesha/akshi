class MonitorTag {
  const MonitorTag({
    required this.id,
    required this.name,
    required this.colorArgb,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int colorArgb;
  final DateTime createdAt;

  MonitorTag copyWith({String? name, int? colorArgb}) => MonitorTag(
    id: id,
    name: name ?? this.name,
    colorArgb: colorArgb ?? this.colorArgb,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name.trim(),
    'color_argb': colorArgb,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory MonitorTag.fromMap(Map<String, Object?> map) => MonitorTag(
    id: map['id']! as String,
    name: map['name']! as String,
    colorArgb: map['color_argb']! as int,
    createdAt: DateTime.parse(map['created_at']! as String).toLocal(),
  );
}

abstract final class TagPalette {
  static const int blue = 0xFF2563EB;
  static const int teal = 0xFF0F766E;
  static const int green = 0xFF16A34A;
  static const int lime = 0xFF65A30D;
  static const int yellow = 0xFFCA8A04;
  static const int orange = 0xFFEA580C;
  static const int red = 0xFFDC2626;
  static const int magenta = 0xFFC026D3;
  static const int purple = 0xFF7C3AED;
  static const int gray = 0xFF64748B;

  static const List<int> presets = <int>[
    blue,
    teal,
    green,
    lime,
    yellow,
    orange,
    red,
    magenta,
    purple,
    gray,
  ];
}
