import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/state/app_controller.dart';
import '../../../core/utilities/persistence_errors.dart';

/// Device-local opt-in. Saving the preference never opens another activity.
class FocusDesktopSettingsTile extends StatefulWidget {
  const FocusDesktopSettingsTile({required this.controller, super.key});

  final AppController controller;

  @override
  State<FocusDesktopSettingsTile> createState() =>
      _FocusDesktopSettingsTileState();
}

class _FocusDesktopSettingsTileState extends State<FocusDesktopSettingsTile> {
  bool _saving = false;
  bool? _retryValue;
  String? _error;

  Future<void> _save(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _retryValue = value;
    });
    try {
      await widget.controller.setFocusDesktopEnabled(value);
      if (mounted) setState(() => _retryValue = null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = persistenceErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    if (!widget.controller.focusDesktopSupported) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('focus-desktop-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.apps_outlined),
          title: Text(context.tr('专注桌面')),
          value: widget.controller.focusDesktopEnabled,
          onChanged: _saving ? null : _save,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            context.tr('默认关闭；开启后，开始或继续专注时自动打开，只显示系统应用、当前白名单应用和 Pactick。'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            context.tr('仅保存在本机。专注桌面不会替换系统默认桌面；主屏幕、最近任务和其他系统入口仍可使用。'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_saving)
          LinearProgressIndicator(semanticsLabel: context.tr('正在保存专注桌面设置')),
        if (_error case final message?) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _saving || _retryValue == null
                  ? null
                  : () => _save(_retryValue!),
              child: Text(context.tr('重试保存专注桌面设置')),
            ),
          ),
        ],
        if (_error == null &&
            widget.controller.focusDesktopErrorMessage != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              widget.controller.focusDesktopErrorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _saving
                  ? null
                  : () => _save(widget.controller.focusDesktopEnabled),
              child: Text(context.tr('重试应用专注桌面设置')),
            ),
          ),
        ],
        const Divider(),
      ],
    );
  }
}

/// Used only beside an active local session, including the private vault.
class OpenFocusDesktopButton extends StatefulWidget {
  const OpenFocusDesktopButton({required this.controller, super.key});

  final AppController controller;

  @override
  State<OpenFocusDesktopButton> createState() => _OpenFocusDesktopButtonState();
}

class _OpenFocusDesktopButtonState extends State<OpenFocusDesktopButton> {
  bool _opening = false;
  String? _error;

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.controller.openFocusDesktop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('无法打开专注桌面，专注仍在继续。请重试。'));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.focusDesktopSupported || !controller.focusDesktopEnabled) {
      return const SizedBox.shrink();
    }
    final message = _error ?? controller.focusDesktopErrorMessage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          child: OutlinedButton.icon(
            onPressed: _opening ? null : _open,
            icon: const Icon(Icons.apps_outlined),
            label: Text(
              _opening
                  ? context.tr('正在打开专注桌面…')
                  : message != null
                  ? context.tr('重试打开专注桌面')
                  : context.tr('打开专注桌面'),
            ),
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    );
  }
}
