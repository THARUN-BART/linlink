import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../theme/linlink_theme.dart';
import '../../storage/file_agent.dart';
import '../pairing_service.dart';

/// Modal bottom sheet / dialog displaying this phone's pairing QR code
/// for zero-config phone-to-phone direct transfers over local Wi-Fi or Hotspot.
class PhoneReceiveDialog extends StatefulWidget {
  final String? initialDeviceName;

  const PhoneReceiveDialog({super.key, this.initialDeviceName});

  static Future<PairedCompanion?> show(
    BuildContext context, {
    String? initialDeviceName,
  }) {
    return showModalBottomSheet<PairedCompanion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PhoneReceiveDialog(initialDeviceName: initialDeviceName),
    );
  }

  @override
  State<PhoneReceiveDialog> createState() => _PhoneReceiveDialogState();
}

class _PhoneReceiveDialogState extends State<PhoneReceiveDialog> with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late AnimationController _pulseController;
  String? _selectedIp;
  List<String> _availableIps = [];
  String _sessionToken = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialDeviceName ?? 'Android Phone',
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initServerAndNetwork();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initServerAndNetwork() async {
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
              'No active Wi-Fi or Hotspot connection detected.\nPlease connect to Wi-Fi or turn on Mobile Hotspot.';
        });
        return;
      }

      final token = AndroidFileAgent.generateSessionToken();
      final port = await AndroidFileAgent.startServer(
        token: token,
        deviceName: _nameController.text.trim(),
      );

      if (port == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not start local receiver server.';
        });
        return;
      }

      // Hook up onPeerPaired callback so we automatically close when sender connects
      AndroidFileAgent.onPeerPaired = (peer) {
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(peer);
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
    final name = Uri.encodeComponent(_nameController.text.trim());
    return 'linlink://$_selectedIp:${AndroidFileAgent.currentPort}?t=$_sessionToken&name=$name';
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

              // Title and badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LinLinkColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.phonelink_ring_rounded, color: LinLinkColors.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receive from Another Phone',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: LinLinkColors.onSurface,
                        ),
                      ),
                      Text(
                        'Zero-data local Wi-Fi / Hotspot P2P transfer',
                        style: TextStyle(
                          fontSize: 11,
                          color: LinLinkColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (_isLoading) ...[
                const SizedBox(height: 40),
                const CircularProgressIndicator(color: LinLinkColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'Preparing local receiver...',
                  style: TextStyle(color: LinLinkColors.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 40),
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
                      const Icon(Icons.wifi_off_rounded, color: LinLinkColors.error, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: LinLinkColors.onSurface, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _initServerAndNetwork,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry Connection'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // High contrast QR code presentation
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: LinLinkColors.outlineVariant, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _qrPayload,
                    version: QrVersions.auto,
                    size: 210.0,
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

                const SizedBox(height: 16),

                // Pulsing waiting indicator
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
                        'Waiting for sender phone to scan...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: LinLinkColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Network & IP Details
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, color: LinLinkColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LOCAL IP ADDRESS',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: LinLinkColors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '$_selectedIp:${AndroidFileAgent.currentPort}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: LinLinkColors.onSurface,
                              ),
                            ),
                          ],
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
                            if (newIp != null) {
                              setState(() => _selectedIp = newIp);
                            }
                          },
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: LinLinkColors.onSurfaceVariant),
                        tooltip: 'Copy pairing link',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _qrPayload));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied pairing link to clipboard')),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Strict Privacy Guarantee Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LinLinkColors.secondaryContainer.withAlpha(120)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: LinLinkColors.secondary, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Strict Privacy Shield',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: LinLinkColors.secondary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'The sending phone cannot browse or view your phone directories. Only files explicitly sent to you will be transferred directly to Downloads/LinLink.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: LinLinkColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Close Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
