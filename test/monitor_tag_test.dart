import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tag mapping round trips its stable source color', () {
    final createdAt = DateTime.utc(2026, 8, 19);
    final tag = MonitorTag(
      id: 'tag-id',
      name: 'Production',
      colorArgb: TagPalette.purple,
      createdAt: createdAt,
    );

    final restored = MonitorTag.fromMap(tag.toMap());

    expect(restored.id, tag.id);
    expect(restored.name, 'Production');
    expect(restored.colorArgb, TagPalette.purple);
    expect(restored.createdAt, createdAt.toLocal());
  });

  test('the curated palette contains ten distinct colors', () {
    expect(TagPalette.presets, hasLength(10));
    expect(TagPalette.presets.toSet(), hasLength(10));
  });
}
