import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/gamepad_elements.dart';
import '../data/moonlight_key_codes.dart';
import '../models/host_info.dart';
import '../services/stream_controller_mapping_store.dart';
import '../services/stream_controller_settings.dart';
import '../services/stream_log_share.dart';
import '../services/streaming_bridge.dart';
import '../services/streaming_host_settings.dart';

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
  StreamControllerSettings? _controllerSettings;
  List<StreamControllerBinding> _controllerBindings = const [];
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
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    bool? mouseEmulation,
  }) async {
    final current = _controllerSettings ?? await StreamControllerSettings.load();
    await current.save(
      multiController: multiController,
      swapFaceButtons: swapFaceButtons,
      onScreenControls: onScreenControls,
      deadZonePercent: deadZonePercent,
      usbDriver: usbDriver,
      bindAllUsb: bindAllUsb,
      mouseEmulation: mouseEmulation,
    );
    if (!mounted) return;
    setState(() => _controllerSettings = current);
  }

  Future<void> _persistControllerBindings(List<StreamControllerBinding> bindings) async {
    final store = await StreamControllerMappingStore.load();
    await store.saveBindings(bindings);
    if (!mounted) return;
    setState(() => _controllerBindings = bindings);
  }

  Future<void> _removeControllerBinding(StreamControllerBinding binding) async {
    final updated = _controllerBindings
        .where((entry) => entry.sourceElementId != binding.sourceElementId)
        .toList();
    await _persistControllerBindings(updated);
  }

  Future<void> _showAddControllerBindingDialog() async {
    var selectedElement = kMappableGamepadElements.first;
    var selectedKey = kMoonlightKeyboardKeys.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Map button to key'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<GamepadElement>(
                      value: selectedElement,
                      decoration: const InputDecoration(labelText: 'Controller button'),
                      items: kMappableGamepadElements
                          .map(
                            (element) => DropdownMenuItem(
                              value: element,
                              child: Text(element.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedElement = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<MoonlightKeyOption>(
                      value: selectedKey,
                      decoration: const InputDecoration(labelText: 'Keyboard key on Mac'),
                      items: kMoonlightKeyboardKeys
                          .map(
                            (key) => DropdownMenuItem(
                              value: key,
                              child: Text(key.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedKey = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;

    final binding = StreamControllerBinding(
      sourceElementId: selectedElement.id,
      sourceLabel: selectedElement.label,
      moonlightKeyCode: selectedKey.moonlightKeyCode,
      targetLabel: selectedKey.label,
    );
    final updated = [
      ..._controllerBindings.where((entry) => entry.sourceElementId != binding.sourceElementId),
      binding,
    ];
    await _persistControllerBindings(updated);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabIndex.dispose();
    super.dispose();
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
    try {
      final outcome = await _bridge.startStream(
        hostId: hostId,
        width: 1920,
        height: 1080,
        fps: 60,
      );
      setState(() {
        _streamActive = outcome.ok;
        _sessionStatus = outcome.message ?? (outcome.ok ? 'Streaming' : 'Failed');
      });
    } catch (e) {
      setState(() {
        _streamActive = false;
        _sessionStatus = 'Start stream error: $e';
      });
    }
  }

  Future<void> _stopStream() async {
    setState(() => _sessionStatus = 'Stopping stream…');
    try {
      final logPath = await _bridge.stopStream();
      if (!mounted) return;
      setState(() {
        _streamActive = false;
        _sessionStatus = 'Stream stopped';
      });
      if (logPath != null) {
        await offerStreamLogShare(context, logPath);
      }
    } catch (e) {
      setState(() => _sessionStatus = 'Stop stream error: $e');
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
          return NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _tabIndex.value = i,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dns), label: 'Hosts'),
              NavigationDestination(icon: Icon(Icons.videogame_asset), label: 'Session'),
              NavigationDestination(icon: Icon(Icons.sports_esports), label: 'Controller'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHostsTab() {
    return Column(
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
                            ? const Icon(Icons.check_circle, color: Colors.green)
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
    );
  }

  Widget _buildSessionTab() {
    final selected = _hosts.where((h) => h.id == _selectedHostId).firstOrNull;
    final canStream = selected?.paired == true && !_streamActive;

    return Padding(
      padding: const EdgeInsets.all(16),
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
            'Connect a gamepad to this phone first (Controller tab), then start Desktop stream.',
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
            children: [
              FilledButton.icon(
                onPressed: canStream ? _startStream : null,
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
      padding: const EdgeInsets.all(16),
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
        Text(
          isAndroid
              ? 'Mapped buttons send keyboard keys to your Mac during a stream. '
                  'Unmapped buttons still work as a gamepad.'
              : 'Button→keyboard mapping during streams is available on Android. '
                  'iOS sends unmapped input as a gamepad.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (isAndroid)
          FilledButton.icon(
            onPressed: _showAddControllerBindingDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add mapping'),
          ),
        if (_controllerBindings.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No custom mappings yet.'),
          )
        else ...[
          const SizedBox(height: 12),
          ..._controllerBindings.map(
            (binding) => Card(
              child: ListTile(
                leading: const Icon(Icons.keyboard),
                title: Text('${binding.sourceLabel} → ${binding.targetLabel}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: isAndroid ? () => _removeControllerBinding(binding) : null,
                ),
              ),
            ),
          ),
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
            SwitchListTile(
              title: const Text('Mouse emulation'),
              subtitle: const Text(
                'Left stick moves the Mac mouse during a stream. '
                'Right stick and unmapped buttons still control the gamepad.',
              ),
              value: settings.mouseEmulation,
              onChanged: (value) => _saveControllerSettings(mouseEmulation: value),
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
