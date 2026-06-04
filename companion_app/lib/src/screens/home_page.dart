import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/host_info.dart';
import '../services/stream_controller_mapping_store.dart';
import '../services/stream_controller_settings.dart';
import '../services/stream_touch_settings.dart';
import '../services/stream_log_share.dart';
import '../services/playnite_stream_foreground.dart' show PlayniteStreamNotification;
import '../services/pairing_cancellation.dart';
import '../services/streaming_bridge.dart';
import '../services/streaming_host_settings.dart';
import '../widgets/companion_insets.dart';
import '../widgets/controller_mapping_section.dart';
import '../widgets/controller_profile_section.dart';
import '../services/stream_controller_profile_store.dart';
import '../widgets/stream_shortcuts_picker_sheet.dart';
import '../widgets/companion_appearance_section.dart';
import '../widgets/stream_shortcuts_section.dart';
import '../services/stream_shortcuts_store.dart';

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
  String? _pairingHostId;
  PairingCancellation? _pairingCancellation;
  bool _streamActive = false;
  bool _streamViewerOpen = false;
  bool _externalStopLogDialogPending = false;
  String? _lastOfferedStreamLogPath;
  StreamControllerSettings? _controllerSettings;
  StreamTouchSettings? _touchSettings;
  List<StreamControllerElementMapping> _controllerBindings = const [];
  List<StreamControllerProfile> _controllerProfiles = const [];
  String? _activeControllerProfileId;
  List<ConnectedControllerInfo> _connectedControllers = const [];
  String _controllerStatus = 'Connect a telescopic or Bluetooth gamepad to this phone.';
  bool _controllersRefreshing = false;
  bool _startingStream = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      _bridge.installExternalStopListener(_onStreamStoppedExternally);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadSettings());
      unawaited(_loadControllerSettings());
      unawaited(_loadTouchSettings());
      if (Platform.isAndroid) {
        unawaited(PlayniteStreamNotification.ensureNotificationPermission());
      }
      unawaited(StreamShortcutsStore.migrateCloseAppDefaultIfNeeded());
      unawaited(_refreshStreamSessionState());
      unawaited(_checkPendingMappingOverlay());
      unawaited(_checkPendingShortcutsOverlay());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // After notification Stop, wait one frame so native onResume finishes before getStreamSession.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refreshStreamSessionState());
      });
      unawaited(_checkPendingMappingOverlay());
      unawaited(_checkPendingShortcutsOverlay());
      unawaited(_reloadControllerMappingState());
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
    await _reloadControllerMappingState();
    if (!mounted) return;
    setState(() => _controllerSettings = settings);
    await _refreshConnectedControllers();
  }

  Future<void> _reloadControllerMappingState() async {
    final mappingStore = await StreamControllerMappingStore.load();
    await mappingStore.syncFromLegacyBindings();
    if (!mounted) return;
    setState(() {
      _controllerBindings = mappingStore.bindings;
      _controllerProfiles = mappingStore.profiles;
      _activeControllerProfileId = mappingStore.activeProfileId;
    });
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
    double? swapStickSensitivity,
  }) async {
    final current = _touchSettings ?? await StreamTouchSettings.load();
    await current.save(
      cursorSpeed: cursorSpeed,
      tapSlopPercent: tapSlopPercent,
      tapTimeoutMs: tapTimeoutMs,
      tapPressurePercent: tapPressurePercent,
      swapStickSensitivity: swapStickSensitivity,
    );
    if (swapStickSensitivity != null && Platform.isAndroid) {
      await _bridge.updateSwapStickSensitivity(swapStickSensitivity);
    }
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
    setState(() {
      _controllerBindings = bindings;
      _controllerProfiles = store.profiles;
    });
  }

  /// True when [status] describes an in-progress or running stream (not idle/pairing copy).
  static bool _isLiveStreamSessionStatus(String status) {
    final lower = status.toLowerCase();
    return lower == 'streaming' ||
        lower.contains('stream running') ||
        lower.contains('opening stream') ||
        lower.contains('starting desktop') ||
        lower.contains('stopping stream');
  }

  Future<void> _refreshStreamSessionState() async {
    if (_startingStream) return;
    final session = await _bridge.getStreamSession();
    if (!mounted) return;
    final active = session['hostStreamActive'] == true;
    final viewerOpen = session['viewerOpen'] == true;
    final wasActive = _streamActive;
    final host = _hosts.where((h) => h.id == _selectedHostId).firstOrNull;
    await PlayniteStreamNotification.syncSession(
      active: active,
      hostLabel: host?.name ?? (session['host'] as String?),
    );
    if (!mounted) return;
    setState(() {
      _streamActive = active;
      _streamViewerOpen = viewerOpen;
      if (!active) {
        _startingStream = false;
      }
      if (active && !viewerOpen) {
        _sessionStatus =
            'Stream running — Enter current stream, or use notification Stop / Controller / Shortcuts.';
      } else if (!active && _isLiveStreamSessionStatus(_sessionStatus)) {
        _sessionStatus = 'Stream stopped';
      }
    });
    if (!active && wasActive) {
      await PlayniteStreamNotification.syncSession(active: false);
    }
    await _offerPendingStreamLog(session);
  }

  /// Notification Stop finishes while [MainActivity] is stopped — offer log after resume refresh.
  Future<void> _offerPendingStreamLog(Map<String, dynamic> session) async {
    final logPath = session['pendingExternalStopLogPath'] as String?;
    if (logPath == null || logPath.isEmpty || !mounted) return;
    if (_externalStopLogDialogPending || _lastOfferedStreamLogPath == logPath) return;
    _externalStopLogDialogPending = true;
    _lastOfferedStreamLogPath = logPath;
    try {
      await offerStreamLogShare(context, logPath);
    } finally {
      _externalStopLogDialogPending = false;
      await _bridge.clearPendingExternalStopLog();
    }
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

  Future<void> _checkPendingShortcutsOverlay() async {
    if (!Platform.isAndroid || !mounted) return;
    final pending = await PlayniteStreamNotification.consumePendingOpenShortcuts();
    if (!pending || !mounted) return;
    final shown = await PlayniteStreamNotification.showStreamShortcutsOverlay();
    if (shown || !mounted) return;
    await showStreamShortcutsPickerSheet(context);
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
              padding: CompanionInsets.mappingTilesHorizontal(sheetContext),
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

    final cancellation = PairingCancellation();
    final wasPaired = host.paired;
    setState(() {
      _pairingInProgress = true;
      _pairingHostId = host.id;
      _pairingCancellation = cancellation;
      _selectedHostId = host.id;
      _pairingStatus = wasPaired
          ? 'Requesting re-pair… approve on your Mac.'
          : 'Requesting pairing…';
    });

    try {
      final outcome = await _bridge.pairWithHost(
        hostId: host.id,
        cancellation: cancellation,
        onProgress: (message) {
          if (mounted) setState(() => _pairingStatus = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _pairingInProgress = false;
        _pairingHostId = null;
        _pairingCancellation = null;
        if (outcome.cancelled) {
          _pairingStatus = 'Pairing cancelled. Tap Pair when you are ready on the Mac.';
        } else if (outcome.ok) {
          _pairingStatus = wasPaired
              ? 'Re-paired with ${host.name}'
              : 'Paired with ${host.name}';
        } else {
          _pairingStatus = _shortError(outcome.message ?? 'Failed');
        }
      });
      if (outcome.ok) await _refreshHosts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairingInProgress = false;
        _pairingHostId = null;
        _pairingCancellation = null;
        _pairingStatus = _shortError('Pairing error: $e');
      });
    }
  }

  Future<void> _cancelPairing() async {
    if (!_pairingInProgress) return;
    _pairingCancellation?.cancel();
    setState(() => _pairingStatus = 'Cancelling pairing…');
    await _bridge.cancelPairing();
  }

  String _shortError(String message) {
    const maxLen = 220;
    if (message.length <= maxLen) return message;
    return '${message.substring(0, maxLen)}…';
  }

  Future<void> _startStream() async {
    if (_startingStream) return;
    final session = await _bridge.getStreamSession();
    if (!mounted) return;
    final nativeActive = session['hostStreamActive'] == true;
    final viewerOpen = session['viewerOpen'] == true;
    // After Back, the Mac may still be streaming while the viewer is closed — reopen it.
    if (nativeActive && !viewerOpen) {
      setState(() {
        _streamActive = true;
        _streamViewerOpen = false;
        _sessionStatus = 'Opening stream view…';
      });
      await _reenterStream();
      return;
    }
    if (nativeActive && viewerOpen) {
      await _reenterStream();
      return;
    }
    if (_streamActive) {
      setState(() {
        _streamActive = false;
        _streamViewerOpen = false;
        if (_isLiveStreamSessionStatus(_sessionStatus)) {
          _sessionStatus = 'Stream stopped';
        }
      });
    }
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

    _startingStream = true;
    setState(() => _sessionStatus = 'Starting Desktop stream…');
    try {
      if (Platform.isAndroid) {
        await PlayniteStreamNotification.ensureNotificationPermission();
      }
      final mappingStore = await StreamControllerMappingStore.load();
      final outcome = await _bridge.startStream(
        hostId: hostId,
        width: 1920,
        height: 1080,
        fps: 60,
        controllerBindingsJson: mappingStore.bindingsJson(),
      );
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _streamActive = false;
        _sessionStatus = 'Start stream error: $e';
      });
      await PlayniteStreamNotification.syncSession(active: false);
    } finally {
      _startingStream = false;
    }
  }

  Future<void> _reenterStream() async {
    if (_startingStream) return;
    _startingStream = true;
    setState(() => _sessionStatus = 'Opening stream view…');
    try {
      final ok = await _bridge.resumeStream();
      if (!mounted) return;
      setState(() {
        _streamViewerOpen = ok;
        _streamActive = ok || _streamActive;
        _sessionStatus = ok
            ? 'Stream running — video view open.'
            : 'Could not reopen stream. Tap Stop, then Start again.';
      });
      await _refreshStreamSessionState();
    } finally {
      _startingStream = false;
    }
  }

  Future<void> _onStreamStoppedExternally({String? logPath}) async {
    if (!mounted || _startingStream) return;
    _startingStream = false;
    await _bridge.ensureHostStreamStopped();
    if (!mounted) return;
    setState(() {
      _streamActive = false;
      _streamViewerOpen = false;
      if (_isLiveStreamSessionStatus(_sessionStatus)) {
        _sessionStatus = 'Stream stopped';
      }
    });
    await PlayniteStreamNotification.syncSession(active: false);
    await _refreshStreamSessionState();
    if (logPath != null && logPath.isNotEmpty && mounted) {
      _lastOfferedStreamLogPath = logPath;
      await offerStreamLogShare(context, logPath);
      await _bridge.clearPendingExternalStopLog();
    }
  }

  Future<void> _stopStream() async {
    setState(() => _sessionStatus = 'Stopping stream…');
    try {
      final logPath = await _bridge.stopStream();
      await _bridge.ensureHostStreamStopped();
      if (!mounted) return;
      setState(() {
        _streamActive = false;
        _streamViewerOpen = false;
        _sessionStatus = 'Stream stopped';
      });
      if (logPath != null && logPath.isNotEmpty) {
        _lastOfferedStreamLogPath = logPath;
        await offerStreamLogShare(context, logPath);
        await _bridge.clearPendingExternalStopLog();
      }
      await PlayniteStreamNotification.syncSession(active: false);
      await _refreshStreamSessionState();
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
          return CompanionInsets.wrapNavigationBar(
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => _tabIndex.value = i,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.dns), label: 'Hosts'),
                NavigationDestination(icon: Icon(Icons.videogame_asset), label: 'Session'),
                NavigationDestination(icon: Icon(Icons.sports_esports), label: 'Controller'),
                NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
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
          trailing: OutlinedButton.icon(
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
                        trailing: _pairingInProgress && _pairingHostId == host.id
                            ? OutlinedButton(
                                onPressed: _cancelPairing,
                                child: const Text('Cancel'),
                              )
                            : OutlinedButton(
                                onPressed: _pairingInProgress ? null : () => _pairHost(host),
                                child: Text(host.paired ? 'Pair again' : 'Pair'),
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
    final canStart = selected?.paired == true && (!_streamActive || !_streamViewerOpen);
    final canReenter = _streamActive && !_streamViewerOpen;

    return SingleChildScrollView(
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
            'While streaming, use the notification Stop, Swap, Controller, or Shortcuts buttons (Stop matches the Session tab). '
            'To start a fresh stream after leaving the video with Back, tap Stop here first, then Start.',
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
              FilledButton.icon(
                onPressed: canStart ? _startStream : null,
                icon: Icon(canReenter ? Icons.fullscreen : Icons.play_arrow),
                label: Text(
                  canReenter ? 'Resume stream view' : 'Start Desktop 1080p60',
                ),
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
    final listPad = CompanionInsets.listPadding(context);
    final contentPad = EdgeInsets.fromLTRB(listPad.left, 0, listPad.right, 0);
    final tilePad = CompanionInsets.mappingTilesHorizontal(context);

    return ListView(
      padding: EdgeInsets.only(top: listPad.top, bottom: listPad.bottom),
      children: [
        Padding(
          padding: contentPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
        if (isAndroid) ...[
          ControllerProfileSection(
            profiles: _controllerProfiles,
            activeProfileId: _activeControllerProfileId,
            onProfilesChanged: _reloadControllerMappingState,
          ),
          const Text(
            'Button → keyboard mapping',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Mapped buttons send keyboard chords or toggle Swap mouse mode (except A, B, and X — '
            'those are used by Swap for click and drag). Unmapped buttons are ignored by the phone UI.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
            ],
          ),
        ),
        if (isAndroid)
          Padding(
            padding: tilePad,
            child: ControllerMappingSection(
              bridge: _bridge,
              bindings: _controllerBindings,
              connectedControllers: _connectedControllers,
              onBindingsChanged: _persistControllerBindings,
              showIntro: false,
            ),
          )
        else
          Padding(
            padding: contentPad,
            child: Text(
              'Button→keyboard mapping during streams is available on Android.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        if (isAndroid) ...[
          Padding(
            padding: contentPad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: CompanionInsets.listPadding(context),
      children: [
        const CompanionAppearanceSection(),
        const SizedBox(height: 28),
        const Text(
          'Notification Swap button',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'While a stream is running, open the Playnite stream notification and tap Swap, or map '
          'Swap to another controller button on the Controller tab (not A, B, or X). Tap again '
          'to return to your normal keyboard mappings.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        const Text(
          'When Swap is on:',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '• Left analog stick moves the Mac cursor\n'
          '• A (Cross on PlayStation) — left click\n'
          '• B (Circle on PlayStation) — right click\n'
          '• X (Square on PlayStation) — hold while moving the left stick to highlight text or drag',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (_touchSettings == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ListTile(
            title: const Text('Swap stick cursor speed'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'How fast the left stick moves the Mac cursor while Swap is on. '
                  'Lower is slower and easier to control.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _touchSettings!.swapStickSensitivity,
                  min: 0.05,
                  max: 1.0,
                  divisions: 19,
                  label: _touchSettings!.swapStickSensitivity.toStringAsFixed(2),
                  onChanged: (value) => _saveTouchSettings(swapStickSensitivity: value),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        const StreamShortcutsSection(),
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
      scrollable: true,
      title: const Text('Add Mac host IP'),
      content: Column(
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
