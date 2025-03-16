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
  final List<BarcodeType>? types;
  final CameraKitPlusController? controller;
  final bool useOld;

  const CameraKitPlusView({super.key, required this.onBarcodeRead, this.onBarcodeDataRead, this.controller, this.types, this.useOld = false});

  @override
  State<CameraKitPlusView> createState() => _CameraKitPlusViewState();
}

class _CameraKitPlusViewState extends State<CameraKitPlusView>  with WidgetsBindingObserver {
  static const channel = MethodChannel('camera_kit_plus');
  late CameraKitPlusController controller;
  late VisibilityDetector visibilityDetector;
  bool paused  = false;
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
        controller.resumeCamera();
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
    // if(widget.useOld){
    //   return CameraKitView(
    //     onBarcodeRead: widget.onBarcodeRead,
    //   );
    // }
    return VisibilityDetector(
      key: const Key('camera-kit-plus-view'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Platform.isAndroid
          ? paused?SizedBox():AndroidView(
        viewType: 'camera-kit-plus-view',
        onPlatformViewCreated: _onPlatformViewCreated,
      )
          :  paused?SizedBox():UiKitView(
        viewType: 'camera-kit-plus-view',
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
    // return FutureBuilder(
    //   future: checkCameraPermission(),
    //   builder: (BuildContext context, AsyncSnapshot<PermissionStatus> snapshot) {
    //     print(snapshot.data?.isGranted);
    //     if (!snapshot.hasData) {
    //       return VisibilityDetector(
    //         key: const Key('camera-kit-plus-view'),
    //         onVisibilityChanged: _onVisibilityChanged,
    //         child: Platform.isAndroid
    //             ? AndroidView(
    //                 viewType: 'camera-kit-plus-view',
    //                 onPlatformViewCreated: _onPlatformViewCreated,
    //               )
    //             : UiKitView(
    //                 viewType: 'camera-kit-plus-view',
    //                 onPlatformViewCreated: _onPlatformViewCreated,
    //               ),
    //       );
    //     }
    //     if (snapshot.data != null && snapshot.data!.isGranted) {
    //
    //       return VisibilityDetector(
    //         key: const Key('camera-kit-plus-view'),
    //         onVisibilityChanged: _onVisibilityChanged,
    //         child: Platform.isAndroid
    //             ? AndroidView(
    //                 viewType: 'camera-kit-plus-view',
    //                 onPlatformViewCreated: _onPlatformViewCreated,
    //               )
    //             : UiKitView(
    //                 viewType: 'camera-kit-plus-view',
    //                 onPlatformViewCreated: _onPlatformViewCreated,
    //               ),
    //       );
    //     }
    //     return VisibilityDetector(
    //       key: const Key('camera-kit-plus-view'),
    //       onVisibilityChanged: _onVisibilityChanged,
    //       child: Column(
    //         mainAxisAlignment: MainAxisAlignment.center,
    //         children: [
    //           const Text(
    //             "You Need Camera Permission!",
    //             style: TextStyle(color: Colors.white),
    //           ),
    //           const SizedBox(height: 8),
    //           TextButton(
    //               onPressed: () async {
    //                 // final pemission = await controller.getCameraPermission();
    //                 // print("getCameraPermission ${pemission}");
    //                 //
    //                 // setState(() {});
    //                 // AppSettings.openAppSettings(type: AppSettingsType.),
    //                 // print("pemission ${pemission}");
    //                 // setState((){});
    //
    //                 final status =  await Permission.camera.onDeniedCallback(() {
    //                    setState(() {});
    //                  }).onGrantedCallback(() {
    //                    setState(() {});
    //                  }).onPermanentlyDeniedCallback(() {
    //                    setState(() {});
    //                  }).onRestrictedCallback(() {
    //                    setState(() {});
    //                  }).onLimitedCallback(() {
    //                    setState(() {});
    //                  }).onProvisionalCallback(() {
    //                    setState(() {});
    //                  }).request();
    //                  if(status != PermissionStatus.granted){
    //                    openAppSettings();
    //                  }
    //               },
    //               child: const Text("Get Permission"))
    //         ],
    //       ),
    //     );
    //   },
    // );
  }

  void _onPlatformViewCreated(int id) {
    channel.setMethodCallHandler(_methodCallHandler);
  }

  Future<dynamic> _methodCallHandler(MethodCall methodCall) async {
    try {
      if (methodCall.method == "onBarcodeScanned") {
        // String barcode = methodCall.arguments.toString();
        // widget.onBarcodeRead?.call(barcode);
      }
      if (methodCall.method == "onBarcodeDataScanned") {
        String barcodeJson = methodCall.arguments.toString();
        // print(barcodeJson);
        final dataJson = jsonDecode(barcodeJson);
        BarcodeData data = BarcodeData.fromJson(dataJson);
        if(widget.types!=null && !widget.types!.map((a)=>a.code).contains(data.type)){
          return;
        }
        // print(data.toJson());
        widget.onBarcodeRead?.call(data.value);
        widget.onBarcodeDataRead?.call(data);
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
    bool isVisible = !(info.visibleFraction == 0);
    if (isVisible) {
      // print("object visible");
      paused = false;
      if(mounted) {
        setState(() {});
      }
      // controller.resumeCamera();
    } else {
      paused = true;
      if(mounted) {
        setState(() {});
      }
      // print("object not visible");
      // controller.pauseCamera();
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
