import 'package:flutter/material.dart';
import '../../theme/linlink_theme.dart';
import 'pairing_service.dart';

class PairingSuccessScreen extends StatelessWidget {
  final PairedCompanion companion;

  const PairingSuccessScreen({super.key, required this.companion});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinLinkColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),

              // Clean success badge (no fake glowing halos)
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: LinLinkColors.secondaryContainer.withAlpha(70),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: LinLinkColors.secondary.withAlpha(100),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_rounded,
                    color: LinLinkColors.secondary,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Connected to Linux',
                style: TextStyle(
                  color: LinLinkColors.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Secure local peer link established with ${companion.deviceName}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: LinLinkColors.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),

              // Target Peer Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: LinLinkColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: LinLinkColors.outlineVariant),
                ),
                child: Column(
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
                          child: const Icon(
                            Icons.desktop_windows,
                            color: LinLinkColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                companion.deviceName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: LinLinkColors.onSurface,
                                ),
                              ),
                              Text(
                                'Port ${companion.port}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: LinLinkColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: LinLinkColors.secondaryContainer.withAlpha(50),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: LinLinkColors.secondary.withAlpha(60)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 7, color: LinLinkColors.secondary),
                              SizedBox(width: 5),
                              Text(
                                'Online',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: LinLinkColors.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: LinLinkColors.outlineVariant, height: 1),
                    const SizedBox(height: 14),
                    _buildDetailRow(
                      icon: Icons.lan_outlined,
                      label: 'Network Address',
                      value: companion.host,
                      isMonospace: true,
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      icon: Icons.wifi,
                      label: 'Transport',
                      value: 'Local Area Network',
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      icon: Icons.lock_outline,
                      label: 'Security',
                      value: 'TLS End-to-End',
                      valueColor: LinLinkColors.secondary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Capabilities Overview
              Row(
                children: [
                  Expanded(
                    child: _buildCapTile(
                      icon: Icons.folder_outlined,
                      title: 'File Access',
                      subtitle: 'Browse & transfer',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCapTile(
                      icon: Icons.content_copy_outlined,
                      title: 'Clipboard',
                      subtitle: 'Real-time sync',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCapTile(
                      icon: Icons.send_outlined,
                      title: 'Notes',
                      subtitle: 'Direct push',
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Action button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: LinLinkColors.primary,
                    foregroundColor: LinLinkColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(companion);
                  },
                  child: const Text(
                    'Open Dashboard',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isMonospace = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: LinLinkColors.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: LinLinkColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: isMonospace ? 'monospace' : null,
            color: valueColor ?? LinLinkColors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildCapTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: LinLinkColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LinLinkColors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, color: LinLinkColors.primary, size: 20),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: LinLinkColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: LinLinkColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
