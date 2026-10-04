import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/linlink_theme.dart';
import '../../pairing/pairing_service.dart';
import '../call_service.dart';

class CallScreen extends StatefulWidget {
  final PairedCompanion? companion;
  final bool isIncoming;

  const CallScreen({
    super.key,
    this.companion,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    CallService.onCallStateChanged = (state) {
      if (!mounted) return;
      if (state == CallState.idle) {
        Navigator.of(context).maybePop();
      } else {
        setState(() {});
      }
    };

    if (!widget.isIncoming && widget.companion != null && CallService.state == CallState.idle) {
      CallService.startCall(widget.companion!);
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallState>(
      valueListenable: CallService.stateNotifier,
      builder: (context, callState, _) {
        final deviceName = widget.companion?.deviceName ?? CallService.remoteDeviceName;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A), // Dark slate blue
          body: SafeArea(
            child: Stack(
              children: [
                // Background subtle gradient circles
                Positioned(
                  top: -100,
                  left: -50,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: LinLinkColors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80,
                  right: -50,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: LinLinkColors.secondary.withValues(alpha: 0.12),
                    ),
                  ),
                ),

                Column(
                  children: [
                    // Top App Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 28),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  callState == CallState.inCall ? Icons.fiber_manual_record : Icons.radio_button_checked,
                                  size: 12,
                                  color: callState == CallState.inCall ? LinLinkColors.secondary : Colors.amber,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'PC Audio Bridge',
                                  style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 48), // Balance close button
                        ],
                      ),
                    ),

                    const Spacer(flex: 1),

                    // Caller Avatar with Glowing Waves
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulsing animated ripple rings
                          if (callState == CallState.calling || callState == CallState.ringing || callState == CallState.inCall)
                            AnimatedBuilder(
                              animation: _rippleController,
                              builder: (context, child) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: List.generate(3, (index) {
                                    final progress = (_rippleController.value + (index * 0.33)) % 1.0;
                                    return Container(
                                      width: 140 + (progress * 100),
                                      height: 140 + (progress * 100),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: (callState == CallState.inCall
                                                  ? LinLinkColors.secondary
                                                  : LinLinkColors.primary)
                                              .withValues(alpha: (1.0 - progress) * 0.4),
                                          width: 2,
                                        ),
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),

                          // Main avatar circle
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: callState == CallState.inCall
                                    ? [LinLinkColors.secondary, const Color(0xFF0D9488)]
                                    : [LinLinkColors.primary, const Color(0xFF4338CA)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (callState == CallState.inCall
                                          ? LinLinkColors.secondary
                                          : LinLinkColors.primary)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 25,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.computer,
                              size: 64,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Remote Device Name
                    Text(
                      deviceName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Call State / Duration
                    ValueListenableBuilder<int>(
                      valueListenable: CallService.durationNotifier,
                      builder: (context, duration, _) {
                        String statusText;
                        Color statusColor;

                        switch (callState) {
                          case CallState.calling:
                            statusText = 'Connecting to Linux PC…';
                            statusColor = Colors.amber;
                            break;
                          case CallState.ringing:
                            statusText = 'Incoming Call from Linux PC…';
                            statusColor = LinLinkColors.secondary;
                            break;
                          case CallState.inCall:
                            statusText = 'Connected  •  ${CallService.formatDuration(duration)}';
                            statusColor = LinLinkColors.secondary;
                            break;
                          case CallState.ended:
                            statusText = 'Call Ended';
                            statusColor = LinLinkColors.error;
                            break;
                          case CallState.idle:
                            statusText = 'Ready';
                            statusColor = Colors.white54;
                            break;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        );
                      },
                    ),

                    const Spacer(flex: 1),

                    // Audio Waveform Equalizer
                    if (callState == CallState.inCall) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.mic, color: LinLinkColors.primary, size: 16),
                                  const SizedBox(width: 6),
                                  const Text('PC Mic (Speaking)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  const SizedBox(width: 20),
                                  const Icon(Icons.volume_up, color: LinLinkColors.secondary, size: 16),
                                  const SizedBox(width: 6),
                                  const Text('PC Speaker (Hearing)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 48,
                                child: ValueListenableBuilder<double>(
                                  valueListenable: CallService.localMicLevelNotifier,
                                  builder: (context, micLevel, _) {
                                    return ValueListenableBuilder<double>(
                                      valueListenable: CallService.remoteSpeakerLevelNotifier,
                                      builder: (context, speakerLevel, _) {
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: List.generate(20, (i) {
                                            final isMicSide = i < 10;
                                            final energy = isMicSide ? micLevel : speakerLevel;
                                            final heightFactor = math.max(
                                              0.15,
                                              energy * (0.4 + 0.6 * math.sin((i + 1) * 0.7)),
                                            );
                                            final barHeight = (48 * heightFactor).clamp(6.0, 48.0);

                                            return AnimatedContainer(
                                              duration: const Duration(milliseconds: 100),
                                              width: 6,
                                              height: barHeight,
                                              decoration: BoxDecoration(
                                                color: isMicSide ? LinLinkColors.primary : LinLinkColors.secondary,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            );
                                          }),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Spacer(flex: 1),

                    // Call Action Buttons
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40.0),
                      child: callState == CallState.ringing
                          ? _buildRingingControls(context)
                          : _buildInCallControls(context, callState),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRingingControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Decline Call
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                CallService.hangup();
                Navigator.of(context).pop();
              },
              customBorder: const CircleBorder(),
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: LinLinkColors.error,
                  boxShadow: [
                    BoxShadow(color: Color(0x66EF4444), blurRadius: 16, spreadRadius: 2),
                  ],
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),

        // Answer Call
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                CallService.answerCall();
              },
              customBorder: const CircleBorder(),
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: LinLinkColors.secondary,
                  boxShadow: [
                    BoxShadow(color: Color(0x6610B981), blurRadius: 16, spreadRadius: 2),
                  ],
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Answer', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildInCallControls(BuildContext context, CallState callState) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mute / Unmute
        ValueListenableBuilder<bool>(
          valueListenable: CallService.muteNotifier,
          builder: (context, isMuted, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => CallService.toggleMute(),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isMuted ? Colors.red.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12),
                      border: Border.all(color: isMuted ? Colors.redAccent : Colors.white24),
                    ),
                    child: Icon(
                      isMuted ? Icons.mic_off : Icons.mic,
                      color: isMuted ? Colors.redAccent : Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isMuted ? 'Muted' : 'Mute',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            );
          },
        ),

        // End Call (Hangup)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                CallService.hangup();
                Navigator.of(context).pop();
              },
              customBorder: const CircleBorder(),
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: LinLinkColors.error,
                  boxShadow: [
                    BoxShadow(color: Color(0x66EF4444), blurRadius: 18, spreadRadius: 3),
                  ],
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 34),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'End Call',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),

        // Speakerphone Toggle
        ValueListenableBuilder<bool>(
          valueListenable: CallService.speakerNotifier,
          builder: (context, isSpeakerOn, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => CallService.toggleSpeaker(),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSpeakerOn ? LinLinkColors.secondary.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12),
                      border: Border.all(color: isSpeakerOn ? LinLinkColors.secondary : Colors.white24),
                    ),
                    child: Icon(
                      isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      color: isSpeakerOn ? LinLinkColors.secondary : Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isSpeakerOn ? 'Speaker' : 'Earpiece',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
