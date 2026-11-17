import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        kBackMouseButton,
        kForwardMouseButton,
        kMiddleMouseButton,
        kPrimaryButton,
        kSecondaryButton,
        PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets.dart';

/// What each labelled focus node is, in the interface's own words.
///
/// A node's [FocusNode.debugLabel] is set where the node is made; this registry
/// turns that label into a role ("file list", "filter field"). A label nobody
/// registered still gets a readable form of itself, so a new node shows up
/// without first being spelled out here.
class FocusRoles {
  FocusRoles([Map<String, String> roles = const {}]) : _roles = {...roles};

  final Map<String, String> _roles;

  /// Name the node labelled [nodeLabel] as [role] from now on. The same label
  /// may be used by several nodes (every pane is one stop in the Tab order).
  void register(String nodeLabel, String role) => _roles[nodeLabel] = role;

  /// The role of [nodeLabel], or null when there is no label to go on.
  String? roleForLabel(String? nodeLabel) {
    if (nodeLabel == null || nodeLabel.trim().isEmpty) return null;
    return _roles[nodeLabel] ?? _prettify(nodeLabel);
  }

  /// The role of [node] or its nearest labelled ancestor, as the user sees it.
  String? roleFor(FocusNode node) {
    for (final n in [node, ...node.ancestors]) {
      final role = roleForLabel(n.debugLabel);
      if (role != null) return role;
    }
    // A text field made without a labelled node around it is still a text field.
    final context = node.context;
    if (context != null &&
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return 'text field';
    }
    return null;
  }

  /// "commit_message" and "file-list" read as "commit message" and "file list".
  static String _prettify(String label) =>
      label.replaceAll(RegExp(r'[_-]+'), ' ').trim().toLowerCase();
}

/// The labels the app's own focus nodes use.
///
/// `shell.dart` names its nodes with these debug labels ("shell", "filter",
/// "commit message"), so the bar names them by role without the strings living
/// in two places.
final FocusRoles appFocusRoles = FocusRoles(const {
  'shell': 'app',
  'rail': 'mode rail',
  'file list': 'file list',
  'filter': 'filter field',
  'commit message': 'commit message',
  'ignore dialog': 'ignore dialog',
  'ignore rail': 'ignore file rail',
  'ignore lines': 'ignore file lines',
  'browse list': 'browse list',
  'browse filter': 'browse filter field',
  'console list': 'console list',
  'editor list': 'editor list',
  'help': 'help',
});

/// The debug bar: a bug button in the corner that opens a panel naming the
/// focused element by its role, the last key pressed and the last mouse event.
///
/// Give it the body as [child] and it wraps that body in a [Listener] and a
/// [Stack] with the bar at the bottom right, so it sees every pointer event in
/// the window:
///
/// ```dart
/// body: DebugBar(roles: appFocusRoles, child: Row(children: [...])),
/// ```
///
/// With no [child] it can sit in a `Positioned` of a `Stack` of your own; the
/// pointer events then come from [GestureBinding]'s global route, which sees
/// the whole window without needing a hit test.
///
/// Both forms are driven the same way in a widget test: pump it, tap
/// [buttonKey], send keys and pointer events, and read the panel at [panelKey].
/// It starts no timers and waits on no future, so the fake clock stays in charge.
class DebugBar extends StatefulWidget {
  const DebugBar({super.key, this.roles, this.child});

  /// The role registry; [appFocusRoles] when omitted.
  final FocusRoles? roles;

  /// The body to watch for pointer events. Omit when the bar is placed by hand.
  final Widget? child;

  /// Keys of the two parts a test drives.
  static const buttonKey = ValueKey<String>('debug button');
  static const panelKey = ValueKey<String>('debug panel');
  static const releasesKey = ValueKey<String>('debug key releases');

  @override
  State<DebugBar> createState() => _DebugBarState();
}

class _DebugBarState extends State<DebugBar> {
  FocusRoles get _roles => widget.roles ?? appFocusRoles;

  bool _open = false;
  bool _showReleases = false;
  String _lastKey = '-';
  String _lastRelease = '-';
  String _lastMouse = '-';

  /// The buttons that went down, so the release can name the same one.
  int _downButtons = 0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_refresh);
    HardwareKeyboard.instance.addHandler(_onKey);
    if (widget.child == null) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_refresh);
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (widget.child == null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _togglePanel() => setState(() => _open = !_open);

  void _toggleReleases() => setState(() => _showReleases = !_showReleases);

  /// Every key the app sees; a release only lands in the release line, never in
  /// the last-key line, and only while the toggle is on.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      setState(() => _lastKey = _keyName(event));
    } else if (event is KeyUpEvent && _showReleases) {
      setState(() => _lastRelease = _keyName(event));
    }
    return false;
  }

  /// The one route both pointer sources use: a [Listener] around the body, or
  /// the global route when the bar stands alone.
  void _onPointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        _downButtons = event.buttons;
        _recordMouse(_buttonName(event.buttons), 'down', event.position);
      case PointerUpEvent():
        _recordMouse(_buttonName(_downButtons), 'up', event.position);
      case PointerScrollEvent():
        _recordWheel(event);
      default:
        return;
    }
  }

  void _recordWheel(PointerScrollEvent event) {
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    _recordMouse('wheel', delta > 0 ? 'down' : 'up', event.position);
  }

  void _recordMouse(String what, String direction, Offset position) {
    final modifiers = _modifiers();
    final at = '${position.dx.round()},${position.dy.round()}';
    final line = '${[...modifiers, what].join('+')} $direction at $at';
    setState(() => _lastMouse = line);
  }

  @override
  Widget build(BuildContext context) {
    final bar = ExcludeFocus(child: _bar(context));
    final body = widget.child;
    if (body == null) return bar;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerUp: _onPointer,
      onPointerSignal: _onPointer,
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(right: 12, bottom: 12, child: bar),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (_open) ...[_panel(context), const SizedBox(height: 8)],
      _BugButton(onPressed: _togglePanel),
    ],
  );

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final role = _focusedRole();
    return Container(
      key: DebugBar.panelKey,
      width: 340,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line(context, 'Focus', role ?? 'nothing'),
          _line(context, 'Key', _lastKey),
          _line(context, 'Mouse', _lastMouse),
          if (_showReleases) _line(context, 'Released', _lastRelease),
          _ReleasesToggle(onPressed: _toggleReleases),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// The focused element by its role, never by its class.
  String? _focusedRole() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return null;
    return _roles.roleFor(node);
  }

  /// "Ctrl+Shift+K" for a chord, "k" for a plain key; a character key with Ctrl
  /// or Alt is shown upper case, as it would be typed.
  String _keyName(KeyEvent event) {
    final character = event.character;
    final hasCharacter = character != null && character.trim().isNotEmpty;
    final modified =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed;
    var name = hasCharacter
        ? character
        : event.logicalKey.keyLabel.isNotEmpty
        ? event.logicalKey.keyLabel
        : event.logicalKey.debugName ?? '?';
    if (hasCharacter && modified && name.length == 1) name = name.toUpperCase();
    if (!hasCharacter &&
        name.length == 1 &&
        !modified &&
        !HardwareKeyboard.instance.isShiftPressed &&
        name.toLowerCase() != name) {
      name = name.toLowerCase();
    }
    final modifiers = _modifiers(shift: !hasCharacter);
    return [...modifiers, name].join('+');
  }

  List<String> _modifiers({bool shift = true}) {
    final keyboard = HardwareKeyboard.instance;
    return [
      if (keyboard.isControlPressed) 'Ctrl',
      if (keyboard.isAltPressed) 'Alt',
      if (keyboard.isShiftPressed && shift) 'Shift',
    ];
  }
}

/// The mouse button in a pointer event's `buttons` bit field, in the order
/// they are named in the panel.
String _buttonName(int buttons) {
  final names = [
    if (buttons & kPrimaryButton != 0) 'Left',
    if (buttons & kSecondaryButton != 0) 'Right',
    if (buttons & kMiddleMouseButton != 0) 'Middle',
    if (buttons & kBackMouseButton != 0) 'Back',
    if (buttons & kForwardMouseButton != 0) 'Forward',
  ];
  return names.isEmpty ? 'Button' : names.join('+');
}

/// The bug button: the bar's only always-visible control.
class _BugButton extends StatelessWidget {
  const _BugButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Clickable(
      tooltip: 'Debug: focus, last key and mouse event',
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 6,
        shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
        child: IconButton(
          key: DebugBar.buttonKey,
          onPressed: onPressed,
          icon: Icon(Icons.bug_report_outlined, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The switch that also records key releases.
class _ReleasesToggle extends StatelessWidget {
  const _ReleasesToggle({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SmallButton(
        key: DebugBar.releasesKey,
        label: 'show key releases',
        tooltip: 'Also show the last key that was released',
        onPressed: onPressed,
      );
}
