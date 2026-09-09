import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/linlink_theme.dart';
import '../pairing/pairing_service.dart';
import 'clipboard_service.dart';

class ClipboardItem {
  final String text;
  final String source;
  final DateTime timestamp;

  ClipboardItem({
    required this.text,
    required this.source,
    required this.timestamp,
  });
}

class ClipboardView extends StatefulWidget {
  final PairedCompanion? pairedCompanion;
  final VoidCallback onRequestPair;

  const ClipboardView({
    super.key,
    required this.pairedCompanion,
    required this.onRequestPair,
  });

  @override
  State<ClipboardView> createState() => _ClipboardViewState();
}

class _ClipboardViewState extends State<ClipboardView> {
  String _phoneClipboard = 'Checking clipboard...';
  String _linuxClipboard = '';
  bool _isSending = false;
  bool _isFetching = false;
  final List<ClipboardItem> _history = [];

  @override
  void initState() {
    super.initState();
    _refreshPhoneClipboard();

    // Hook into global clipboard sync
    final previousOnSynced = ClipboardService.onClipboardSynced;
    ClipboardService.onClipboardSynced = (text) {
      if (previousOnSynced != null) previousOnSynced(text);
      if (mounted) {
        setState(() {
          _linuxClipboard = text;
          _addToHistory(text, widget.pairedCompanion?.deviceName ?? 'Linux');
        });
      }
    };
  }

  Future<void> _refreshPhoneClipboard() async {
    final text = await ClipboardService.readDeviceClipboard();
    if (mounted) {
      setState(() {
        _phoneClipboard = text ?? '(Clipboard is empty)';
      });
    }
  }

  void _addToHistory(String text, String source) {
    if (text.trim().isEmpty) return;
    if (_history.any((item) => item.text == text)) {
      _history.removeWhere((item) => item.text == text);
    }
    _history.insert(
      0,
      ClipboardItem(text: text, source: source, timestamp: DateTime.now()),
    );
    if (_history.length > 20) {
      _history.removeLast();
    }
  }

  Future<void> _sendToLinux() async {
    if (widget.pairedCompanion == null) {
      widget.onRequestPair();
      return;
    }

    setState(() => _isSending = true);
    final text = await ClipboardService.readDeviceClipboard();
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        setState(() => _isSending = false);
        _showToast('Device clipboard is empty');
      }
      return;
    }

    final success = await ClipboardService.sendToCompanion(
      companion: widget.pairedCompanion!,
      text: text,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _phoneClipboard = text;
        if (success) {
          _addToHistory(text, 'This Device');
        }
      });
      _showToast(success ? 'Copied to Linux Companion!' : 'Failed to send');
    }
  }

  Future<void> _fetchFromLinux() async {
    if (widget.pairedCompanion == null) {
      widget.onRequestPair();
      return;
    }

    setState(() => _isFetching = true);
    final text = await ClipboardService.fetchFromCompanion(
      widget.pairedCompanion!,
    );

    if (mounted) {
      setState(() => _isFetching = false);
      if (text != null && text.isNotEmpty) {
        await ClipboardService.writeDeviceClipboard(text);
        setState(() {
          _linuxClipboard = text;
          _phoneClipboard = text;
          _addToHistory(text, widget.pairedCompanion!.deviceName);
        });
        _showToast('Copied from Linux to Phone clipboard!');
      } else {
        _showToast('Linux clipboard is empty');
      }
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isLinked = widget.pairedCompanion != null;
    final isAutoSync = ClipboardService.isAutoSyncRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Sync Status Card
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
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isAutoSync ? Icons.sync : Icons.sync_disabled,
                    color: isAutoSync
                        ? LinLinkColors.secondary
                        : LinLinkColors.onSurfaceVariant,
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
                            isAutoSync
                                ? 'Auto-Sync Active'
                                : 'Auto-Sync Paused',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: LinLinkColors.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: isAutoSync
                                  ? LinLinkColors.secondaryContainer
                                  : LinLinkColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isAutoSync ? 'LIVE' : 'OFF',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isAutoSync
                                    ? LinLinkColors.onSecondaryContainer
                                    : LinLinkColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLinked
                            ? 'Bi-directional mirror with ${widget.pairedCompanion!.deviceName}'
                            : 'Pair with Linux to enable continuous clipboard mirroring',
                        style: const TextStyle(
                          fontSize: 12,
                          color: LinLinkColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isAutoSync,
                  onChanged: (val) {
                    if (!isLinked) {
                      widget.onRequestPair();
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

          const SizedBox(height: 14),

          // Phone Clipboard Card
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
                        Icon(
                          Icons.smartphone,
                          size: 16,
                          color: LinLinkColors.primary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Phone Clipboard',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: LinLinkColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        size: 18,
                        color: LinLinkColors.onSurfaceVariant,
                      ),
                      tooltip: 'Refresh phone clipboard',
                      onPressed: _refreshPhoneClipboard,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _phoneClipboard,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: LinLinkColors.onSurface,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.copy,
                          size: 16,
                          color: LinLinkColors.onSurfaceVariant,
                        ),
                        tooltip: 'Copy text',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _phoneClipboard),
                          );
                          _showToast('Copied to device clipboard');
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: _isSending ? null : _sendToLinux,
                    icon: _isSending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_upward, size: 16),
                    label: const Text('Send to Linux'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Linux Clipboard Card
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
                        Icon(
                          Icons.terminal,
                          size: 16,
                          color: LinLinkColors.secondary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Linux Companion Clipboard',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: LinLinkColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: LinLinkColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'wl-clipboard / xclip',
                          style: TextStyle(
                            fontSize: 10,
                            color: LinLinkColors.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: LinLinkColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: LinLinkColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _linuxClipboard.isEmpty
                              ? '(No content fetched yet)'
                              : _linuxClipboard,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: _linuxClipboard.isEmpty
                                ? LinLinkColors.outline
                                : LinLinkColors.onSurface,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_linuxClipboard.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            size: 16,
                            color: LinLinkColors.onSurfaceVariant,
                          ),
                          tooltip: 'Copy text',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _linuxClipboard),
                            );
                            _showToast('Copied to device clipboard');
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: _isFetching ? null : _fetchFromLinux,
                    icon: _isFetching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_downward, size: 16),
                    label: const Text('Fetch from Linux'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // Clipboard History Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Clipboard History',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: LinLinkColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: LinLinkColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_history.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: LinLinkColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (_history.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _history.clear());
                  },
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 12,
                      color: LinLinkColors.outline,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_history.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: LinLinkColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: LinLinkColors.outlineVariant),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.content_paste,
                    size: 32,
                    color: LinLinkColors.outline,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No clipboard history yet',
                    style: TextStyle(
                      color: LinLinkColors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Synced text will appear here automatically',
                    style: TextStyle(
                      color: LinLinkColors.outline,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            )
          else
            Material(
              color: LinLinkColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _history.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _history[index];
                  final isFromLinux = item.source != 'This Device';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: LinLinkColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        isFromLinux ? Icons.terminal : Icons.smartphone,
                        size: 16,
                        color: isFromLinux
                            ? LinLinkColors.secondary
                            : LinLinkColors.primary,
                      ),
                    ),
                    title: Text(
                      item.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: LinLinkColors.onSurface,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          _formatTimeAgo(item.timestamp),
                          style: const TextStyle(
                            fontSize: 11,
                            color: LinLinkColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '•',
                          style: TextStyle(color: LinLinkColors.outline),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.source,
                          style: TextStyle(
                            fontSize: 11,
                            color: isFromLinux
                                ? LinLinkColors.secondary
                                : LinLinkColors.primary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.copy,
                        size: 16,
                        color: LinLinkColors.onSurfaceVariant,
                      ),
                      tooltip: 'Copy',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: item.text));
                        _showToast('Copied to clipboard');
                      },
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
