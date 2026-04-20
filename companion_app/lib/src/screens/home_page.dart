import 'package:flutter/material.dart';

import '../models/host_info.dart';
import '../services/streaming_bridge.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final StreamingBridge _bridge = StreamingBridge();
  final TextEditingController _pinController = TextEditingController();
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);
  List<HostInfo> _hosts = const [];
  String? _selectedHostId;
  String _status = 'Idle';

  @override
  void initState() {
    super.initState();
    _refreshHosts();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _tabIndex.dispose();
    super.dispose();
  }

  Future<void> _refreshHosts() async {
    setState(() => _status = 'Discovering hosts...');
    try {
      final hosts = await _bridge.discoverHosts();
      setState(() {
        _hosts = hosts;
        _selectedHostId = hosts.isNotEmpty ? hosts.first.id : null;
        _status = hosts.isEmpty ? 'No hosts found' : 'Found ${hosts.length} host(s)';
      });
    } catch (e) {
      setState(() => _status = 'Discovery failed: $e');
    }
  }

  Future<void> _pair() async {
    final hostId = _selectedHostId;
    final pin = _pinController.text.trim();
    if (hostId == null || pin.isEmpty) {
      setState(() => _status = 'Select a host and enter a PIN first');
      return;
    }
    setState(() => _status = 'Pairing...');
    try {
      final ok = await _bridge.pairWithPin(hostId: hostId, pin: pin);
      setState(() => _status = ok ? 'Pairing successful' : 'Pairing failed');
      await _refreshHosts();
    } catch (e) {
      setState(() => _status = 'Pairing error: $e');
    }
  }

  Future<void> _startStream() async {
    final hostId = _selectedHostId;
    if (hostId == null) {
      setState(() => _status = 'Select a host first');
      return;
    }
    setState(() => _status = 'Starting stream...');
    try {
      final ok = await _bridge.startStream(
        hostId: hostId,
        width: 1920,
        height: 1080,
        fps: 60,
      );
      setState(() => _status = ok ? 'Stream started (stub)' : 'Failed to start stream');
    } catch (e) {
      setState(() => _status = 'Start stream error: $e');
    }
  }

  Future<void> _stopStream() async {
    setState(() => _status = 'Stopping stream...');
    try {
      await _bridge.stopStream();
      setState(() => _status = 'Stream stopped');
    } catch (e) {
      setState(() => _status = 'Stop stream error: $e');
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
          title: Text(_status),
          trailing: FilledButton.icon(
            onPressed: _refreshHosts,
            icon: const Icon(Icons.refresh),
            label: const Text('Discover'),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _hosts.isEmpty
              ? const Center(child: Text('No hosts discovered yet'))
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PIN pairing channel',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use the PIN shown on your Mac host. This is the same UX idea as Steam Link / Moonlight pairing.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedHostId,
            items: _hosts
                .map((h) => DropdownMenuItem<String>(value: h.id, child: Text('${h.name} (${h.address})')))
                .toList(),
            onChanged: (v) => setState(() => _selectedHostId = v),
            decoration: const InputDecoration(labelText: 'Host'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PIN',
              hintText: 'e.g. 1234',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _pair,
            icon: const Icon(Icons.link),
            label: const Text('Pair now'),
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
          const Text('Native bridge stubs are wired for Android and iOS.'),
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
}
