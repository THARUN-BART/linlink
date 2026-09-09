import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/linlink_theme.dart';
import '../clipboard/clipboard_service.dart';
import '../pairing/pairing_service.dart';
import '../storage/file_agent.dart';
import '../storage/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final PairedCompanion? pairedCompanion;
  final VoidCallback onPairNew;
  final VoidCallback onUnlink;

  const SettingsScreen({
    super.key,
    required this.pairedCompanion,
    required this.onPairNew,
    required this.onUnlink,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _cameraGranted = false;
  bool _storageGranted = false;
  bool _autoAcceptTransfers = true;
  final String _downloadPath = 'Download/LinLink';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final camera = await Permission.camera.isGranted;
    final storage = await StorageService.hasStoragePermission();
    if (mounted) {
      setState(() {
        _cameraGranted = camera;
        _storageGranted = storage;
      });
    }
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() => _cameraGranted = status.isGranted);
    }
  }

  Future<void> _requestStorage() async {
    final granted = await StorageService.requestStoragePermission();
    if (mounted) {
      setState(() => _storageGranted = granted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLinked = widget.pairedCompanion != null;
    final isLiveSync = ClipboardService.isAutoSyncRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: LinLinkColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Companion bridge configuration and device permissions',
            style: TextStyle(
              fontSize: 13,
              color: LinLinkColors.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 18),

          // Session / Link Status Overview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LinLinkColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: LinLinkColors.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isLinked ? Icons.computer : Icons.computer_outlined,
                    color: isLinked ? LinLinkColors.primary : LinLinkColors.outline,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isLinked ? widget.pairedCompanion!.deviceName : 'Not Paired',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: LinLinkColors.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isLinked ? LinLinkColors.secondaryContainer : LinLinkColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isLinked ? 'CONNECTED' : 'DISCONNECTED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isLinked ? LinLinkColors.onSecondaryContainer : LinLinkColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLinked
                            ? '${widget.pairedCompanion!.host}:${widget.pairedCompanion!.port} • Local Wi-Fi'
                            : 'No companion computer currently connected',
                        style: const TextStyle(
                          fontSize: 12,
                          color: LinLinkColors.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Connection Management Section
          _buildSectionHeader(Icons.lan_outlined, 'Connection'),
          Material(
            color: LinLinkColors.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: LinLinkColors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: const Icon(Icons.qr_code_scanner, size: 20, color: LinLinkColors.primary),
                  title: const Text('Pair Computer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Scan QR code from `linlink pair`', style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant)),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: LinLinkColors.outline),
                  onTap: widget.onPairNew,
                ),
                if (isLinked) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: const Icon(Icons.link_off, size: 20, color: LinLinkColors.error),
                    title: const Text('Unlink Computer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LinLinkColors.error)),
                    subtitle: const Text('Revoke current cryptographic session', style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant)),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: LinLinkColors.error),
                    onTap: widget.onUnlink,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Sync & Transfers Section
          _buildSectionHeader(Icons.sync_alt, 'Sync & Transfers'),
          Material(
            color: LinLinkColors.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: LinLinkColors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Live Clipboard Sync', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text('Bi-directional background text mirroring', style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Switch(
                        value: isLiveSync,
                        onChanged: (val) {
                          if (!isLinked) {
                            widget.onPairNew();
                            return;
                          }
                          setState(() {
                            if (val) {
                              ClipboardService.startAutoSync(widget.pairedCompanion!);
                            } else {
                              ClipboardService.stopAutoSync();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Auto-Accept Transfers', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text('Automatically save incoming files from paired Linux host', style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _autoAcceptTransfers,
                        onChanged: (val) => setState(() => _autoAcceptTransfers = val),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Remote Directory Browsing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text(
                              'Allow Linux to view phone folders. Disabled by default for privacy.',
                              style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: AndroidFileAgent.allowRemoteBrowsing,
                        onChanged: (val) => setState(() => AndroidFileAgent.allowRemoteBrowsing = val),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text('Download Directory', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(_downloadPath, style: const TextStyle(fontSize: 12, color: LinLinkColors.primary, fontFamily: 'monospace')),
                  trailing: const Icon(Icons.folder_outlined, size: 18, color: LinLinkColors.outline),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Files saved to device Download/LinLink folder')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Permissions Section
          _buildSectionHeader(Icons.security, 'Permissions'),
          Material(
            color: LinLinkColors.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: LinLinkColors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildPermissionRow(
                  icon: Icons.camera_alt_outlined,
                  title: 'Camera Access',
                  subtitle: 'Required for scanning pairing QR code',
                  isGranted: _cameraGranted,
                  onRequest: _requestCamera,
                ),
                const Divider(height: 1),
                _buildPermissionRow(
                  icon: Icons.folder_shared_outlined,
                  title: 'Storage Access',
                  subtitle: 'Required for reading and saving transferred files',
                  isGranted: _storageGranted,
                  onRequest: _requestStorage,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // About Section
          _buildSectionHeader(Icons.info_outline, 'About LinLink'),
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
                    const Text('LinLink Peer Bridge', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: LinLinkColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'v1.0.0',
                        style: TextStyle(fontSize: 10, color: LinLinkColors.onSurfaceVariant, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Zero-cloud local network utility connecting mobile devices to Linux workstations.',
                  style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 14, color: LinLinkColors.secondary),
                    SizedBox(width: 6),
                    Text('Direct TCP & TLS 1.3 socket', style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: LinLinkColors.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 15, color: LinLinkColors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: LinLinkColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: LinLinkColors.onSurfaceVariant, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant)),
      trailing: isGranted
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: LinLinkColors.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Granted',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: LinLinkColors.onSecondaryContainer),
              ),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              onPressed: onRequest,
              child: const Text('Grant', style: TextStyle(fontSize: 12)),
            ),
    );
  }
}
