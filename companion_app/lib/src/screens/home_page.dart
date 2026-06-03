import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/host_info.dart';
import '../services/stream_controller_mapping_store.dart';
import '../services/stream_controller_settings.dart';
import '../services/stream_touch_settings.dart';
import '../services/stream_log_share.dart';
import '../services/playnite_stream_foreground.dart' show PlayniteStreamNotification;
import '../services/streaming_bridge.dart';
import '../services/streaming_host_settings.dart';
import '../widgets/companion_insets.dart';
import '../widgets/controller_mapping_section.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final StreamingBridge _bridge = StreamingBridge();
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  List<HostInfo> _hosts = const [];
  String? _selectedHostId;
  String _hostStatus = 'Add your Mac\'s LAN IP with Add IP (from Mac → Streaming).';
  String _pairingStatus = '';
  String _sessionStatus = 'Pair with your Mac first, then start a Desktop stream.';
  bool _pairingInProgress = false;
  bool _streamActive = false;
  bool _streamViewerOpen = false;
  StreamControllerSettings? _controllerSettings;
  StreamTouchSettings? _touchSettings;
  List<StreamControllerElementMapping> _controllerBindings = const [];
  List<ConnectedControllerInfo> _connectedControllers = const [];
  String _controllerStatus = 'Connect a telescopic or Bluetooth gamepad to this phone.';
  bool _controllersRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadSettings());
      unawaited(_loadControllerSettings());
      unawaited(_loadTouchSettings());
      if (Platform.isAndroid) {
        unawaited(PlayniteStreamNotification.ensureNotificationPermission());
      }
      unawaited(_refreshStreamSessionState());
      unawaited(_checkPendingMappingOverlay());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStreamSessionState());
      unawaited(_checkPendingMappingOverlay());
    }
    if (_pairingInProgress &&
        (state == AppLifecycleState.paused || state == AppLifecycleState.inactive)) {
      setState(() {
        _pairingStatus =
            'App left foreground — pairing may stall. Return here and keep this screen visible.';
      });
    }
  }

  Future<void> _loadSettings() async {
    final settings = await StreamingHostSettings.load();
    if (settings.isConfigured) {
      await _refreshHosts();
    }
  }

  Future<void> _loadControllerSettings() async {
    final settings = await StreamControllerSettings.load();
    final mappingStore = await StreamControllerMappingStore.load();
    if (!mounted) return;
    setState(() {
      _controllerSettings = settings;
      _controllerBindings = mappingStore.bindings;
    });
    await _refreshConnectedControllers();
  }

  Future<void> _loadTouchSettings() async {
    final settings = await StreamTouchSettings.load();
    if (!mounted) return;
    setState(() => _touchSettings = settings);
  }

  Future<void> _saveTouchSettings({
    double? cursorSpeed,
    int? tapSlopPercent,
    int? tapTimeoutMs,
    int? tapPressurePercent,
  }) async {
    final current = _touchSettings ?? await StreamTouchSettings.load();
    await current.save(
      cursorSpeed: cursorSpeed,
      tapSlopPercent: tapSlopPercent,
      tapTimeoutMs: tapTimeoutMs,
      tapPressurePercent: tapPressurePercent,
    );
    if (!mounted) return;
    setState(() => _touchSettings = current);
  }

  Future<void> _refreshConnectedControllers() async {
    setState(() {
      _controllersRefreshing = true;
      _controllerStatus = 'Scanning for gamepads…';
    });
    final controllers = await _bridge.listConnectedControllers();
    if (!mounted) return;
    setState(() {
      _controllersRefreshing = false;
      _connectedControllers = controllers;
      _controllerStatus = controllers.isEmpty
          ? 'No gamepad detected. Pair your telescopic controller to this phone, press a button, then tap Refresh.'
          : '${controllers.length} controller(s) ready — start a stream to send input to your Mac.';
    });
  }

  Future<void> _saveControllerSettings({
    bool? multiController,
    bool? swapFaceButtons,
    bool? onScreenControls,
    int? deadZonePercent,
    bool? usbDriver,
    bool? bindAllUsb,
  }) async {
    final current = _controllerSettings ?? await StreamControllerSettings.load();
    await current.save(
      multiController: multiController,
      swapFaceButtons: swapFaceButtons,
      onScreenControls: onScreenControls,
      deadZonePercent: deadZonePercent,
      usbDriver: usbDriver,
      bindAllUsb: bindAllUsb,
    );
    if (!mounted) return;
    setState(() => _controllerSettings = current);
  }

  Future<void> _persistControllerBindings(List<StreamControllerElementMapping> bindings) async {
    final store = await StreamControllerMappingStore.load();
    await store.saveBindings(bindings);
    if (!mounted) return;
    setState(() => _controllerBindings = bindings);
  }

  Future<void> _refreshStreamSessionState() async {
    final session = await _bridge.getStreamSession();
    if (!mounted) return;
    final active = session['hostStreamActive'] == true;
    final viewerOpen = session['viewerOpen'] == true;
    final host = _hosts.where((h) => h.id == _selectedHostId).firstOrNull;
    await PlayniteStreamNotification.syncSession(
      active: active,
      hostLabel: host?.name ?? (session['host'] as String?),
    );
    if (!mounted) return;
    setState(() {
      _streamActive = active;
      _streamViewerOpen = viewerOpen;
      if (active && !viewerOpen) {
        _sessionStatus =
            'Stream running — use Enter current stream, or notification Stop / Controller.';
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabIndex.dispose();
    super.dispose();
  }

  Future<void> _checkPendingMappingOverlay() async {
    if (!Platform.isAndroid || !mounted) return;
    final pending = await PlayniteStreamNotification.consumePendingOpenMapping();
    if (!pending || !mounted) return;
    final shown = await PlayniteStreamNotification.showStreamMappingOverlay();
    if (shown || !mounted) return;
    await _showMappingOverlaySheet();
  }

  Future<void> _showMappingOverlaySheet() async {
    if (!mounted) return;
    _tabIndex.value = 2;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: ControllerMappingSection(
                bridge: _bridge,
                bindings: _controllerBindings,
                connectedControllers: _connectedControllers,
                onBindingsChanged: _persistControllerBindings,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddHostIpDialog() async {
    final settings = await StreamingHostSettings.load();
    if (!mounted) return;

    final normalized = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _AddMacHostIpDialog(initialAddress: settings.hostAddress),
    );

    if (normalized == null || !mounted) return;

    final store = await StreamingHostSettings.load();
    await store.save(hostAddress: normalized);
    setState(() => _hostStatus = 'Saved $normalized — connecting…');
    await _refreshHosts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_hostStatus)),
    );
  }

  Future<void> _refreshHosts() async {
    setState(() => _hostStatus = 'Discovering host…');
    try {
      final settings = await StreamingHostSettings.load();
      final configuredIp = settings.hostAddress;
      final hosts = await _bridge.discoverHosts();
      setState(() {
        _hosts = hosts;
        _selectedHostId = hosts.isNotEmpty ? hosts.first.id : null;
        if (hosts.isEmpty) {
          _hostStatus = configuredIp.isEmpty
              ? 'Tap Add IP and enter your Mac\'s LAN address.'
              : 'Could not reach Mac stream host at $configuredIp — open Mac → Streaming, same Wi‑Fi, port ${StreamingHostSettings.defaultControlPort}.';
        } else {
          _hostStatus = 'Found ${hosts.first.name} at ${hosts.first.address}';
        }
      });
    } catch (e) {
      setState(() => _hostStatus = 'Discovery failed: $e');
    }
  }

  Future<void> _pairHost(HostInfo host) async {
    if (_pairingInProgress) return;

    final settings = await StreamingHostSettings.load();
    if (!settings.isConfigured) {
      setState(() => _pairingStatus = 'Tap Add IP on Hosts and enter your Mac\'s LAN address first.');
      return;
    }

    setState(() {
      _pairingInProgress = true;
      _selectedHostId = host.id;
      _pairingStatus = 'Requesting pairing…';
    });

    try {
      final outcome = await _bridge.pairWithHost(
        hostId: host.id,
        onProgress: (message) {
          if (mounted) setState(() => _pairingStatus = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _pairingInProgress = false;
        _pairingStatus = _shortError(outcome.message ?? (outcome.ok ? 'Paired with ${host.name}' : 'Failed'));
      });
      if (outcome.ok) await _refreshHosts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairingInProgress = false;
        _pairingStatus = _shortError('Pairing error: $e');
      });
    }
  }

  String _shortError(String message) {
    const maxLen = 220;
    if (message.length <= maxLen) return message;
    return '${message.substring(0, maxLen)}…';
  }

  Future<void> _startStream() async {
    final hostId = _selectedHostId;
    if (hostId == null) {
      setState(() => _sessionStatus = 'Select a host on the Hosts tab first.');
      return;
    }
    final host = _hosts.where((h) => h.id == hostId).firstOrNull;
    if (host != null && !host.paired) {
      setState(() => _sessionStatus = 'Host is not paired. Tap Pair on the Hosts tab first.');
      return;
    }

    setState(() => _sessionStatus = 'Starting Desktop stream…');
    if (Platform.isAndroid) {
      await PlayniteStreamNotification.ensureNotificationPermission();
    }
    try {
      final mappingStore = await StreamControllerMappingStore.load();
      final outcome = await _bridge.startStream(
        hostId: hostId,
        width: 1920,
        height: 1080,
        fps: 60,
        controllerBindingsJson: mappingStore.bindingsJson(),
      );
      setState(() {
        _streamActive = outcome.ok;
        _streamViewerOpen = outcome.ok;
        _sessionStatus = outcome.message ?? (outcome.ok ? 'Streaming' : 'Failed');
      });
      if (outcome.ok) {
        await _refreshStreamSessionState();
      } else {
        await PlayniteStreamNotification.syncSession(active: false);
      }
    } catch (e) {
      setState(() {
        _streamActive = false;
        _sessionStatus = 'Start stream error: $e';
      });
      await PlayniteStreamNotification.syncSession(active: false);
    }
  }

  Future<void> _reenterStream() async {
    setState(() => _sessionStatus = 'Opening stream view…');
    final ok = await _bridge.resumeStream();
    if (!mounted) return;
    setState(() {
      _streamViewerOpen = ok;
      _sessionStatus = ok
          ? 'Stream running — video view open.'
          : 'Could not reopen stream. Tap Stop and start again.';
    });
    await _refreshStreamSessionState();
  }

  Future<void> _stopStream() async {
    setState(() => _sessionStatus = 'Stopping stream…');
    try {
      final logPath = await _bridge.stopStream();
      if (!mounted) return;
      setState(() {
        _streamActive = false;
        _streamViewerOpen = false;
        _sessionStatus = 'Stream stopped';
      });
      if (logPath != null) {
        await offerStreamLogShare(context, logPath);
      }
      await PlayniteStreamNotification.syncSession(active: false);
    } catch (e) {
      setState(() => _sessionStatus = 'Stop stream error: $e');
      await PlayniteStreamNotification.syncSession(active: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playnite Companion')),
      body: ValueListenableBuilder<int>(
        valueListenable: _tabIndex,
        builder: (context, index, _) {
          switch (index) {
            case 0:
              return _buildHostsTab();
            case 1:
              return _buildSessionTab();
            case 2:
              return _buildControllersTab();
            default:
              return const SizedBox.shrink();
          }
        },
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _tabIndex,
        builder: (context, index, _) {
          return CompanionInsets.wrapNavigationBar(
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => _tabIndex.value = i,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.dns), label: 'Hosts'),
                NavigationDestination(icon: Icon(Icons.videogame_asset), label: 'Session'),
                NavigationDestination(icon: Icon(Icons.sports_esports), label: 'Controller'),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHostsTab() {
    return Padding(
      padding: CompanionInsets.listPadding(context),
      child: Column(
      children: [
        ListTile(
          title: Text(_hostStatus),
          trailing: FilledButton.icon(
            onPressed: _showAddHostIpDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add IP'),
          ),
        ),
        if (_pairingStatus.isNotEmpty) ...[
          if (_pairingInProgress) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _pairingStatus,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        const Divider(height: 1),
        Expanded(
          child: _hosts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No host found. Tap Add IP, enter the LAN address from Mac → Streaming, then confirm the Mac host is running.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _hosts.length,
                  itemBuilder: (context, i) {
                    final host = _hosts[i];
                    final selected = _selectedHostId == host.id;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        selected: selected,
                        onTap: () => setState(() => _selectedHostId = host.id),
                        title: Text(host.name),
                        subtitle: Text('${host.address} • ${host.paired ? "Paired" : "Not paired"}'),
                        trailing: host.paired
                            ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                            : FilledButton(
                                onPressed: _pairingInProgress ? null : () => _pairHost(host),
                                child: const Text('Pair'),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
      ),
    );
  }

  Widget _buildSessionTab() {
    final selected = _hosts.where((h) => h.id == _selectedHostId).firstOrNull;
    final canStart = selected?.paired == true && !_streamActive;
    final canReenter = _streamActive && !_streamViewerOpen;

    return Padding(
      padding: CompanionInsets.listPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Streaming session',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Streams your Mac desktop via Playnite H.264 (port ${StreamingHostSettings.defaultVideoPort}). '
            'Connect a gamepad first (Controller tab), then start Desktop stream. '
            'While streaming, use the notification Stop or Controller buttons.',
          ),
          if (_sessionStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _sessionStatus,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 8),
            Text(
              '${selected.name} (${selected.address}) • ${selected.paired ? "Paired" : "Not paired"}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (canReenter)
                FilledButton.icon(
                  onPressed: _reenterStream,
                  icon: const Icon(Icons.fullscreen),
                  label: const Text('Enter current stream'),
                )
              else
                FilledButton.icon(
                  onPressed: canStart ? _startStream : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Desktop 1080p60'),
                ),
              OutlinedButton.icon(
                onPressed: _streamActive ? _stopStream : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControllersTab() {
    final settings = _controllerSettings;
    final isAndroid = Platform.isAndroid;

    return ListView(
      padding: CompanionInsets.listPadding(context),
      children: [
        const Text(
          'Game controller',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pair a telescopic or Bluetooth gamepad to this phone (not the Mac). '
          'During a stream, Moonlight forwards pad input to your Mac as an Xbox-style controller.',
        ),
        const SizedBox(height: 12),
        Text(
          _controllerStatus,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _controllersRefreshing ? null : _refreshConnectedControllers,
          icon: _controllersRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: const Text('Refresh gamepads'),
        ),
        if (_connectedControllers.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._connectedControllers.map(
            (controller) => Card(
              child: ListTile(
                leading: const Icon(Icons.gamepad),
                title: Text(controller.name),
                subtitle: Text(
                  controller.vendor != null ? 'Vendor ${controller.vendor}' : 'Ready for streaming',
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Button → keyboard mapping',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (isAndroid)
          ControllerMappingSection(
            bridge: _bridge,
            bindings: _controllerBindings,
            connectedControllers: _connectedControllers,
            onBindingsChanged: _persistControllerBindings,
          )
        else
          Text(
            'Button→keyboard mapping during streams is available on Android.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        if (isAndroid) ...[
          const SizedBox(height: 24),
          const Text(
            'Touchpad (stream view)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'While streaming your Mac desktop, finger touches on the video surface move the Mac cursor. '
            'Adjust speed and how taps are detected.',
          ),
          const SizedBox(height: 8),
          if (_touchSettings == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            ListTile(
              title: const Text('Cursor speed'),
              subtitle: Slider(
                value: _touchSettings!.cursorSpeed,
                min: 0.25,
                max: 3.0,
                divisions: 11,
                label: _touchSettings!.cursorSpeed.toStringAsFixed(2),
                onChanged: (value) => _saveTouchSettings(cursorSpeed: value),
              ),
            ),
            ListTile(
              title: const Text('Tap movement allowance'),
              subtitle: Slider(
                value: _touchSettings!.tapSlopPercent.toDouble(),
                min: 50,
                max: 200,
                divisions: 15,
                label: '${_touchSettings!.tapSlopPercent}%',
                onChanged: (value) =>
                    _saveTouchSettings(tapSlopPercent: value.round()),
              ),
            ),
            ListTile(
              title: const Text('Tap time limit'),
              subtitle: Slider(
                value: _touchSettings!.tapTimeoutMs.toDouble(),
                min: 150,
                max: 800,
                divisions: 13,
                label: '${_touchSettings!.tapTimeoutMs} ms',
                onChanged: (value) =>
                    _saveTouchSettings(tapTimeoutMs: value.round()),
              ),
            ),
            ListTile(
              title: const Text('Tap pressure'),
              subtitle: Slider(
                value: _touchSettings!.tapPressurePercent.toDouble(),
                min: 10,
                max: 90,
                divisions: 16,
                label: '${_touchSettings!.tapPressurePercent}%',
                onChanged: (value) =>
                    _saveTouchSettings(tapPressurePercent: value.round()),
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        const Text(
          'Stream input options',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (settings == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          SwitchListTile(
            title: const Text('Multi-controller'),
            subtitle: const Text('Keep slots open when a pad disconnects mid-game.'),
            value: settings.multiController,
            onChanged: (value) => _saveControllerSettings(multiController: value),
          ),
          SwitchListTile(
            title: const Text('Swap A/B and X/Y'),
            subtitle: const Text('Nintendo-style face buttons → Xbox layout on the Mac.'),
            value: settings.swapFaceButtons,
            onChanged: (value) => _saveControllerSettings(swapFaceButtons: value),
          ),
          SwitchListTile(
            title: const Text('On-screen controls'),
            subtitle: const Text('Touch overlay gamepad when no physical controller is connected.'),
            value: settings.onScreenControls,
            onChanged: (value) => _saveControllerSettings(onScreenControls: value),
          ),
          ListTile(
            title: const Text('Stick dead zone'),
            subtitle: Slider(
              value: settings.deadZonePercent.toDouble(),
              min: 0,
              max: 20,
              divisions: 20,
              label: '${settings.deadZonePercent}%',
              onChanged: (value) =>
                  _saveControllerSettings(deadZonePercent: value.round()),
            ),
          ),
          if (isAndroid) ...[
            SwitchListTile(
              title: const Text('USB driver'),
              subtitle: const Text('Support USB-C telescopic controllers via Moonlight USB driver.'),
              value: settings.usbDriver,
              onChanged: (value) => _saveControllerSettings(usbDriver: value),
            ),
            SwitchListTile(
              title: const Text('Bind all USB devices'),
              subtitle: const Text('Claim unrecognized USB gamepads (use if yours is not detected).'),
              value: settings.bindAllUsb,
              onChanged: (value) => _saveControllerSettings(bindAllUsb: value),
            ),
          ],
        ],
      ],
    );
  }

}

/// Dialog for entering the Mac streaming host LAN IP (owns its [TextEditingController]).
class _AddMacHostIpDialog extends StatefulWidget {
  const _AddMacHostIpDialog({required this.initialAddress});

  final String initialAddress;

  @override
  State<_AddMacHostIpDialog> createState() => _AddMacHostIpDialogState();
}

class _AddMacHostIpDialogState extends State<_AddMacHostIpDialog> {
  late final TextEditingController _ipController;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = _normalizeHostAddress(_ipController.text);
    if (normalized.isEmpty) {
      setState(() => _inlineError = 'Enter a LAN IP address.');
      return;
    }
    if (normalized == '127.0.0.1' || normalized == 'localhost' || normalized == '::1') {
      setState(() => _inlineError = '127.0.0.1 is this phone, not your Mac.');
      return;
    }
    Navigator.pop(context, normalized);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Mac host IP'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'LAN IPv4 from Mac → Streaming. IP only — not 127.0.0.1. '
              'Port 28765 is automatic.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Mac host IP',
                hintText: 'e.g. 192.168.1.42',
                errorText: _inlineError,
              ),
              onChanged: (_) {
                if (_inlineError != null) {
                  setState(() => _inlineError = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

String _normalizeHostAddress(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return '';

  if (value.contains('://')) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }
  }

  // Allow pasting "192.168.1.42:47989" — strip port; ports are configured separately.
  final colon = value.indexOf(':');
  if (colon > 0 && !value.contains(']')) {
    value = value.substring(0, colon);
  }

  return value.trim();
}
