import 'package:equatable/equatable.dart';

enum CameraStatus {
  initial,
  permissionRequesting,
  permissionDenied,
  permissionPermanentlyDenied,
  ready,
  scanned,
  error,
}

class CameraState extends Equatable {
  final CameraStatus status;
  final bool isTorchOn;
  final String? scannedData;
  final String? errorMessage;

  const CameraState({
    this.status = CameraStatus.initial,
    this.isTorchOn = false,
    this.scannedData,
    this.errorMessage,
  });

  CameraState copyWith({
    CameraStatus? status,
    bool? isTorchOn,
    String? scannedData,
    String? errorMessage,
  }) {
    return CameraState(
      status: status ?? this.status,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      scannedData: scannedData ?? this.scannedData,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, isTorchOn, scannedData, errorMessage];
}
