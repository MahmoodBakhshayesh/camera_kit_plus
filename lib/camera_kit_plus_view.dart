import 'dart:convert';
import 'dart:io';

// import 'package:app_settings/app_settings.dart';
import 'package:camera_kit_plus/enums.dart';

// import 'package:camerakit/CameraKitView.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'camera_kit_plus_controller.dart';

class CameraKitPlusView extends StatefulWidget {
  final void Function(String code)? onBarcodeRead;
  final void Function(BarcodeData data)? onBarcodeDataRead;
  final bool showFrame;
  final bool showZoomSlider;
  final List<BarcodeType>? types;
  final CameraKitPlusController? controller;
  final bool useOld;

  const CameraKitPlusView({super.key, required this.onBarcodeRead, this.onBarcodeDataRead, this.controller, this.types, this.useOld = false, this.showFrame = false, this.showZoomSlider = false});

  @override
  State<CameraKitPlusView> createState() => _CameraKitPlusViewState();
}

class _CameraKitPlusViewState extends State<CameraKitPlusView> with WidgetsBindingObserver {
  static const channel = MethodChannel('camera_kit_plus');
  late CameraKitPlusController controller;
  bool isVisible = false;
  double zoom = 1;

  @override
  void initState() {
    // channel.setMethodCallHandler(_methodCallHandler);
    controller = widget.controller ?? CameraKitPlusController();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  Future<PermissionStatus> checkCameraPermission() async {
    var status = await Permission.camera.status;
    return status;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // print("Flutter Life Cycle: resumed");
        if (isVisible) {
          controller.resumeCamera();
        }
        break;
      case AppLifecycleState.inactive:
        // print("Flutter Life Cycle: inactive");
        if (Platform.isIOS) {
          controller.pauseCamera();
        }
        break;
      case AppLifecycleState.paused:
        // print("Flutter Life Cycle: paused");
        controller.pauseCamera();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.pauseCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width * 0.9;

    // if(widget.useOld){
    //   return CameraKitView(
    //     onBarcodeRead: widget.onBarcodeRead,
    //   );
    // }
    return Stack(
      children: [
        VisibilityDetector(
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
        ),
        !widget.showFrame
            ? SizedBox()
            : IgnorePointer(child: Align(alignment: Alignment.center, child: SizedBox(width: width, height: width * 0.7, child: Image.asset("assets/images/scanner_frame.png", package: 'camera_kit_plus', fit: BoxFit.fill)))),
        !widget.showZoomSlider
            ? SizedBox()
            : IgnorePointer(
                ignoring: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: width,
                    height: 40,
                    margin: EdgeInsets.only(bottom: 24),
                    child: Slider(
                      min: 1,
                      max: 8,
                      value: zoom,
                      onChanged: (a) {
                        zoom = a;
                        setState(() {});
                        controller.setZoom(a);
                      },
                    ),
                  ),
                ),
              ),
      ],
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
        if (widget.types != null && !widget.types!.map((a) => a.code).contains(data.type)) {
          return;
        }
        // print(data.toJson());
        widget.onBarcodeRead?.call(data.value);
        widget.onBarcodeDataRead?.call(data);
      } else if (methodCall.method == "onZoomChanged") {
        try {
          double? z = methodCall.arguments;
          if (z != null) {
            zoom = z;
            setState(() {});
          }
        } catch (e) {
        }
        // log("onMacroChanged");
        // String jsonStr = methodCall.arguments.toString();
        // log(jsonStr);
      }
    } catch (e) {
      if (e is Error) {
        print(e.stackTrace);
      } else {
        print(e);
      }
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    bool visible = !(info.visibleFraction == 0);
    if (visible != isVisible) {
      isVisible = visible;
      if (isVisible) {
        controller.resumeCamera();
      } else {
        controller.pauseCamera();
      }
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
