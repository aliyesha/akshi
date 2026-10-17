import 'package:akshi/app/providers.dart';
import 'package:akshi/core/errors/user_facing_error.dart';
import 'package:akshi/core/logging/app_logger.dart';
import 'package:akshi/core/theme/akshi_theme.dart';
import 'package:akshi/core/widgets/akshi_notice.dart';
import 'package:akshi/core/widgets/offline_notice.dart';
import 'package:akshi/features/domains/application/domain_controller.dart';
import 'package:akshi/features/domains/domain/hostname.dart';
import 'package:akshi/features/domains/domain/domain_entry.dart';
import 'package:akshi/features/domains/domain/tls_endpoint.dart';
import 'package:akshi/features/domains/presentation/widgets/domain_refresh_banner.dart';
import 'package:akshi/features/tags/application/tag_controller.dart';
import 'package:akshi/features/tags/domain/domain_tag.dart';
import 'package:akshi/features/tags/domain/tag_policy.dart';
import 'package:akshi/features/tags/presentation/tag_editor_sheet.dart';
import 'package:akshi/features/tags/presentation/tag_pill.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class DomainFormScreen extends ConsumerStatefulWidget {
  const DomainFormScreen.create({super.key}) : isEditing = false, domainId = '';

  const DomainFormScreen.edit({required this.domainId, super.key})
    : isEditing = true;

  final bool isEditing;
  final String domainId;

  @override
  ConsumerState<DomainFormScreen> createState() => _DomainFormScreenState();
}

class _DomainFormScreenState extends ConsumerState<DomainFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostname = TextEditingController();
  final _tlsHostname = TextEditingController();
  final _label = TextEditingController();
  final _port = TextEditingController(text: '443');
  final _dkimSelectors = TextEditingController();
  final _selectedTagIds = <String>{};
  var _remindersEnabled = true;
  var _initialized = false;
  var _saving = false;
  var _progress = const DomainSaveProgress.initial();
  var _checksCertificate = false;
  var _checksEmail = false;
  var _mailSends = true;
  var _mailReceives = true;

  var _hostnameAutofocus = true;
  @override
  void dispose() {
    _hostname.dispose();
    _tlsHostname.dispose();
    _label.dispose();
    _port.dispose();
    _dkimSelectors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final domains = ref.watch(domainControllerProvider);
    late final List<DomainEntry> items;
    if (widget.isEditing) {
      switch (domains) {
        case AsyncData(:final value):
          items = value;
        case AsyncError():
          return _DomainLoadFailure(
            error: 'Akshi could not load saved domains from this device. Please try again.',
            onRetry: () => ref.invalidate(domainControllerProvider),
          );
        case _:
          return const _DomainFormLoading();
      }
    } else {
      items = switch (domains) {
        AsyncData(:final value) => value,
        _ => const <DomainEntry>[],
      };
    }
    final tags = ref.watch(tagControllerProvider).value ?? const <DomainTag>[];
    final refresh = ref.watch(domainRefreshProvider);
    final offline = ref.watch(deviceOfflineProvider).value ?? false;
    final atTagLimit = !TagPolicy.canCreate(tags.length);
    final editing = widget.isEditing;
    final original = editing ? _find(items, widget.domainId) : null;
    if (editing && original == null) {
      return const _DomainNotFound();
    }
    if (!_initialized && (!editing || original != null)) {
      _initialized = true;
      if (original != null) {
        _hostname.text = original.hostname;
        _tlsHostname.text = original.tlsHostname == original.hostname
            ? ''
            : original.tlsHostname;
        _label.text = original.label ?? '';
        _port.text = original.tlsPort.toString();
        _remindersEnabled = original.remindersEnabled;
        _checksCertificate = original.checksCertificate;
        _checksEmail = original.checksEmail;
        _mailSends = original.mailSends;
        _mailReceives = original.mailReceives;
        _dkimSelectors.text = original.dkimSelectors.join(', ');
        _selectedTagIds.addAll(original.tags.map((tag) => tag.id));
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        title: Text(editing ? 'Edit domain' : 'Add domain'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              if (refresh.shouldShowStatus) ...<Widget>[
                const DomainRefreshBanner(),
                const SizedBox(height: 14),
              ],
              if (offline) ...<Widget>[
                const OfflineNotice(
                  message: 'Connect to add or save a domain. Existing saved data is unchanged.',
                ),
                const SizedBox(height: 14),
              ],
              _Intro(editing: editing),
              const SizedBox(height: 22),
              _FormPanel(
                icon: PhosphorIconsDuotone.identificationCard,
                title: 'Domain identity',
                subtitle: 'The domain and the name you will recognize.',
                children: <Widget>[
                  TextFormField(
                    controller: _hostname,
                    autofocus: !editing && _hostnameAutofocus,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Domain',
                      hintText: 'example.com',
                      helperText: 'The registered domain to watch. You can also paste a URL.',
                      helperMaxLines: 2,
                      prefixIcon: PhosphorIcon(
                        PhosphorIconsDuotone.globeHemisphereWest,
                      ),
                    ),
                    validator: (value) => validateHostname(value ?? ''),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _label,
                    textInputAction: TextInputAction.next,
                    maxLength: 48,
                    decoration: const InputDecoration(
                      labelText: 'Name (optional)',
                      hintText: 'Production Website',
                      helperText: 'A friendly name shown prominently; the domain stays visible.',
                      helperMaxLines: 2,
                      prefixIcon: PhosphorIcon(
                        PhosphorIconsDuotone.identificationCard,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _FormPanel(
                icon: PhosphorIconsDuotone.checkCircle,
                title: 'Checks',
                subtitle: 'Registration is always on. Select services this domain uses.',
                children: <Widget>[
                  const _CheckCard(
                    icon: PhosphorIconsDuotone.globeHemisphereWest,
                    title: 'Domain registration',
                    subtitle: 'Registration expiry · always included',
                    selected: true,
                  ),
                  const SizedBox(height: 10),
                  _CheckCard(
                    icon: PhosphorIconsDuotone.certificate,
                    title: 'TLS certificate',
                    subtitle: 'Certificate expiry, trust, and hostname',
                    selected: _checksCertificate,
                    onChanged: (value) =>
                        setState(() => _checksCertificate = value),
                  ),
                  const SizedBox(height: 10),
                  _CheckCard(
                    icon: PhosphorIconsDuotone.envelopeSimple,
                    title: 'Email configuration',
                    subtitle: 'Public sending and receiving DNS records',
                    selected: _checksEmail,
                    onChanged: (value) => setState(() => _checksEmail = value),
                  ),
                ],
              ),
              if (_checksCertificate) ...<Widget>[
                const SizedBox(height: 14),
                _FormPanel(
                  icon: PhosphorIconsDuotone.certificate,
                  title: 'TLS endpoint',
                  subtitle: 'Where Akshi should read the live certificate.',
                  children: <Widget>[
                    TextFormField(
                      controller: _tlsHostname,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'TLS hostname',
                        hintText: 'Same as domain',
                        helperText: 'Leave blank to use the domain above',
                        prefixIcon: PhosphorIcon(
                          PhosphorIconsDuotone.shieldCheck,
                        ),
                      ),
                      validator: (value) {
                        if (!_checksCertificate ||
                            (value ?? '').trim().isEmpty) {
                          return null;
                        }
                        return validateHostname(value!);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'TLS port',
                        helperText: 'Direct TLS · 443 is the HTTPS default',
                        prefixIcon: PhosphorIcon(PhosphorIconsDuotone.network),
                      ),
                      validator: (value) {
                        if (!_checksCertificate) return null;
                        return validateTlsPort(value);
                      },
                      onFieldSubmitted: (_) => _save(original),
                    ),
                  ],
                ),
              ],
              if (_checksEmail) ...<Widget>[
                const SizedBox(height: 14),
                _FormPanel(
                  icon: PhosphorIconsDuotone.envelopeSimple,
                  title: 'Email configuration',
                  subtitle: 'Standard mail records are found automatically.',
                  children: <Widget>[
                    const _EmailCheckNote(),
                    const SizedBox(height: 12),
                    _MailDirectionCard(
                      sends: _mailSends,
                      receives: _mailReceives,
                      onSendsChanged: (value) =>
                          setState(() => _mailSends = value),
                      onReceivesChanged: (value) =>
                          setState(() => _mailReceives = value),
                    ),
                    if (_mailSends) ...<Widget>[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _dkimSelectors,
                        decoration: const InputDecoration(
                          labelText: 'DKIM selector names (optional)',
                          hintText: 'google, selector1, selector2',
                          helperText: 'Leave blank if unsure. For selector1._domainkey.example.com, enter selector1.',
                          helperMaxLines: 3,
                          prefixIcon: PhosphorIcon(PhosphorIconsDuotone.key),
                        ),
                        autocorrect: false,
                        validator: (value) {
                          final selectors = _parseSelectors(value ?? '');
                          return selectors.any(
                                (selector) => !_isValidDkimSelector(selector),
                              )
                              ? 'Use DNS names containing letters, numbers, hyphens, and optional dots'
                              : null;
                        },
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 14),
              _FormPanel(
                icon: PhosphorIconsDuotone.tag,
                title: 'Tags',
                subtitle: atTagLimit
                    ? '${tags.length} of ${TagPolicy.maxCount} used · reuse one or manage tags'
                    : '${tags.length} of ${TagPolicy.maxCount} used · ${TagPolicy.remaining(tags.length)} remaining',
                trailing: TextButton.icon(
                  onPressed: atTagLimit ? _manageTags : () => _createTag(),
                  icon: PhosphorIcon(
                    atTagLimit
                        ? PhosphorIconsDuotone.gear
                        : PhosphorIconsRegular.plus,
                    size: 17,
                  ),
                  label: Text(atTagLimit ? 'Manage' : 'New'),
                ),
                children: <Widget>[
                  if (atTagLimit) ...<Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer
                            .withValues(alpha: .62),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'The 10-tag limit is reached. Select an existing tag below, or manage tags to delete one.',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (tags.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'No tags yet. Create one here whenever you need a group.',
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
                ],
              ),
              if (editing) ...<Widget>[
                const SizedBox(height: 14),
                _FormPanel(
                  icon: PhosphorIconsDuotone.bellRinging,
                  title: 'Reminders',
                  subtitle: 'Control local expiry alerts for this domain.',
                  children: <Widget>[
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      value: _remindersEnabled,
                      onChanged: (value) =>
                          setState(() => _remindersEnabled = value),
                      title: const Text('Expiry reminders'),
                      subtitle: const Text(
                        'Include this domain in consolidated local alerts',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      tileColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLowest,
                    ),
                  ],
                ),
              ],
              if (_saving) ...<Widget>[
                _SaveProgressPanel(progress: _progress),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: _saving || refresh.isRunning || offline
                    ? null
                    : () => _save(original),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PhosphorIcon(
                        editing
                            ? PhosphorIconsDuotone.floppyDisk
                            : PhosphorIconsRegular.plus,
                      ),
                label: Text(
                  _saving
                      ? 'Working…'
                      : editing
                      ? 'Save changes'
                      : 'Add domain',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Akshi checks from this device. No account or Akshi server is used.',
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
      if (!_selectedTagIds.add(id)) {
        _selectedTagIds.remove(id);
      }
    });
  }

  Future<void> _createTag() async {
    setState(() => _hostnameAutofocus = false);
    final tagCount =
        ref.read(tagControllerProvider).value?.length ?? TagPolicy.maxCount;
    if (!TagPolicy.canCreate(tagCount)) {
      await _manageTags();
      return;
    }
    final draft = await showTagEditor(context, currentCount: tagCount);
    if (draft == null || !mounted) {
      return;
    }
    try {
      final tag = await ref
          .read(tagControllerProvider.notifier)
          .create(name: draft.name, colorArgb: draft.colorArgb);
      if (mounted) {
        setState(() => _selectedTagIds.add(tag.id));
      }
    } catch (error, stackTrace) {
      appLogger.error('ui.domain_form.tag_create.failed', error, stackTrace);
      if (!mounted) {
        return;
      }
      final message = switch (error) {
        DomainRefreshInProgressException() =>
          'Wait for the domain refresh to finish.',
        _ when error.toString().contains('UNIQUE constraint failed') =>
          'A tag with that name already exists.',
        _ => userFacingError(error),
      };
      showAkshiNotice(
        context,
        title: 'Could not create tag',
        message: message,
        tone: AkshiNoticeTone.error,
      );
    }
  }

  Future<void> _manageTags() async {
    setState(() => _hostnameAutofocus = false);
    await context.push('/settings/tags');
    if (mounted) {
      ref.invalidate(tagControllerProvider);
    }
  }

  Future<void> _save(DomainEntry? original) async {
    if (!_formKey.currentState!.validate() || _saving) {
      return;
    }
    if (_checksEmail && !_mailSends && !_mailReceives) {
      showAkshiNotice(
        context,
        title: 'Email role required',
        message:
            'Choose whether this domain sends email, receives email, or both.',
        tone: AkshiNoticeTone.warning,
      );
      return;
    }
    setState(() {
      _saving = true;
      _progress = const DomainSaveProgress.initial();
    });
    try {
      final controller = ref.read(domainControllerProvider.notifier);
      final DomainEntry saved;
      final label = _label.text.trim();
      final hostname = normalizeHostname(_hostname.text);
      final enteredTlsHostname = normalizeHostname(_tlsHostname.text);
      final tlsHostname = enteredTlsHostname.isEmpty
          ? hostname
          : enteredTlsHostname;
      final tlsPort = _checksCertificate
          ? requireValidTlsPort(int.parse(_port.text))
          : 443;
      if (!widget.isEditing) {
        saved = await controller.add(
          hostname: hostname,
          tlsHostname: tlsHostname,
          tlsPort: tlsPort,
          checksCertificate: _checksCertificate,
          checksEmail: _checksEmail,
          mailSends: _mailSends,
          mailReceives: _mailReceives,
          dkimSelectors: _parseSelectors(_dkimSelectors.text),
          label: label.isEmpty ? null : label,
          tagIds: _selectedTagIds,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );
      } else {
        if (original == null || original.id != widget.domainId) {
          throw StateError('Domain no longer exists');
        }
        saved = await controller.updateDomain(
          original.copyWith(
            hostname: hostname,
            tlsHostname: tlsHostname,
            tlsPort: tlsPort,
            checksCertificate: _checksCertificate,
            checksEmail: _checksEmail,
            mailSends: _mailSends,
            mailReceives: _mailReceives,
            dkimSelectors: _parseSelectors(_dkimSelectors.text),
            label: label.isEmpty ? null : label,
            remindersEnabled: _remindersEnabled,
          ),
          tagIds: _selectedTagIds,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );
      }
      if (mounted) {
        context.go('/domain/${saved.id}');
      }
    } catch (error, stackTrace) {
      appLogger.error('ui.domain_form.save.failed', error, stackTrace);
      if (!mounted) {
        return;
      }
      showAkshiNotice(
        context,
        title: 'Could not save domain',
        message: _friendlyError(error),
        tone: AkshiNoticeTone.error,
      );
      setState(() => _saving = false);
    }
  }

  DomainEntry? _find(List<DomainEntry> items, String id) {
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  String _friendlyError(Object error) => userFacingError(error);
}

class _DomainFormLoading extends StatelessWidget {
  const _DomainFormLoading();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: _backButton(context),
      title: const Text('Edit domain'),
    ),
    body: SafeArea(
      child: Center(
        child: Semantics(
          label: 'Loading domain',
          child: const CircularProgressIndicator(),
        ),
      ),
    ),
  );
}

class _DomainNotFound extends StatelessWidget {
  const _DomainNotFound();

  @override
  Widget build(BuildContext context) => _DomainRouteMessage(
    icon: PhosphorIconsDuotone.magnifyingGlass,
    title: 'Domain not found',
    message: 'This domain may have been deleted or is no longer available on this device.',
    primaryLabel: 'Back to domains',
    primaryIcon: PhosphorIconsDuotone.caretLeft,
    onPrimary: () => context.go('/'),
  );
}

class _DomainLoadFailure extends StatelessWidget {
  const _DomainLoadFailure({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _DomainRouteMessage(
    icon: PhosphorIconsDuotone.warningCircle,
    title: 'Couldn’t load domain',
    message: error,
    primaryLabel: 'Try again',
    primaryIcon: PhosphorIconsRegular.arrowsClockwise,
    onPrimary: onRetry,
    secondaryLabel: 'Back to domains',
    onSecondary: () => context.go('/'),
  );
}

class _DomainRouteMessage extends StatelessWidget {
  const _DomainRouteMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: _backButton(context),
        title: const Text('Edit domain'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: PhosphorIcon(
                        icon,
                        size: 34,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onPrimary,
                        icon: PhosphorIcon(primaryIcon),
                        label: Text(primaryLabel),
                      ),
                    ),
                    if (secondaryLabel case final label?) ...<Widget>[
                      const SizedBox(height: 8),
                      TextButton(onPressed: onSecondary, child: Text(label)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveProgressPanel extends StatelessWidget {
  const _SaveProgressPanel({required this.progress});

  final DomainSaveProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AkshiTheme.progressSurface(scheme);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  value: progress.fraction >= 1 ? 1 : null,
                  strokeWidth: 2.2,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  progress.message,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(progress.fraction * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.foreground),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.fraction,
            color: colors.accent,
            backgroundColor: colors.foreground.withValues(alpha: .16),
          ),
          const SizedBox(height: 8),
          Text(
            'The domain saves first. Initial checks continue on its summary.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.foreground),
          ),
        ],
      ),
    );
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
  icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
);

class _Intro extends StatelessWidget {
  const _Intro({required this.editing});
  final bool editing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        editing ? 'Update this domain' : 'Watch a new domain',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        'Set the identity first, then choose only the checks this domain uses.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .72)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: PhosphorIcon(icon, size: 21, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing case final action?) ...<Widget>[
                const SizedBox(width: 8),
                action,
              ],
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final interactive = onChanged != null;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedBackground = dark
        ? const Color(0xFF4A2337)
        : const Color(0xFF7B2952);
    final selectedForeground = dark ? const Color(0xFFFFEAF3) : Colors.white;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: selected
            ? selectedForeground.withValues(alpha: .38)
            : scheme.outlineVariant,
      ),
    );
    return Material(
      color: selected ? selectedBackground : scheme.surfaceContainerLowest,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: interactive ? () => onChanged!(!selected) : null,
        customBorder: shape,
        child: Semantics(
          button: interactive,
          checked: selected,
          enabled: interactive,
          label: title,
          value: interactive
              ? selected
                    ? 'Selected'
                    : 'Not selected'
              : 'Always included',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? selectedForeground.withValues(alpha: .14)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: PhosphorIcon(
                    icon,
                    size: 21,
                    color: selected
                        ? selectedForeground
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: selected
                              ? selectedForeground
                              : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: selected
                              ? selectedForeground.withValues(alpha: .82)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 32,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: PhosphorIcon(
                        selected
                            ? PhosphorIconsDuotone.checkCircle
                            : PhosphorIconsRegular.circle,
                        key: ValueKey<bool>(selected),
                        size: 25,
                        color: selected ? selectedForeground : scheme.outline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailCheckNote extends StatelessWidget {
  const _EmailCheckNote();

  @override
  Widget build(BuildContext context) {
    final colors = AkshiTheme.infoSurface(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PhosphorIcon(
            PhosphorIconsDuotone.info,
            size: 21,
            color: colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Akshi finds standard mail records automatically. Leave both roles on for a domain that sends and receives email. Only DKIM needs optional selector names from your mail provider. Akshi does not send messages or test delivery.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.foreground, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _MailDirectionCard extends StatelessWidget {
  const _MailDirectionCard({
    required this.sends,
    required this.receives,
    required this.onSendsChanged,
    required this.onReceivesChanged,
  });

  final bool sends;
  final bool receives;
  final ValueChanged<bool> onSendsChanged;
  final ValueChanged<bool> onReceivesChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: <Widget>[
        SwitchListTile(
          value: sends,
          onChanged: onSendsChanged,
          title: const Text('Sends email from this domain'),
          subtitle: const Text(
            'Automatically checks SPF and DMARC. DKIM is checked only for selector names you add below.',
          ),
          secondary: const PhosphorIcon(PhosphorIconsDuotone.paperPlaneTilt),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: receives,
          onChanged: onReceivesChanged,
          title: const Text('Receives email at this domain'),
          subtitle: const Text(
            'Automatically checks MX, MTA-STS, and TLS reporting records.',
          ),
          secondary: const PhosphorIcon(PhosphorIconsDuotone.trayArrowDown),
        ),
      ],
    ),
  );
}

List<String> _parseSelectors(String value) => value
    .split(',')
    .map((selector) => selector.trim().toLowerCase())
    .where((selector) => selector.isNotEmpty)
    .toSet()
    .toList(growable: false);

bool _isValidDkimSelector(String selector) =>
    selector.length <= 253 &&
    selector
        .split('.')
        .every(
          (label) =>
              RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
                  .hasMatch(label),
        );
