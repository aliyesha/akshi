import 'package:akshi/features/monitors/application/monitor_controller.dart';
import 'package:akshi/features/monitors/domain/hostname.dart';
import 'package:akshi/features/monitors/domain/monitor_entry.dart';
import 'package:akshi/features/tags/application/tag_controller.dart';
import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:akshi/features/tags/presentation/tag_editor_sheet.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class MonitorFormScreen extends ConsumerStatefulWidget {
  const MonitorFormScreen({this.monitorId, super.key});

  final String? monitorId;

  @override
  ConsumerState<MonitorFormScreen> createState() => _MonitorFormScreenState();
}

class _MonitorFormScreenState extends ConsumerState<MonitorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostname = TextEditingController();
  final _label = TextEditingController();
  final _port = TextEditingController(text: '443');
  final _selectedTagIds = <String>{};
  var _enabled = true;
  var _initialized = false;
  var _saving = false;

  @override
  void dispose() {
    _hostname.dispose();
    _label.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(monitorControllerProvider).value ?? const <MonitorEntry>[];
    final tags = ref.watch(tagControllerProvider).value ?? const <MonitorTag>[];
    final editing = widget.monitorId != null;
    final original = editing ? _find(items, widget.monitorId!) : null;
    if (!_initialized && (!editing || original != null)) {
      _initialized = true;
      if (original != null) {
        _hostname.text = original.hostname;
        _label.text = original.label ?? '';
        _port.text = original.port.toString();
        _enabled = original.enabled;
        _selectedTagIds.addAll(original.tags.map((tag) => tag.id));
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        title: Text(editing ? 'Edit monitor' : 'Add monitor'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              _Intro(editing: editing),
              const SizedBox(height: 28),
              TextFormField(
                controller: _hostname,
                autofocus: !editing,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Domain or hostname',
                  hintText: 'example.com',
                  prefixIcon: Icon(Icons.public_rounded),
                ),
                validator: (value) => validateHostname(value ?? ''),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _label,
                      textInputAction: TextInputAction.next,
                      maxLength: 48,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'Optional',
                        prefixIcon: Icon(LucideIcons.tag),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(labelText: 'Port'),
                      validator: (value) {
                        final port = int.tryParse(value ?? '');
                        if (port == null || port < 1 || port > 65535) {
                          return '1–65535';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _save(original),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Tags',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Optional organization',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _createTag(),
                    icon: const Icon(LucideIcons.plus, size: 17),
                    label: const Text('New tag'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (tags.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'No tags yet. Create one when you need it.',
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags
                      .map(
                        (tag) => TagPill(
                          tag: tag,
                          selected: _selectedTagIds.contains(tag.id),
                          onTap: () => _toggleTag(tag.id),
                        ),
                      )
                      .toList(),
                ),
              if (editing) ...<Widget>[
                const SizedBox(height: 18),
                SwitchListTile(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  title: const Text('Expiry reminders'),
                  subtitle: const Text(
                    'Keep local reminders active for this endpoint',
                  ),
                  secondary: const Icon(LucideIcons.bell_ring),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
              ],
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(original),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(editing ? LucideIcons.save : LucideIcons.plus),
                label: Text(
                  _saving
                      ? 'Checking…'
                      : editing
                      ? 'Save changes'
                      : 'Add and check',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Akshi checks from this device. No account or remote monitoring service is used.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleTag(String id) {
    setState(() {
      if (!_selectedTagIds.add(id)) _selectedTagIds.remove(id);
    });
  }

  Future<void> _createTag() async {
    final draft = await showTagEditor(context);
    if (draft == null || !mounted) return;
    try {
      final tag = await ref
          .read(tagControllerProvider.notifier)
          .create(name: draft.name, colorArgb: draft.colorArgb);
      if (mounted) setState(() => _selectedTagIds.add(tag.id));
    } on Object catch (error) {
      if (!mounted) return;
      final duplicate = error.toString().contains('UNIQUE constraint failed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            duplicate ? 'A tag with that name already exists.' : '$error',
          ),
        ),
      );
    }
  }

  Future<void> _save(MonitorEntry? original) async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(monitorControllerProvider.notifier);
      final MonitorEntry saved;
      final label = _label.text.trim();
      if (original == null) {
        saved = await controller.add(
          hostname: _hostname.text,
          port: int.parse(_port.text),
          label: label.isEmpty ? null : label,
          tagIds: _selectedTagIds,
        );
      } else {
        saved = await controller.updateMonitor(
          original.copyWith(
            hostname: normalizeHostname(_hostname.text),
            port: int.parse(_port.text),
            label: label.isEmpty ? null : label,
            enabled: _enabled,
          ),
          tagIds: _selectedTagIds,
        );
      }
      if (mounted) context.go('/monitor/${saved.id}');
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      setState(() => _saving = false);
    }
  }

  MonitorEntry? _find(List<MonitorEntry> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  String _friendlyError(Object error) {
    final value = error.toString();
    if (value.contains('UNIQUE constraint failed')) {
      return 'That endpoint is already being monitored.';
    }
    return value.replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
  }
}

Widget _backButton(BuildContext context) => IconButton(
  tooltip: 'Back',
  onPressed: () {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  },
  icon: const Icon(LucideIcons.chevron_left),
);

class _Intro extends StatelessWidget {
  const _Intro({required this.editing});
  final bool editing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        editing ? 'Update the endpoint' : 'Watch a new endpoint',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        'Akshi will look up the registration date and inspect the live TLS certificate.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}
