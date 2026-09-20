import 'package:akshi/app/providers.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final tagControllerProvider =
    AsyncNotifierProvider<TagController, List<MonitorTag>>(TagController.new);

class TagController extends AsyncNotifier<List<MonitorTag>> {
  @override
  Future<List<MonitorTag>> build() => ref.watch(tagRepositoryProvider).all();

  Future<MonitorTag> create({
    required String name,
    required int colorArgb,
  }) async {
    final tag = MonitorTag(
      id: const Uuid().v4(),
      name: name.trim(),
      colorArgb: colorArgb,
      createdAt: DateTime.now(),
    );
    await ref.read(tagRepositoryProvider).save(tag);
    await _reload();
    return tag;
  }

  Future<void> updateTag(MonitorTag tag) async {
    await ref
        .read(tagRepositoryProvider)
        .save(tag.copyWith(name: tag.name.trim()));
    await _reload();
  }

  Future<void> delete(String id) async {
    await ref.read(tagRepositoryProvider).delete(id);
    await _reload();
    ref.invalidate(monitorRepositoryProvider);
  }

  Future<void> _reload() async {
    state = AsyncData(await ref.read(tagRepositoryProvider).all());
  }
}
