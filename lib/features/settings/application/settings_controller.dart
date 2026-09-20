import 'package:akshi/app/providers.dart';
import 'package:akshi/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> saveSettings(AppSettings value) async {
    state = AsyncData(value);
    await ref.read(settingsRepositoryProvider).save(value);
  }
}
