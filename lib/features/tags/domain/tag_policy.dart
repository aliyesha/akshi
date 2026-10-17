/// Product-wide constraints for reusable domain tags.
///
/// Keeping the limit in the domain layer lets persistence, controllers, and
/// presentation share one rule instead of duplicating a UI-only constant.
abstract final class TagPolicy {
  static const int maxCount = 10;

  static int remaining(int currentCount) =>
      (maxCount - currentCount).clamp(0, maxCount).toInt();

  static bool canCreate(int currentCount) => currentCount < maxCount;
}

/// Raised when a create operation races with, or bypasses, the visible limit.
class TagLimitReachedException implements Exception {
  const TagLimitReachedException();

  @override
  String toString() =>
      'You already have ${TagPolicy.maxCount} tags. Delete one or reuse an existing tag.';
}
