import 'package:akshi/features/tags/domain/monitor_tag.dart';
import 'package:akshi/features/tags/domain/tag_policy.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class TagDraft {
  const TagDraft({required this.name, required this.colorArgb});

  final String name;
  final int colorArgb;
}

Future<TagDraft?> showTagEditor(
  BuildContext context, {
  MonitorTag? tag,
  int? currentCount,
}) =>
    showModalBottomSheet<TagDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _TagEditorSheet(tag: tag, currentCount: currentCount),
    );

class _TagEditorSheet extends StatefulWidget {
  const _TagEditorSheet({this.tag, this.currentCount});

  final int? currentCount;
  final MonitorTag? tag;

  @override
  State<_TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<_TagEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _hex;
  late HSVColor _hsv;
  late int _colorArgb;
  var _custom = false;

  @override
  void initState() {
    super.initState();
    _colorArgb = widget.tag?.colorArgb ?? TagPalette.blue;
    _hsv = HSVColor.fromColor(Color(_colorArgb));
    _name = TextEditingController(text: widget.tag?.name ?? '');
    _hex = TextEditingController(text: _hexValue(_colorArgb));
    _custom = !TagPalette.presets.contains(_colorArgb);
  }

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final preview = MonitorTag(
      id: 'preview',
      name: _name.text.trim().isEmpty ? 'Tag preview' : _name.text.trim(),
      colorArgb: _colorArgb,
      createdAt: DateTime.now(),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.tag == null ? 'Create tag' : 'Edit tag',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (widget.tag == null && widget.currentCount != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '${widget.currentCount} of ${TagPolicy.maxCount} used · '
                  '${TagPolicy.remaining(widget.currentCount! + 1)} remaining after this tag',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                autofocus: widget.tag == null,
                maxLength: 24,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tag name',
                  hintText: 'Production',
                  prefixIcon: PhosphorIcon(PhosphorIconsDuotone.tag),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a tag name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              Text('Color', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final color in TagPalette.presets)
                    _ColorChoice(
                      color: Color(color),
                      selected: !_custom && color == _colorArgb,
                      onTap: () => _selectPreset(color),
                    ),
                  _CustomChoice(
                    selected: _custom,
                    color: Color(_colorArgb),
                    onTap: () => setState(() => _custom = true),
                  ),
                ],
              ),
              if (_custom) ...<Widget>[
                const SizedBox(height: 18),
                _ColorSlider(
                  label: 'Hue',
                  value: _hsv.hue,
                  maximum: 360,
                  onChanged: (value) => _setHsv(_hsv.withHue(value)),
                ),
                _ColorSlider(
                  label: 'Saturation',
                  value: _hsv.saturation,
                  maximum: 1,
                  onChanged: (value) => _setHsv(_hsv.withSaturation(value)),
                ),
                _ColorSlider(
                  label: 'Brightness',
                  value: _hsv.value,
                  maximum: 1,
                  onChanged: (value) => _setHsv(_hsv.withValue(value)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _hex,
                  maxLength: 7,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Hex color',
                    hintText: '#2563EB',
                  ),
                  validator: (value) {
                    final normalized = (value ?? '').trim().replaceFirst(
                      '#',
                      '',
                    );
                    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) {
                      return 'Enter a six-digit hex color';
                    }
                    return null;
                  },
                  onFieldSubmitted: _applyHex,
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Text(
                    'Preview',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 12),
                  TagPill(tag: preview),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: Text(widget.tag == null ? 'Create tag' : 'Save tag'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectPreset(int value) {
    setState(() {
      _custom = false;
      _colorArgb = value;
      _hsv = HSVColor.fromColor(Color(value));
      _hex.text = _hexValue(value);
    });
  }

  void _setHsv(HSVColor value) {
    setState(() {
      _custom = true;
      _hsv = value;
      _colorArgb = value.toColor().toARGB32();
      _hex.text = _hexValue(_colorArgb);
    });
  }

  void _applyHex(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    final color = 0xFF000000 | int.parse(normalized, radix: 16);
    setState(() {
      _custom = true;
      _colorArgb = color;
      _hsv = HSVColor.fromColor(Color(color));
      _hex.text = _hexValue(color);
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_custom) _applyHex(_hex.text);
    Navigator.of(context)
        .pop(TagDraft(name: _name.text.trim(), colorArgb: _colorArgb));
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Choose color',
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const PhosphorIcon(
                PhosphorIconsRegular.check,
                size: 19,
                color: Colors.white,
              )
            : null,
      ),
    ),
  );
}

class _CustomChoice extends StatelessWidget {
  const _CustomChoice({
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Custom color',
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: <Color>[
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
          ),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
    ),
  );
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.maximum,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double maximum;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(width: 78, child: Text(label)),
      Expanded(
        child: Slider(
          value: value < 0.0
              ? 0.0
              : value > maximum
              ? maximum
              : value,
          max: maximum,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

String _hexValue(int colorArgb) =>
    '#${(colorArgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
