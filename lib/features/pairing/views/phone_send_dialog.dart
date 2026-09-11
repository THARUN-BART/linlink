import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../theme/linlink_theme.dart';
import '../../storage/file_agent.dart';


class PhoneSendDialog extends StatefulWidget {

  /// Opens the file picker and then shows the QR dialog if files are selected.
  static Future<bool?> pickAndShow(BuildContext context) async {
    // Step 1: Pick files
    final pickedFiles = await FilePicker.pickFiles(type: FileType.any);
    if (pickedFiles.isEmpty) return null;

    // Convert PlatformFile → File (need on-device paths)
    final files = <File>[];
    for (final pf in pickedFiles) {
      if (pf.path != null && File(pf.path!).existsSync()) {
        files.add(File(pf.path!));
      }
    }

    if (files.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access selected files.')),
        );
      }
      return null;
    }

    if (!context.mounted) return null;

    // Step 2: Show QR dialog with files queued
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (ctx) => PhoneSendDialog._internal(files: files),
    );
  }

  /// Internal constructor — only used by [pickAndShow].
  const PhoneSendDialog._internal({required this.files});
  final List<File> files;

  @override
  State<PhoneSendDialog> createState() => _PhoneSendDialogState();
}

class _PhoneSendDialogState extends State<PhoneSendDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  String? _selectedIp;
  List<String> _availableIps = [];
  String _sessionToken = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initServerAndQueue();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    AndroidFileAgent.onAllFilesServed = null;
    super.dispose();
  }

  Future<void> _initServerAndQueue() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ips = await AndroidFileAgent.getLocalIpv4Addresses();
      if (ips.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'No active Wi-Fi or Hotspot connection detected.\nConnect to Wi-Fi or turn on Mobile Hotspot.';
        });
        return;
      }

      final token = AndroidFileAgent.generateSessionToken();

      // Queue the picked files
      AndroidFileAgent.pendingP2PFiles = List.from(widget.files);

      final port = await AndroidFileAgent.startServer(
        token: token,
        deviceName: 'LinLink Sender',
      );

      if (port == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not start local server.';
        });
        return;
      }

      // Listen for completion
      AndroidFileAgent.onAllFilesServed = () {
        if (mounted) {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop(true);
        }
      };

      setState(() {
        _availableIps = ips;
        _selectedIp = ips.first;
        _sessionToken = token;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Initialization error: $e';
        });
      }
    }
  }

  String get _qrPayload {
    if (_selectedIp == null || _sessionToken.isEmpty) return '';
    return 'linlink://$_selectedIp:${AndroidFileAgent.currentPort}?t=$_sessionToken&mode=p2p';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  int get _totalSize {
    int total = 0;
    for (final f in widget.files) {
      try { total += f.lengthSync(); } catch (_) {}
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: LinLinkColors.surfaceContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LinLinkColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LinLinkColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.send_rounded, color: LinLinkColors.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send to Another Phone',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: LinLinkColors.onSurface,
                        ),
                      ),
                      Text(
                        '${widget.files.length} file${widget.files.length > 1 ? 's' : ''} · ${_formatSize(_totalSize)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: LinLinkColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // File list preview
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LinLinkColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: LinLinkColors.outlineVariant),
                ),
                constraints: const BoxConstraints(maxHeight: 100),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (ctx, i) {
                    final f = widget.files[i];
                    final name = f.uri.pathSegments.last;
                    int size = 0;
                    try { size = f.lengthSync(); } catch (_) {}
                    return Row(
                      children: [
                        Icon(
                          _iconForFile(name),
                          size: 16,
                          color: LinLinkColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 12, color: LinLinkColors.onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatSize(size),
                          style: const TextStyle(fontSize: 11, color: LinLinkColors.onSurfaceVariant),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              if (_isLoading) ...[
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: LinLinkColors.primary),
                const SizedBox(height: 12),
                const Text(
                  'Preparing...',
                  style: TextStyle(color: LinLinkColors.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 30),
              ] else if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: LinLinkColors.errorContainer.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LinLinkColors.errorContainer),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: LinLinkColors.error, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: LinLinkColors.onSurface, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _initServerAndQueue,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // QR Code
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: LinLinkColors.outlineVariant, width: 2),
                  ),
                  child: QrImageView(
                    data: _qrPayload,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF000000),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Waiting indicator
                FadeTransition(
                  opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_pulseController),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: LinLinkColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Ask receiver to scan this QR...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: LinLinkColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // IP info
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, color: LinLinkColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_selectedIp:${AndroidFileAgent.currentPort}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: LinLinkColors.onSurface,
                          ),
                        ),
                      ),
                      if (_availableIps.length > 1) ...[
                        DropdownButton<String>(
                          value: _selectedIp,
                          underline: const SizedBox.shrink(),
                          dropdownColor: LinLinkColors.surfaceContainerHigh,
                          items: _availableIps.map((ip) {
                            return DropdownMenuItem(
                              value: ip,
                              child: Text(ip, style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (newIp) {
                            if (newIp != null) setState(() => _selectedIp = newIp);
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 14),
              ],

              // Cancel button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    AndroidFileAgent.pendingP2PFiles = [];
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'].contains(ext)) return Icons.image;
    if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) return Icons.videocam;
    if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].contains(ext)) return Icons.audiotrack;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['zip', 'tar', 'gz', 'rar', '7z'].contains(ext)) return Icons.archive;
    if (['apk'].contains(ext)) return Icons.android;
    if (['doc', 'docx', 'txt', 'rtf', 'md'].contains(ext)) return Icons.description;
    return Icons.insert_drive_file;
  }
}
