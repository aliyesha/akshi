import 'package:akshi/app/providers.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/tags/domain/domain_tag.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final tagControllerProvider =
    AsyncNotifierProvider<TagController, List<DomainTag>>(TagController.new);

class TagController extends AsyncNotifier<List<DomainTag>> {
  @override
  Future<List<DomainTag>> build() => ref.watch(tagRepositoryProvider).all();

  Future<DomainTag> create({required String name, required int colorArgb}) =>
      ref
          .read(domainRefreshProvider.notifier)
          .runMutation(() => _create(name: name, colorArgb: colorArgb));

  Future<DomainTag> _create({
    required String name,
    required int colorArgb,
  }) async {
    final flow = appLogger.start(
      'tag.create',
      data: <String, Object?>{'colorArgb': colorArgb},
    );
    final tag = DomainTag(
      id: const Uuid().v4(),
      name: name.trim(),
      colorArgb: colorArgb,
      createdAt: DateTime.now(),
    );
    try {
      await ref.read(tagRepositoryProvider).create(tag);
      await _reload();
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
    flow.info('completed');
    return tag;
  }

  Future<void> updateTag(DomainTag tag) => ref
      .read(domainRefreshProvider.notifier)
      .runMutation(() => _updateTag(tag));

  Future<void> _updateTag(DomainTag tag) async {
    final flow = appLogger.start(
      'tag.update',
      data: <String, Object?>{'tagId': tag.id, 'colorArgb': tag.colorArgb},
    );
    try {
      await ref
          .read(tagRepositoryProvider)
          .update(tag.copyWith(name: tag.name.trim()));
      await _reload();
      ref.invalidate(domainControllerProvider);
    } catch (error, stackTrace) {
      flow.error('failed', error, stackTrace);
      rethrow;
    }
    flow.info('completed');
  }

  Future<void> delete(String id) =>
      ref.read(domainRefreshProvider.notifier).runMutation(() => _delete(id));

  Future<void> _delete(String id) async {
    final flow = appLogger.start(
      'tag.delete',
      data: <String, Object?>{'tagId': id},
    );
    try {
      await ref.read(tagRepositoryProvider).delete(id);
      await _reload();
      ref.invalidate(domainRepositoryProvider);
      ref.invalidate(domainControllerProvider);
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
