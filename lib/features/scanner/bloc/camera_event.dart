import 'package:equatable/equatable.dart';

abstract class CameraEvent extends Equatable {
  const CameraEvent();

  @override
  List<Object?> get props => [];
}

class CameraInitializeRequested extends CameraEvent {
  const CameraInitializeRequested();
}

class CameraToggleTorchRequested extends CameraEvent {
  const CameraToggleTorchRequested();
}

class CameraSwitchRequested extends CameraEvent {
  const CameraSwitchRequested();
}

class CameraBarcodeScanned extends CameraEvent {
  final String rawValue;

  const CameraBarcodeScanned(this.rawValue);

  @override
  List<Object?> get props => [rawValue];
}

class CameraResetScanRequested extends CameraEvent {
  const CameraResetScanRequested();
}

class CameraStopRequested extends CameraEvent {
  const CameraStopRequested();
}
