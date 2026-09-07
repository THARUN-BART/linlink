import 'package:flutter/material.dart';
import '../clipboard/clipboard_service.dart';
import '../pairing/pairing_service.dart';
import '../scanner/views/scanner_screen.dart';
import '../storage/file_agent.dart';
import '../storage/remote_file_browser_screen.dart';
import '../storage/storage_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  PairedCompanion? _pairedCompanion;
  bool _isCheckingStatus = false;
  bool _hasStoragePermission = false;
  bool _isSyncingClipboard = false;
  bool _isSendingFile = false;
  String _lastSyncedClipboard = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ClipboardService.onClipboardSynced = (text) {
      if (mounted) {
        setState(() => _lastSyncedClipboard = text);
      }
    };
    _checkStorage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ClipboardService.stopAutoSync();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStorage();
      if (_pairedCompanion != null) {
        ClipboardService.syncNow(_pairedCompanion!);
      }
    }
  }

  Future<void> _checkStorage() async {
    final hasPerm = await StorageService.hasStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = hasPerm);
    }
  }

  Future<void> _requestStorage() async {
    final granted = await StorageService.requestStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: granted ? Colors.teal.shade800 : Colors.red.shade800,
          content: Text(
            granted
                ? '✅ Storage permission granted!'
                : '⚠️ Storage permission denied. Please grant All Files Access in Settings.',
          ),
        ),
      );
    }
  }

  Future<void> _sendClipboardToLinux() async {
    if (_pairedCompanion == null) return;
    setState(() => _isSyncingClipboard = true);

    final text = await ClipboardService.readDeviceClipboard();
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        setState(() => _isSyncingClipboard = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📱 Device clipboard is empty.')),
        );
      }
      return;
    }

    final success = await ClipboardService.sendToCompanion(
      companion: _pairedCompanion!,
      text: text,
    );

    if (mounted) {
      setState(() {
        _isSyncingClipboard = false;
        if (success) _lastSyncedClipboard = text;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? Colors.teal.shade800 : Colors.red.shade800,
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success
                      ? '📋 Copied to Linux Companion! ("${text.length > 30 ? '${text.substring(0, 30)}…' : text}")'
                      : '❌ Failed to copy to Linux Companion.',
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _fetchClipboardFromLinux() async {
    if (_pairedCompanion == null) return;
    setState(() => _isSyncingClipboard = true);

    final text = await ClipboardService.fetchFromCompanion(_pairedCompanion!);

    if (mounted) {
      setState(() => _isSyncingClipboard = false);

      if (text != null && text.isNotEmpty) {
        await ClipboardService.writeDeviceClipboard(text);
        if (!mounted) return;
        setState(() => _lastSyncedClipboard = text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.teal.shade800,
            content: Row(
              children: [
                const Icon(Icons.content_paste, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📋 Copied from Linux to Android! ("${text.length > 30 ? '${text.substring(0, 30)}…' : text}")',
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ℹ️ Linux Companion clipboard is empty.')),
        );
      }
    }
  }

  Future<void> _sendTestFileToLinux() async {
    if (_pairedCompanion == null) return;
    setState(() => _isSendingFile = true);

    final timestamp = DateTime.now().toIso8601String();
    final filename = 'linlink_note_${DateTime.now().millisecondsSinceEpoch}.txt';
    final content = 'Hello from Android device (${_pairedCompanion!.deviceName})!\n'
        'Sent at: $timestamp\n'
        'Storage Access: ${_hasStoragePermission ? "Active" : "Standard"}\n';

    final success = await StorageService.uploadFileToCompanion(
      companion: _pairedCompanion!,
      filename: filename,
      content: content,
    );

    if (mounted) {
      setState(() => _isSendingFile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? Colors.teal.shade800 : Colors.red.shade800,
          content: Text(
            success
                ? '📁 File transferred to Linux: ~/Downloads/LinLink/$filename'
                : '❌ Failed to send file to Linux Companion.',
          ),
        ),
      );
    }
  }

  Future<void> _checkConnection() async {
    if (_pairedCompanion == null) return;

    setState(() => _isCheckingStatus = true);
    final status = await PairingService.checkStatus(_pairedCompanion!);
    setState(() => _isCheckingStatus = false);

    if (!mounted) return;

    if (status != null && status['status'] == 'ok') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade800,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bridge is alive! State: ${status['state']} (${status['host']}:${status['port']})',
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Companion is unreachable. Make sure linlink is running.'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _unlinkDevice() async {
    if (_pairedCompanion == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Device?'),
        content: Text(
          'Are you sure you want to disconnect and unlink from ${_pairedCompanion!.baseUrl}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unlink'),
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
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device unlinked successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLinked = _pairedCompanion != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LinLink 📱 ↔ 💻'),
        centerTitle: true,
        actions: [
          if (isLinked)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Check Connection',
              onPressed: _isCheckingStatus ? null : _checkConnection,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: isLinked ? _buildLinkedView() : _buildUnlinkedView(),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlinkedView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.cyan.withAlpha(25),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.phonelink_ring_outlined,
            size: 72,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Phone ↔ Linux Bridge',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'No Linux companion linked yet.\nScan the pairing QR code to establish a link.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 36),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyan.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.qr_code_scanner, size: 24),
          label: const Text(
            'Scan QR Code to Link',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: () async {
            final companion = await Navigator.of(context).push<PairedCompanion>(
              MaterialPageRoute(
                builder: (context) => const ScannerScreen(),
              ),
            );

            if (companion != null && mounted) {
              setState(() {
                _pairedCompanion = companion;
              });
              await AndroidFileAgent.startServer(companion: companion);
              ClipboardService.startAutoSync(companion);
              if (!mounted) return;
              _checkStorage();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.teal.shade800,
                  content: Text(
                    '🎉 Successfully linked to ${companion.baseUrl}! Live clipboard sync active.',
                  ),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 32),
        _buildStoragePermissionCard(),
        const SizedBox(height: 32),
        Card(
          elevation: 0,
          color: Colors.white.withAlpha(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal, size: 20, color: Colors.cyanAccent),
                    SizedBox(width: 8),
                    Text(
                      'How to Link:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  '1. On your Linux PC, run:\n   `linlink pair`',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                SizedBox(height: 6),
                Text(
                  '2. Make sure both devices are on the same Wi-Fi.',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                SizedBox(height: 6),
                Text(
                  '3. Tap "Scan QR Code to Link" above and point your camera at the QR code.',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkedView() {
    final comp = _pairedCompanion!;

    return Column(
      children: [
        const SizedBox(height: 8),
        // Active status card
        Card(
          elevation: 2,
          color: Colors.teal.shade900.withAlpha(80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.greenAccent, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'DEVICE IS LINKED',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                _buildInfoRow(
                  icon: Icons.computer,
                  label: 'Companion Server',
                  value: comp.baseUrl,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  icon: Icons.smartphone,
                  label: 'This Device Name',
                  value: comp.deviceName,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  icon: Icons.vpn_key,
                  label: 'Session Token',
                  value: comp.token,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  icon: Icons.access_time,
                  label: 'Linked At',
                  value: '${comp.pairedAt.toLocal().hour.toString().padLeft(2, '0')}:'
                      '${comp.pairedAt.toLocal().minute.toString().padLeft(2, '0')}:'
                      '${comp.pairedAt.toLocal().second.toString().padLeft(2, '0')}',
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 💻 Linux File Explorer Card
        _buildLinuxFilesCard(),

        const SizedBox(height: 16),

        // 📋 Clipboard Sync Card
        _buildClipboardSyncCard(),

        const SizedBox(height: 16),

        // 📁 Storage Control Card
        _buildStoragePermissionCard(),

        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.cyanAccent),
                ),
                icon: _isCheckingStatus
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, color: Colors.cyanAccent),
                label: const Text(
                  'Ping Bridge',
                  style: TextStyle(color: Colors.cyanAccent),
                ),
                onPressed: _isCheckingStatus ? null : _checkConnection,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.link_off),
                label: const Text('Unlink'),
                onPressed: _unlinkDevice,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Card(
          elevation: 0,
          color: Colors.white.withAlpha(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.cyanAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your device is linked to ${comp.host}. Check companion status in Linux with `linlink status` or copy clipboard with `linlink clipboard`.',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinuxFilesCard() {
    return Card(
      elevation: 0,
      color: Colors.white.withAlpha(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.cyan, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.computer, color: Colors.cyanAccent, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Explore Linux Files & Folders 💻',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Browse files on your Linux PC, view folders, and transfer files between them directly over TCP.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyan.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.folder_open, size: 20),
                label: const Text(
                  'Open Linux File Explorer',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  if (_pairedCompanion == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => RemoteFileBrowserScreen(
                        companion: _pairedCompanion!,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClipboardSyncCard() {
    final isAutoSync = ClipboardService.isAutoSyncRunning;

    return Card(
      elevation: 0,
      color: Colors.white.withAlpha(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.cyan, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.content_paste, color: Colors.cyanAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Shared Clipboard 📋',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAutoSync ? Colors.teal.shade900 : Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isAutoSync ? Colors.tealAccent : Colors.white24,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isAutoSync ? Colors.greenAccent : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isAutoSync ? 'Live Sync ON' : 'Paused',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isAutoSync ? Colors.greenAccent : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isAutoSync
                  ? '⚡ Automatically syncing clipboard bidirectionally until connection stops.'
                  : 'Automatic clipboard sync is currently paused.',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Continuous Auto-Sync',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Switch(
                    value: isAutoSync,
                    activeThumbColor: Colors.tealAccent,
                    onChanged: (val) {
                      setState(() {
                        if (val && _pairedCompanion != null) {
                          ClipboardService.startAutoSync(_pairedCompanion!);
                        } else {
                          ClipboardService.stopAutoSync();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
            if (_lastSyncedClipboard.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  _lastSyncedClipboard,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _isSyncingClipboard
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload, size: 18),
                    label: const Text('Send to Linux', style: TextStyle(fontSize: 13)),
                    onPressed: _isSyncingClipboard ? null : _sendClipboardToLinux,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: const BorderSide(color: Colors.cyanAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Get from Linux', style: TextStyle(fontSize: 13)),
                    onPressed: _isSyncingClipboard ? null : _fetchClipboardFromLinux,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoragePermissionCard() {
    return Card(
      elevation: 0,
      color: Colors.white.withAlpha(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _hasStoragePermission ? Colors.greenAccent : Colors.orangeAccent,
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _hasStoragePermission ? Icons.folder_shared : Icons.folder_off,
                  color: _hasStoragePermission ? Colors.greenAccent : Colors.orangeAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Storage Control 📁',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _hasStoragePermission
                        ? Colors.green.withAlpha(40)
                        : Colors.orange.withAlpha(40),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _hasStoragePermission ? 'Granted' : 'Permission Needed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _hasStoragePermission ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _hasStoragePermission
                  ? 'All Files Access is active. You can control Android storage and transfer files to Linux.'
                  : 'Storage & file management permissions are needed to manage and browse Android files from Linux.',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (!_hasStoragePermission)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                  ),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Grant All Files / Storage Access'),
                  onPressed: _requestStorage,
                ),
              )
            else if (_pairedCompanion != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    side: const BorderSide(color: Colors.greenAccent),
                  ),
                  icon: _isSendingFile
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 18),
                  label: const Text('Send Test File to Linux Downloads'),
                  onPressed: _isSendingFile ? null : _sendTestFileToLinux,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.cyanAccent),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
