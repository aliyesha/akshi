import 'package:akshi/features/tags/domain/tag_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows zero through nine tags and rejects the tenth slot', () {
    expect(TagPolicy.canCreate(0), isTrue);
    expect(TagPolicy.canCreate(9), isTrue);
    expect(TagPolicy.canCreate(10), isFalse);
    expect(TagPolicy.canCreate(11), isFalse);
  });

  test('remaining capacity is clamped to the product boundary', () {
    expect(TagPolicy.remaining(0), 10);
    expect(TagPolicy.remaining(9), 1);
    expect(TagPolicy.remaining(10), 0);
    expect(TagPolicy.remaining(99), 0);
  });
}
