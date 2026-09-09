import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'camera_event.dart';
import 'camera_state.dart';

class CameraBloc extends Bloc<CameraEvent, CameraState> {
  final MobileScannerController scannerController;

  CameraBloc({MobileScannerController? scannerController})
      : scannerController = scannerController ??
            MobileScannerController(
              autoStart: true,
              detectionSpeed: DetectionSpeed.noDuplicates,
              detectionTimeoutMs: 250,
              facing: CameraFacing.back,
              formats: const [],
              torchEnabled: false,
            ),
        super(const CameraState()) {
    on<CameraInitializeRequested>(_onInitializeRequested);
    on<CameraToggleTorchRequested>(_onToggleTorchRequested);
    on<CameraSwitchRequested>(_onSwitchRequested);
    on<CameraBarcodeScanned>(_onBarcodeScanned);
    on<CameraResetScanRequested>(_onResetScanRequested);
    on<CameraStopRequested>(_onStopRequested);
  }

  Future<void> _onInitializeRequested(
    CameraInitializeRequested event,
    Emitter<CameraState> emit,
  ) async {
    emit(state.copyWith(status: CameraStatus.permissionRequesting));

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (status.isGranted || status.isLimited) {
      emit(state.copyWith(
        status: CameraStatus.ready,
        scannedData: null,
        errorMessage: null,
      ));
    } else if (status.isPermanentlyDenied) {
      emit(state.copyWith(
        status: CameraStatus.permissionPermanentlyDenied,
        errorMessage: 'Camera permission is permanently denied. Please enable it in Settings.',
      ));
    } else {
      emit(state.copyWith(
        status: CameraStatus.permissionDenied,
        errorMessage: 'Camera permission denied.',
      ));
    }
  }

  Future<void> _onToggleTorchRequested(
    CameraToggleTorchRequested event,
    Emitter<CameraState> emit,
  ) async {
    try {
      await scannerController.toggleTorch();
      emit(state.copyWith(isTorchOn: !state.isTorchOn));
    } catch (e) {
      // Ignored if torch not available
    }
  }

  Future<void> _onSwitchRequested(
    CameraSwitchRequested event,
    Emitter<CameraState> emit,
  ) async {
    try {
      await scannerController.switchCamera();
    } catch (e) {
      // Ignored
    }
  }

  void _onBarcodeScanned(
    CameraBarcodeScanned event,
    Emitter<CameraState> emit,
  ) {
    if (state.status == CameraStatus.scanned) return;

    if (event.rawValue.isNotEmpty) {
      emit(state.copyWith(
        status: CameraStatus.scanned,
        scannedData: event.rawValue,
      ));
    }
  }

  Future<void> _onResetScanRequested(
    CameraResetScanRequested event,
    Emitter<CameraState> emit,
  ) async {
    emit(state.copyWith(
      status: CameraStatus.ready,
      scannedData: null,
      errorMessage: null,
    ));
    try {
      if (!scannerController.value.isRunning && !scannerController.value.isStarting) {
        await scannerController.start();
      }
    } catch (_) {}
  }

  Future<void> _onStopRequested(
    CameraStopRequested event,
    Emitter<CameraState> emit,
  ) async {
    try {
      await scannerController.stop();
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    try {
      await scannerController.dispose();
    } catch (_) {}
    return super.close();
  }
}
