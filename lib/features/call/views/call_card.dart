import 'package:flutter/material.dart';
import '../../../theme/linlink_theme.dart';
import '../../pairing/pairing_service.dart';
import '../call_service.dart';
import 'call_screen.dart';

class CallCard extends StatelessWidget {
  final PairedCompanion? companion;
  final VoidCallback? onRequestPair;

  const CallCard({
    super.key,
    required this.companion,
    this.onRequestPair,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallState>(
      valueListenable: CallService.stateNotifier,
      builder: (context, callState, _) {
        if (callState == CallState.ringing) {
          // Incoming Call Alert Banner
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: LinLinkColors.secondary, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: LinLinkColors.secondary.withValues(alpha: 0.2),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: LinLinkColors.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_in_talk, color: LinLinkColors.secondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Incoming Remote Call',
                        style: TextStyle(
                          color: LinLinkColors.secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${CallService.remoteDeviceName} wants to call (using PC mic & speaker)',
                        style: const TextStyle(
                          color: LinLinkColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => CallService.hangup(),
                  icon: const Icon(Icons.call_end, color: LinLinkColors.error),
                  tooltip: 'Decline',
                ),
                IconButton(
                  onPressed: () {
                    CallService.answerCall();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CallScreen(companion: companion, isIncoming: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.call, color: LinLinkColors.secondary),
                  tooltip: 'Answer',
                ),
              ],
            ),
          );
        }

        if (callState == CallState.inCall) {
          // Active in-call banner
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: LinLinkColors.secondary),
            ),
            child: Row(
              children: [
                const Icon(Icons.record_voice_over, color: LinLinkColors.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: CallService.durationNotifier,
                    builder: (context, seconds, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Active Call with Linux PC',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                          Text(
                            'Duration: ${CallService.formatDuration(seconds)} • PC Mic & Speaker Active',
                            style: const TextStyle(fontSize: 11, color: LinLinkColors.secondary),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CallScreen(companion: companion),
                      ),
                    );
                  },
                  child: const Text('Open Call UI'),
                ),
              ],
            ),
          );
        }

        // Standard Call Action Card
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: LinLinkColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: LinLinkColors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: LinLinkColors.primaryContainer.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.headset_mic_rounded, color: LinLinkColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Remote Calling & Audio Bridge',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      companion != null
                          ? 'Speak with PC microphone & listen through PC speaker'
                          : 'Pair with Linux PC to enable remote voice calling',
                      style: const TextStyle(
                        fontSize: 12,
                        color: LinLinkColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: const Icon(Icons.dialpad, size: 15),
                    label: const Text('Dial', style: TextStyle(fontSize: 12)),
                    onPressed: () => _showDialDialog(context),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: LinLinkColors.primaryContainer,
                      foregroundColor: LinLinkColors.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: const Icon(Icons.call, size: 15),
                    label: const Text('Call PC', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      if (companion == null) {
                        onRequestPair?.call();
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CallScreen(companion: companion),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDialDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LinLinkColors.surfaceContainer,
        title: const Row(
          children: [
            Icon(Icons.dialpad, color: LinLinkColors.primary),
            SizedBox(width: 10),
            Text('Remote Phone Call 📞'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a phone number to call your friend using your phone remotely while speaking and hearing through your PC:',
              style: TextStyle(fontSize: 12, color: LinLinkColors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'e.g. +1 555 123 4567',
                prefixIcon: const Icon(Icons.phone),
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
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.call, size: 16),
            label: const Text('Call Number'),
            onPressed: () {
              final number = controller.text.trim();
              if (number.isNotEmpty) {
                Navigator.of(ctx).pop();
                CallService.dialNumber(number, companion: companion);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CallScreen(companion: companion),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
