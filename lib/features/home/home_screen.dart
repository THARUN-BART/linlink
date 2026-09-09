import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/linlink_theme.dart';
import '../clipboard/clipboard_service.dart';
import '../clipboard/clipboard_view.dart';
import '../pairing/pairing_service.dart';
import '../pairing/pairing_success_screen.dart';
import '../pairing/views/phone_receive_dialog.dart';
import '../scanner/views/scanner_screen.dart';
import '../settings/settings_screen.dart';
import '../storage/file_agent.dart';
import '../storage/remote_file_browser_screen.dart';
import '../storage/storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _currentTabIndex = 0;
  PairedCompanion? _pairedCompanion;
  bool _isCheckingStatus = false;
  String _lastSyncedClipboard = '';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    ClipboardService.onClipboardSynced = (text) {
      if (mounted) {
        setState(() => _lastSyncedClipboard = text);
      }
    };

    AndroidFileAgent.onFileReceived = (filename, path) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: LinLinkColors.secondaryContainer,
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(Icons.download_done, color: LinLinkColors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📥 Received: $filename\nSaved in Downloads/LinLink',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    };

    AndroidFileAgent.onLinuxDisconnected = () {
      if (mounted) {
        ClipboardService.stopAutoSync();
        AndroidFileAgent.stopServer();
        setState(() {
          _pairedCompanion = null;
          _currentTabIndex = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: LinLinkColors.errorContainer,
            content: Row(
              children: [
                Icon(Icons.link_off, color: Colors.white),
                SizedBox(width: 8),
                Text('Linux companion stopped. Device unlinked.'),
              ],
            ),
          ),
        );
      }
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    ClipboardService.stopAutoSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pairedCompanion != null) {
        ClipboardService.syncNow(_pairedCompanion!);
      }
    }
  }

  Future<void> _openScanner() async {
    final companion = await Navigator.of(context).push<PairedCompanion>(
      MaterialPageRoute(
        builder: (context) => const ScannerScreen(),
      ),
    );

    if (companion != null && mounted) {
      // Show Pairing Success celebration screen
      await Navigator.of(context).push<PairedCompanion>(
        MaterialPageRoute(
          builder: (context) => PairingSuccessScreen(companion: companion),
        ),
      );

      if (!mounted) return;

      setState(() {
        _pairedCompanion = companion;
      });

      await AndroidFileAgent.startServer(companion: companion);
      if (!mounted) return;
      ClipboardService.startAutoSync(companion);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LinLinkColors.secondaryContainer,
          content: Text('🎉 Linked to ${companion.deviceName}! Live sync ready.'),
        ),
      );
    }
  }

  Future<void> _openPhoneReceiveDialog() async {
    final peer = await PhoneReceiveDialog.show(context);
    if (peer != null && mounted) {
      setState(() {
        _pairedCompanion = peer;
      });
      await AndroidFileAgent.startServer(companion: peer);
      if (!mounted) return;
      ClipboardService.startAutoSync(peer);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LinLinkColors.secondaryContainer,
          content: Text('🎉 Linked to ${peer.deviceName}! Ready to transfer files.'),
        ),
      );
    }
  }

  Future<void> _unlinkDevice() async {
    if (_pairedCompanion == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LinLinkColors.surfaceContainer,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: LinLinkColors.error),
            SizedBox(width: 8),
            Text('Unlink Device?'),
          ],
        ),
        content: Text(
          'Are you sure you want to disconnect and revoke the session with ${_pairedCompanion!.deviceName} (${_pairedCompanion!.host})?',
          style: const TextStyle(color: LinLinkColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LinLinkColors.errorContainer),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unlink', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    ClipboardService.stopAutoSync();
    await AndroidFileAgent.stopServer();
    await PairingService.unlink(_pairedCompanion!);

    if (mounted) {
      setState(() {
        _pairedCompanion = null;
        _currentTabIndex = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session revoked. Device unlinked.')),
      );
    }
  }

  Future<void> _pingBridge() async {
    if (_pairedCompanion == null) return;

    setState(() => _isCheckingStatus = true);
    final status = await PairingService.checkStatus(_pairedCompanion!);
    setState(() => _isCheckingStatus = false);

    if (!mounted) return;

    if (status != null && status['status'] == 'ok') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LinLinkColors.secondaryContainer,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Bridge is alive! State: ${status['state']} (${status['host']}:${status['port']})'),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: LinLinkColors.errorContainer,
          content: Text('Companion is unreachable. Make sure linlink is running on Linux.'),
        ),
      );
    }
  }

  Future<void> _showSendNoteDialog() async {
    if (_pairedCompanion == null) {
      _openScanner();
      return;
    }

    final noteController = TextEditingController();

    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LinLinkColors.surfaceContainer,
        title: Row(
          children: [
            const Icon(Icons.edit_note, color: LinLinkColors.secondary),
            const SizedBox(width: 8),
            Text('Send Note to ${_pairedCompanion!.deviceName} 📝'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quickly push a note as a .txt file directly to ${_pairedCompanion!.deviceName}:',
              style: const TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              autofocus: true,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Type your message or command here...',
                hintStyle: const TextStyle(color: LinLinkColors.outline),
                filled: true,
                fillColor: LinLinkColors.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LinLinkColors.primaryContainer,
              foregroundColor: LinLinkColors.onPrimaryContainer,
            ),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Send Note'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (send == true && noteController.text.trim().isNotEmpty) {
      final filename = 'note_${DateTime.now().millisecondsSinceEpoch}.txt';
      final success = await StorageService.uploadFileToCompanion(
        companion: _pairedCompanion!,
        filename: filename,
        content: noteController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? LinLinkColors.secondaryContainer : LinLinkColors.errorContainer,
            content: Text(
              success
                ? '✅ Sent to ${_pairedCompanion!.deviceName}: $filename'
                : '❌ Failed to send note to ${_pairedCompanion!.deviceName}.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickAndShareFiles() async {
    if (_pairedCompanion == null) {
      _openScanner();
      return;
    }

    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;

      final peerName = _pairedCompanion!.deviceName;
      int successCount = 0;
      for (final file in files) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 1),
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Sharing "${file.name}" to $peerName…')),
              ],
            ),
          ),
        );

        final success = await StorageService.uploadBinaryFile(
          companion: _pairedCompanion!,
          file: file,
        );

        if (success) successCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: LinLinkColors.secondaryContainer,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: LinLinkColors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    successCount == 1
                        ? 'Shared 1 file to $peerName!'
                        : 'Shared $successCount files to $peerName!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: LinLinkColors.errorContainer,
            content: Text('Failed to share file: $e'),
          ),
        );
      }
    }
  }

  Future<void> _sendClipboardNow() async {
    if (_pairedCompanion == null) {
      _openScanner();
      return;
    }

    final text = await ClipboardService.readDeviceClipboard();
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device clipboard is empty')),
        );
      }
      return;
    }

    final success = await ClipboardService.sendToCompanion(
      companion: _pairedCompanion!,
      text: text,
    );

    if (mounted) {
      setState(() => _lastSyncedClipboard = text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? LinLinkColors.secondaryContainer : LinLinkColors.errorContainer,
          content: Text(success ? 'Copied to Linux Companion' : 'Failed to send clipboard'),
        ),
      );
    }
  }

  Future<void> _getClipboardNow() async {
    if (_pairedCompanion == null) {
      _openScanner();
      return;
    }

    final text = await ClipboardService.fetchFromCompanion(_pairedCompanion!);
    if (mounted) {
      if (text != null && text.isNotEmpty) {
        await ClipboardService.writeDeviceClipboard(text);
        if (!mounted) return;
        setState(() => _lastSyncedClipboard = text);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied from Linux to device clipboard'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Linux companion clipboard is empty')),
        );
      }
    }
  }

  Future<void> _openManualPairing() async {
    final hostController = TextEditingController();
    final portController = TextEditingController(text: '7878');
    final tokenController = TextEditingController();
    final nameController = TextEditingController(text: 'Android Device');

    final companion = await showDialog<PairedCompanion>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: LinLinkColors.surfaceContainer,
        title: const Row(
          children: [
            Icon(Icons.lan, color: LinLinkColors.primary, size: 22),
            SizedBox(width: 10),
            Text('Manual Connection'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the IP address and session token displayed by `linlink pair` on your Linux host:',
                style: TextStyle(fontSize: 13, color: LinLinkColors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: hostController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Linux IP / Hostname',
                  hintText: '192.168.1.x',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '7878',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenController,
                decoration: const InputDecoration(
                  labelText: 'Session Token (or full link URL)',
                  hintText: 'e.g. 31327e36 or linlink://...',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Device Name (shown on Linux)',
                  hintText: 'Pixel 8',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final rawHost = hostController.text.trim();
              final rawToken = tokenController.text.trim();
              final targetFromToken = PairingTarget.tryParse(rawToken);
              final targetFromHost = PairingTarget.tryParse(rawHost);

              final target = targetFromToken ??
                  targetFromHost ??
                  PairingTarget(
                    host: rawHost,
                    port: int.tryParse(portController.text.trim()) ?? 7878,
                    token: rawToken,
                  );

              if (target.host.isEmpty || target.token.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide both host and session token')),
                );
                return;
              }

              Navigator.of(dialogCtx).pop();

              try {
                final deviceName = nameController.text.trim().isEmpty ? 'Android Device' : nameController.text.trim();
                final comp = await PairingService.pair(target: target, deviceName: deviceName);
                if (mounted) {
                  Navigator.of(context).push<PairedCompanion>(
                    MaterialPageRoute(
                      builder: (context) => PairingSuccessScreen(companion: comp),
                    ),
                  );
                  setState(() => _pairedCompanion = comp);
                  await AndroidFileAgent.startServer(companion: comp);
                  ClipboardService.startAutoSync(comp);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: LinLinkColors.errorContainer,
                      content: Text('Failed to pair: ${e.toString().replaceFirst('Exception: ', '')}'),
                    ),
                  );
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    if (companion != null && mounted) {
      setState(() => _pairedCompanion = companion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabTitles = ['Overview', 'Files', 'Clipboard', 'Settings'];
    final isLinked = _pairedCompanion != null;

    return Scaffold(
      backgroundColor: LinLinkColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: const BoxDecoration(
            color: LinLinkColors.surface,
            border: Border(bottom: BorderSide(color: LinLinkColors.outlineVariant, width: 1)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'LinLink',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: LinLinkColors.onSurface,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isLinked
                                  ? LinLinkColors.secondaryContainer
                                  : LinLinkColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isLinked ? LinLinkColors.secondary : LinLinkColors.outline,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isLinked ? 'LINKED' : 'STANDBY',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: isLinked ? LinLinkColors.onSecondaryContainer : LinLinkColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        tabTitles[_currentTabIndex],
                        style: const TextStyle(
                          fontSize: 11,
                          color: LinLinkColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (isLinked) ...[
                    IconButton(
                      icon: _isCheckingStatus
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: LinLinkColors.primary),
                            )
                          : const Icon(Icons.refresh, size: 20, color: LinLinkColors.onSurfaceVariant),
                      tooltip: 'Ping companion host',
                      onPressed: _isCheckingStatus ? null : _pingBridge,
                    ),
                  ] else ...[
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 32),
                      ),
                      icon: const Icon(Icons.qr_code_scanner, size: 16),
                      label: const Text('Pair'),
                      onPressed: _openScanner,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Main content — padded so it doesn't hide behind the floating nav
          Padding(
            padding: const EdgeInsets.only(bottom: 90),
            child: IndexedStack(
              index: _currentTabIndex,
              children: [
                // Tab 0: Home / Overview
                isLinked ? _buildLinkedHomeView() : _buildUnlinkedConnectView(),

                // Tab 1: Files
                RemoteFileBrowserScreen(
                  companion: _pairedCompanion,
                  onRequestPair: _openScanner,
                ),

                // Tab 2: Clipboard
                ClipboardView(
                  pairedCompanion: _pairedCompanion,
                  onRequestPair: _openScanner,
                ),

                // Tab 3: Settings
                SettingsScreen(
                  pairedCompanion: _pairedCompanion,
                  onPairNew: _openScanner,
                  onUnlink: _unlinkDevice,
                ),
              ],
            ),
          ),

          // Floating glass navigation bar
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: SafeArea(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: LinLinkColors.surface.withAlpha(180),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: LinLinkColors.outlineVariant.withAlpha(120),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(index: 0, icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Overview'),
                        _buildNavItem(index: 1, icon: Icons.folder_outlined, activeIcon: Icons.folder, label: 'Files'),
                        _buildNavItem(index: 2, icon: Icons.content_paste_outlined, activeIcon: Icons.content_paste, label: 'Clipboard'),
                        _buildNavItem(index: 3, icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = _currentTabIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTabIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? LinLinkColors.primary.withAlpha(30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                size: 20,
                color: isActive ? LinLinkColors.primary : LinLinkColors.onSurfaceVariant,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? LinLinkColors.primary : LinLinkColors.onSurfaceVariant,
                  letterSpacing: isActive ? 0.2 : 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= Unlinked State: Clean Power-User Onboarding =================
  Widget _buildUnlinkedConnectView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App icon hero
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Hero statement
          const Text(
            'Connect your Linux computer',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: LinLinkColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Secure local peer-to-peer bridge for seamless clipboard mirroring and file browsing on your local Wi-Fi.',
            style: TextStyle(
              fontSize: 13,
              color: LinLinkColors.onSurfaceVariant,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20),

          // Primary Terminal Instructions Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LinLinkColors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.terminal, color: LinLinkColors.primary, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Step 1: Run in Linux terminal',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LinLinkColors.onSurface),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: LinLinkColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'bash / zsh',
                        style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: LinLinkColors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '\$ ',
                        style: TextStyle(fontFamily: 'monospace', color: LinLinkColors.outline, fontSize: 13),
                      ),
                      const Expanded(
                        child: Text(
                          'linlink pair',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: LinLinkColors.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: LinLinkColors.onSurfaceVariant),
                        tooltip: 'Copy command',
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: 'linlink pair'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied "linlink pair" to clipboard')),
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Step 2: Scan the QR code printed in your terminal console to pair instantly.',
                  style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Primary & Secondary Pairing Actions
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openScanner,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR Code'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _openManualPairing,
                icon: const Icon(Icons.lan_outlined, size: 18),
                label: const Text('Enter IP'),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Phone to Phone P2P Direct Transfer Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LinLinkColors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.phone_android, color: LinLinkColors.secondary, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Phone-to-Phone Direct Transfer',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LinLinkColors.onSurface),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: LinLinkColors.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'P2P LAN',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LinLinkColors.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Transfer photos, videos, and files directly to another phone over Wi-Fi or Personal Hotspot with zero mobile data or internet used.',
                  style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant, height: 1.3),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 15, color: LinLinkColors.secondary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Privacy Mode Active: Neither phone can browse or view the other’s internal storage.',
                          style: TextStyle(fontSize: 11, color: LinLinkColors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: LinLinkColors.secondaryContainer,
                          foregroundColor: LinLinkColors.onSecondaryContainer,
                        ),
                        onPressed: _openPhoneReceiveDialog,
                        icon: const Icon(Icons.qr_code, size: 18),
                        label: const Text('Receive Files'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openScanner,
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Send to Phone'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Feature Architecture Highlights
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LinLinkColors.outlineVariant),
            ),
            child: Column(
              children: [
                _buildFeatureRow(
                  icon: Icons.wifi_protected_setup,
                  title: 'Local Wi-Fi Only',
                  description: 'Traffic never touches external servers or third-party cloud infrastructure.',
                ),
                const Divider(height: 1),
                _buildFeatureRow(
                  icon: Icons.sync_alt,
                  title: 'Live Clipboard Mirror',
                  description: 'Instant bi-directional text synchronization with wl-clipboard and X11.',
                ),
                const Divider(height: 1),
                _buildFeatureRow(
                  icon: Icons.folder_shared_outlined,
                  title: 'Remote Filesystem Access',
                  description: 'Explore remote directories, download assets, and upload documents over TCP.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: LinLinkColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LinLinkColors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= Linked State: Streamlined Companion Overview =================
  Widget _buildLinkedHomeView() {
    final comp = _pairedCompanion!;
    final isLiveSync = ClipboardService.isAutoSyncRunning;
    final isPhonePeer = comp.port == 7879 ||
        comp.deviceName.toLowerCase().contains('phone') ||
        comp.deviceName.toLowerCase().contains('android') ||
        comp.deviceName.toLowerCase().contains('mobile');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Peer Host Information Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LinLinkColors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: LinLinkColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(isPhonePeer ? Icons.phone_android : Icons.computer, color: LinLinkColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                comp.deviceName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: LinLinkColors.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: LinLinkColors.secondaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check, size: 10, color: LinLinkColors.secondary),
                                    SizedBox(width: 3),
                                    Text(
                                      'ONLINE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: LinLinkColors.onSecondaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${comp.host}:${comp.port}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: LinLinkColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LinLinkColors.error,
                        side: const BorderSide(color: LinLinkColors.outlineVariant),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 34),
                      ),
                      onPressed: _unlinkDevice,
                      child: const Text('Unlink', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Quick Action Grid (Share Files, Send Note, Browse Files)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickAndShareFiles,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: LinLinkColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: LinLinkColors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.upload_file, color: LinLinkColors.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Share Files', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(isPhonePeer ? 'Send to ${comp.deviceName}' : 'Send to Linux', style: const TextStyle(fontSize: 11, color: LinLinkColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _showSendNoteDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: LinLinkColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: LinLinkColors.outlineVariant),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.edit_note, color: LinLinkColors.secondary, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Send Note', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text('Push .txt text', style: TextStyle(fontSize: 11, color: LinLinkColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Privacy Protection Mode Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: LinLinkColors.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  AndroidFileAgent.allowRemoteBrowsing ? Icons.folder_shared : Icons.shield_outlined,
                  size: 18,
                  color: AndroidFileAgent.allowRemoteBrowsing ? Colors.amber : LinLinkColors.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AndroidFileAgent.allowRemoteBrowsing
                            ? 'Remote Browsing: ALLOWED'
                            : 'Privacy Mode: Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AndroidFileAgent.allowRemoteBrowsing ? Colors.amber : LinLinkColors.secondary,
                        ),
                      ),
                      Text(
                        AndroidFileAgent.allowRemoteBrowsing
                            ? 'Linux can view phone directory tree'
                            : 'Phone folders hidden from PC. Share files directly from phone.',
                        style: const TextStyle(fontSize: 10, color: LinLinkColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: AndroidFileAgent.allowRemoteBrowsing,
                  onChanged: (val) {
                    setState(() => AndroidFileAgent.allowRemoteBrowsing = val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          val
                              ? 'Remote directory browsing enabled for Linux'
                              : 'Privacy Mode enabled: Linux cannot browse phone directories',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Clipboard Integration Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LinLinkColors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.sync_alt, size: 18, color: LinLinkColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'Live Clipboard Sync',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: LinLinkColors.onSurface),
                        ),
                      ],
                    ),
                    Switch(
                      value: isLiveSync,
                      onChanged: (val) {
                        setState(() {
                          if (val) {
                            ClipboardService.startAutoSync(comp);
                          } else {
                            ClipboardService.stopAutoSync();
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isLiveSync
                      ? 'Clipboard is actively mirrored bi-directionally with ${comp.deviceName}.'
                      : 'Background mirroring is currently paused.',
                  style: const TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant),
                ),
                if (_lastSyncedClipboard.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: LinLinkColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: LinLinkColors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LAST SYNCED TEXT',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: LinLinkColors.onSurfaceVariant, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lastSyncedClipboard,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: LinLinkColors.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: LinLinkColors.surfaceContainerHigh,
                          foregroundColor: LinLinkColors.onSurface,
                          minimumSize: const Size(0, 38),
                        ),
                        icon: const Icon(Icons.arrow_upward, size: 16),
                        label: const Text('Send to Linux', style: TextStyle(fontSize: 12)),
                        onPressed: _sendClipboardNow,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                        ),
                        icon: const Icon(Icons.arrow_downward, size: 16),
                        label: const Text('Fetch from Linux', style: TextStyle(fontSize: 12)),
                        onPressed: _getClipboardNow,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
