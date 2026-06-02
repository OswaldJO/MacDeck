import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/host_info.dart';
import '../services/streaming_bridge.dart';
import '../services/streaming_host_settings.dart';
import '../services/sunshine_pairing_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final StreamingBridge _bridge = StreamingBridge();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  List<HostInfo> _hosts = const [];
  String? _selectedHostId;
  String _hostStatus = 'Configure your Mac host IP in Settings.';
  String _pairingStatus = 'Tap Start pairing below, then submit the PIN on the Mac.';
  bool _pairingInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
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
    _hostController.text = settings.hostAddress;
    await _refreshHosts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    _hostController.dispose();
    _tabIndex.dispose();
    super.dispose();
  }

  Future<void> _saveHostSettings() async {
    final normalized = _normalizeHostAddress(_hostController.text);
    if (normalized.isEmpty) {
      _showSettingsMessage('Enter your Mac’s LAN IP (e.g. 192.168.1.42).');
      return;
    }
    if (normalized == '127.0.0.1' || normalized == 'localhost' || normalized == '::1') {
      _showSettingsMessage(
        '127.0.0.1 is this phone, not your Mac. Use the LAN IP from Mac → Streaming.',
      );
      return;
    }

    _hostController.text = normalized;
    final settings = await StreamingHostSettings.load();
    await settings.save(hostAddress: normalized);
    setState(() => _hostStatus = 'Saved host $normalized — discovering…');
    await _refreshHosts();
    if (!mounted) return;
    _tabIndex.value = 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_hostStatus)),
    );
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

  void _showSettingsMessage(String message) {
    setState(() => _hostStatus = message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
              ? 'Set your Mac’s LAN IP in Settings first.'
              : 'Could not reach Sunshine at $configuredIp — check Mac Streaming tab is running, same Wi‑Fi, and firewall.';
        } else {
          _hostStatus = 'Found ${hosts.first.name} at ${hosts.first.address}';
        }
      });
    } catch (e) {
      setState(() => _hostStatus = 'Discovery failed: $e');
    }
  }

  Future<void> _pair() async {
    if (_pairingInProgress) return;

    final settings = await StreamingHostSettings.load();
    if (!settings.isConfigured) {
      setState(() => _pairingStatus = 'Save your Mac’s LAN IP in Settings first.');
      return;
    }

    var pin = _pinController.text.trim();
    if (pin.length != 4) {
      pin = SunshinePairingService.generatePin();
      _pinController.text = pin;
    }

    setState(() {
      _pairingInProgress = true;
      _pairingStatus = 'Starting pairing…';
    });

    try {
      final hostId = _selectedHostId ?? settings.hostAddress;
      final outcome = await _bridge.pairWithPin(
        hostId: hostId,
        pin: pin,
        onProgress: (message) {
          if (mounted) {
            setState(() {
              _pairingStatus = message;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _pairingInProgress = false;
        _pairingStatus = _shortError(outcome.message ?? (outcome.ok ? 'Paired' : 'Failed'));
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
      setState(() => _hostStatus = 'Select a host first');
      return;
    }
    setState(() => _hostStatus = 'Starting stream…');
    try {
      final ok = await _bridge.startStream(
        hostId: hostId,
        width: 1920,
        height: 1080,
        fps: 60,
      );
      setState(() => _hostStatus = ok ? 'Stream started (stub)' : 'Failed to start stream');
    } catch (e) {
      setState(() => _hostStatus = 'Start stream error: $e');
    }
  }

  Future<void> _stopStream() async {
    setState(() => _hostStatus = 'Stopping stream…');
    try {
      await _bridge.stopStream();
      setState(() => _hostStatus = 'Stream stopped');
    } catch (e) {
      setState(() => _hostStatus = 'Stop stream error: $e');
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
              return _buildPairingTab();
            case 2:
              return _buildSessionTab();
            case 3:
              return _buildSettingsTab();
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
              NavigationDestination(icon: Icon(Icons.password), label: 'Pairing'),
              NavigationDestination(icon: Icon(Icons.videogame_asset), label: 'Session'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
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
            onPressed: _refreshHosts,
            icon: const Icon(Icons.refresh),
            label: const Text('Discover'),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _hosts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No host found. Save your Mac’s LAN IP in Settings, confirm Mac → Streaming shows Running, then tap Discover.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _hosts.length,
                  itemBuilder: (context, i) {
                    final host = _hosts[i];
                    return RadioListTile<String>(
                      value: host.id,
                      groupValue: _selectedHostId,
                      onChanged: (v) => setState(() => _selectedHostId = v),
                      title: Text(host.name),
                      subtitle: Text('${host.address} • ${host.paired ? "Paired" : "Not paired"}'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPairingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sunshine pairing',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '1. Tap Start pairing below FIRST (keep this screen open).\n'
            '2. On the Mac → Streaming → Start pairing → enter the same PIN → Submit PIN to Sunshine.\n'
            '3. Do not submit the PIN on the Mac until this screen says “Waiting for Mac…”.',
          ),
          if (_pairingStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_pairingInProgress) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            Text(
              _pairingStatus,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'PIN (4 digits)',
              hintText: 'Auto-generated if empty',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pairingInProgress
                ? null
                : () {
                    final pin = SunshinePairingService.generatePin();
                    _pinController.text = pin;
                    setState(() {
                      _pairingStatus =
                          'PIN $pin — tap Start pairing, wait for “Waiting for Mac…”, then enter it on the Mac.';
                    });
                  },
            icon: const Icon(Icons.casino),
            label: const Text('Generate PIN'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _pairingInProgress ? null : _pair,
            icon: _pairingInProgress
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.link),
            label: Text(_pairingInProgress ? 'Pairing…' : 'Start pairing'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTab() {
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
          const Text('Video decode is still a stub; pairing is wired to Sunshine.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _startStream,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start 1080p60'),
              ),
              OutlinedButton.icon(
                onPressed: _stopStream,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mac host',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'LAN IPv4 of the Mac running Sunshine (shown on Mac → Streaming tab). '
            'IP only — do not use 127.0.0.1 or add :47989 here.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hostController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Mac host IP',
              hintText: 'e.g. 192.168.1.42',
            ),
          ),
          if (_hostStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _hostStatus,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saveHostSettings,
            icon: const Icon(Icons.save),
            label: const Text('Save & discover'),
          ),
        ],
      ),
    );
  }
}
