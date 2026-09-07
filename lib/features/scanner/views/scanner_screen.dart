import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../pairing/pairing_service.dart';
import '../bloc/camera_bloc.dart';
import '../bloc/camera_event.dart';
import '../bloc/camera_state.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CameraBloc()..add(const CameraInitializeRequested()),
      child: const _ScannerView(),
    );
  }
}

class _ScannerView extends StatelessWidget {
  const _ScannerView();

  @override
  Widget build(BuildContext context) {
    final cameraBloc = context.read<CameraBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Companion QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Enter Manually',
            onPressed: () => _showManualEntryDialog(context),
          ),
          BlocBuilder<CameraBloc, CameraState>(
            buildWhen: (prev, curr) => prev.isTorchOn != curr.isTorchOn,
            builder: (context, state) {
              return IconButton(
                icon: Icon(
                  state.isTorchOn ? Icons.flash_on : Icons.flash_off,
                ),
                onPressed: () => cameraBloc.add(const CameraToggleTorchRequested()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => cameraBloc.add(const CameraSwitchRequested()),
          ),
        ],
      ),
      body: BlocConsumer<CameraBloc, CameraState>(
        listener: (context, state) {
          if (state.status == CameraStatus.scanned && state.scannedData != null) {
            _handleScannedData(context, state.scannedData!);
          }
        },
        builder: (context, state) {
          if (state.status == CameraStatus.permissionRequesting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == CameraStatus.permissionDenied) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera permission is required to scan the pairing QR code.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => cameraBloc.add(const CameraInitializeRequested()),
                      child: const Text('Grant Permission'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Or Enter Code Manually'),
                      onPressed: () => _showManualEntryDialog(context),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state.status == CameraStatus.permissionPermanentlyDenied) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera permission permanently denied.\nPlease enable it in App Settings or enter manually.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => openAppSettings(),
                      child: const Text('Open Settings'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Enter Code Manually'),
                      onPressed: () => _showManualEntryDialog(context),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state.status == CameraStatus.error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                    const SizedBox(height: 16),
                    Text(
                      state.errorMessage ?? 'An error occurred with camera',
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => cameraBloc.add(const CameraInitializeRequested()),
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Enter Code Manually'),
                      onPressed: () => _showManualEntryDialog(context),
                    ),
                  ],
                ),
              ),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: cameraBloc.scannerController,
                onDetect: (capture) {
                  final barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    final raw = barcode.rawValue ?? barcode.displayValue;
                    if (raw != null && raw.trim().isNotEmpty) {
                      cameraBloc.add(CameraBarcodeScanned(raw.trim()));
                      break;
                    }
                  }
                },
              ),
              _buildScanOverlay(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScanOverlay(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.cyanAccent, width: 2.5),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Point camera at the QR code on your Linux terminal',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          style: TextButton.styleFrom(
            backgroundColor: Colors.black54,
            foregroundColor: Colors.cyanAccent,
          ),
          icon: const Icon(Icons.keyboard, size: 18),
          label: const Text('Or Enter Pairing Code Manually'),
          onPressed: () => _showManualEntryDialog(context),
        ),
      ],
    );
  }

  void _handleScannedData(BuildContext context, String payload) {
    final cameraBloc = context.read<CameraBloc>();
    final target = PairingTarget.tryParse(payload);

    if (target == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Unrecognized QR'),
            ],
          ),
          content: Text(
            'The scanned text is not a valid LinLink pairing code:\n"$payload"\n\n'
            'Please scan the QR code generated by `linlink pair` in your Linux terminal, '
            'or enter the details manually.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _showManualEntryDialog(context);
              },
              child: const Text('Enter Manually'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                cameraBloc.add(const CameraResetScanRequested());
              },
              child: const Text('Scan Again'),
            ),
          ],
        ),
      );
      return;
    }

    // Valid target found – show pairing confirmation dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _PairingConfirmDialog(
        target: target,
        onSuccess: (companion) {
          Navigator.of(dialogCtx).pop();
          Navigator.of(context).pop(companion);
        },
        onCancel: () {
          Navigator.of(dialogCtx).pop();
          cameraBloc.add(const CameraResetScanRequested());
        },
      ),
    );
  }

  void _showManualEntryDialog(BuildContext context) {
    final hostController = TextEditingController(text: '10.253.176.30');
    final portController = TextEditingController(text: '7878');
    final tokenController = TextEditingController();
    final nameController = TextEditingController(text: 'Android Phone');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Colors.cyanAccent),
            SizedBox(width: 10),
            Text('Manual Pairing'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the details printed in your terminal under the QR code:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hostController,
                decoration: const InputDecoration(
                  labelText: 'Companion IP / Host',
                  hintText: 'e.g. 192.168.1.50',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '7878',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tokenController,
                decoration: const InputDecoration(
                  labelText: 'Token or Full linlink:// URI',
                  hintText: 'e.g. 4a7bc12d',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'This Device Name',
                  hintText: 'e.g. Pixel 8',
                  border: OutlineInputBorder(),
                  isDense: true,
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
            onPressed: () {
              final rawToken = tokenController.text.trim();
              final target = PairingTarget.tryParse(rawToken);

              final effectiveTarget = target ??
                  PairingTarget(
                    host: hostController.text.trim(),
                    port: int.tryParse(portController.text.trim()) ?? 7878,
                    token: rawToken,
                  );

              if (effectiveTarget.token.isEmpty || effectiveTarget.host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter host and token.')),
                );
                return;
              }

              Navigator.of(dialogCtx).pop();

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (confirmCtx) => _PairingConfirmDialog(
                  target: effectiveTarget,
                  onSuccess: (companion) {
                    Navigator.of(confirmCtx).pop();
                    Navigator.of(context).pop(companion);
                  },
                  onCancel: () => Navigator.of(confirmCtx).pop(),
                ),
              );
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }
}

class _PairingConfirmDialog extends StatefulWidget {
  final PairingTarget target;
  final ValueChanged<PairedCompanion> onSuccess;
  final VoidCallback onCancel;

  const _PairingConfirmDialog({
    required this.target,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<_PairingConfirmDialog> createState() => _PairingConfirmDialogState();
}

class _PairingConfirmDialogState extends State<_PairingConfirmDialog> {
  late final TextEditingController _nameController;
  bool _isLinking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    String defaultName = 'Android Phone';
    if (Platform.isLinux) {
      defaultName = 'Linux Client';
    } else if (Platform.isMacOS) {
      defaultName = 'Mac Client';
    } else if (Platform.isWindows) {
      defaultName = 'Windows Client';
    } else if (Platform.isIOS) {
      defaultName = 'iPhone';
    }
    _nameController = TextEditingController(text: defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _startPairing() async {
    final name = _nameController.text.trim().isEmpty
        ? 'Android Device'
        : _nameController.text.trim();

    setState(() {
      _isLinking = true;
      _errorMessage = null;
    });

    try {
      final companion = await PairingService.pair(
        target: widget.target,
        deviceName: name,
      );
      if (mounted) {
        widget.onSuccess(companion);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLinking = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.phonelink_setup, color: Colors.cyanAccent),
          SizedBox(width: 10),
          Text('Link Device'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Linux Companion detected:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.computer, size: 28, color: Colors.cyanAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.target.host}:${widget.target.port}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'Token: ${widget.target.token}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Device Name (shown on Linux companion):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              enabled: !_isLinking,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'e.g. Pixel 8',
              ),
            ),
            if (_isLinking) ...[
              const SizedBox(height: 20),
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text(
                      'Linking with Linux Companion…',
                      style: TextStyle(fontSize: 13, color: Colors.cyanAccent),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withAlpha(100)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isLinking) ...[
          TextButton(
            onPressed: widget.onCancel,
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Link Now'),
            onPressed: _startPairing,
          ),
        ],
      ],
    );
  }
}
