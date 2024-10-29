import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'camera_kit_plus_controller.dart';

class CameraKitPlusView extends StatefulWidget {
  final void Function(String code)? onBarcodeRead;
  final CameraKitPlusController? controller;

  const CameraKitPlusView({super.key, required this.onBarcodeRead, this.controller});

  @override
  State<CameraKitPlusView> createState() => _CameraKitPlusViewState();
}

class _CameraKitPlusViewState extends State<CameraKitPlusView> {
  static const channel = MethodChannel('camera_kit_plus');
  late CameraKitPlusController controller;

  @override
  void initState() {
    // channel.setMethodCallHandler((call) async {
    //   if (call.method == "onBarcodeScanned") {
    //     widget.onBarcodeRead.call(call.arguments);
    //   }
    // });
    controller = widget.controller ?? CameraKitPlusController();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: const Key('camera-kit-plus-view'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Platform.isAndroid
          ? AndroidView(
              viewType: 'camera-kit-plus-view',
              onPlatformViewCreated: _onPlatformViewCreated,
            )
          : UiKitView(
              viewType: 'camera-kit-plus-view',
              onPlatformViewCreated: _onPlatformViewCreated,
            ),
    );
  }

  void _onPlatformViewCreated(int id) {
    channel.setMethodCallHandler(_methodCallHandler);
  }

  Future<dynamic> _methodCallHandler(MethodCall methodCall) async {
    if (methodCall.method == "onBarcodeRead") {
      String barcode = methodCall.arguments.toString();
      widget.onBarcodeRead?.call(barcode);
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    bool isVisible = !(info.visibleFraction == 0);
    if (isVisible) {
      controller.resumeCamera();
    } else {
      controller.pauseCamera();
    }
  }
}
