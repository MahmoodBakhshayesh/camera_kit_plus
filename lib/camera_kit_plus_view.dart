import 'dart:convert';
import 'dart:io';
import 'package:camera_kit_plus/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'camera_kit_plus_controller.dart';

class CameraKitPlusView extends StatefulWidget {
  final void Function(String code)? onBarcodeRead;
  final void Function(BarcodeData data)? onBarcodeDataRead;
  final CameraKitPlusController? controller;

  const CameraKitPlusView({super.key, required this.onBarcodeRead,  this.onBarcodeDataRead, this.controller});

  @override
  State<CameraKitPlusView> createState() => _CameraKitPlusViewState();
}

class _CameraKitPlusViewState extends State<CameraKitPlusView> {
  static const channel = MethodChannel('camera_kit_plus');
  late CameraKitPlusController controller;

  @override
  void initState() {
    // channel.setMethodCallHandler(_methodCallHandler);
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
    try {
      if (methodCall.method == "onBarcodeScanned") {
        String barcode = methodCall.arguments.toString();
        widget.onBarcodeRead?.call(barcode);
      }
      if (methodCall.method == "onBarcodeDataScanned") {
        String barcodeJson = methodCall.arguments.toString();
        // print(barcodeJson);
        final dataJson = jsonDecode(barcodeJson);
        BarcodeData data = BarcodeData.fromJson(dataJson);
        // print(data.toJson());
        widget.onBarcodeDataRead?.call(data);
      }
    }catch (e){
      if(e is Error){
        print(e.stackTrace);
      }else{
        print(e);
      }
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


class BarcodeData {
  final List<CornerPoint> cornerPoints;
  final int type;
  final String value;

  BarcodeData({
    required this.cornerPoints,
    required this.type,
    required this.value,
  });

  BarcodeData copyWith({
    List<CornerPoint>? cornerPoints,
    int? type,
    String? value,
  }) =>
      BarcodeData(
        cornerPoints: cornerPoints ?? this.cornerPoints,
        type: type ?? this.type,
        value: value ?? this.value,
      );

  factory BarcodeData.fromJson(Map<String, dynamic> json) => BarcodeData(
    cornerPoints: List<CornerPoint>.from(json["cornerPoints"].map((x) => CornerPoint.fromJson(x))),
    type: json["type"],
    value: json["value"],
  );

  Map<String, dynamic> toJson() => {
    "cornerPoints": List<dynamic>.from(cornerPoints.map((x) => x.toJson())),
    "type": type,
    "value": value,
  };

  BarcodeType get getType => BarcodeType.fromCode(type);
}

class CornerPoint {
  final double x;
  final double y;

  CornerPoint({
    required this.x,
    required this.y,
  });

  CornerPoint copyWith({
    double? x,
    double? y,
  }) =>
      CornerPoint(
        x: x ?? this.x,
        y: y ?? this.y,
      );

  factory CornerPoint.fromJson(Map<String, dynamic> json) => CornerPoint(
    x: json["x"],
    y: json["y"],
  );

  Map<String, dynamic> toJson() => {
    "x": x,
    "y": y,
  };
}