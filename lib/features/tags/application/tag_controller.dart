import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
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
    final flow = appLogger.start(
      'tag.create',
      data: <String, Object?>{'colorArgb': colorArgb},
    );
    final tag = MonitorTag(
      id: const Uuid().v4(),
      name: name.trim(),
      colorArgb: colorArgb,
      createdAt: DateTime.now(),
    );
    try {
      await ref.read(tagRepositoryProvider).save(tag);
      await _reload();
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
    flow.info('completed');
    return tag;
  }

  Future<void> updateTag(MonitorTag tag) async {
    final flow = appLogger.start(
      'tag.update',
      data: <String, Object?>{'tagId': tag.id, 'colorArgb': tag.colorArgb},
    );
    try {
      await ref
          .read(tagRepositoryProvider)
          .save(tag.copyWith(name: tag.name.trim()));
      await _reload();
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
    flow.info('completed');
  }

  Future<void> delete(String id) async {
    final flow = appLogger.start(
      'tag.delete',
      data: <String, Object?>{'tagId': id},
    );
    try {
      await ref.read(tagRepositoryProvider).delete(id);
      await _reload();
      ref.invalidate(monitorRepositoryProvider);
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
    flow.info('completed');
  }

  Future<void> _reload() async {
    state = AsyncData(await ref.read(tagRepositoryProvider).all());
  }
}
