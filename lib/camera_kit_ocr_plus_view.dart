import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'camera_kit_plus_controller.dart';

class CameraKitOcrPlusView extends StatefulWidget {
  final void Function(OcrData data)? onTextRead;
  final void Function(double zoom)? onZoomChanged;
  final bool showFrame;
  final bool showZoomSlider;
  final bool showTextRectangles;
  final CameraKitPlusController? controller;

  const CameraKitOcrPlusView({super.key, required this.onTextRead, this.controller, this.onZoomChanged, this.showFrame = false, this.showZoomSlider = false, this.showTextRectangles = false});

  @override
  State<CameraKitOcrPlusView> createState() => _CameraKitOcrPlusViewState();
}

class _CameraKitOcrPlusViewState extends State<CameraKitOcrPlusView> with WidgetsBindingObserver {
  static const channel = MethodChannel('camera_kit_plus');
  late CameraKitPlusController controller;
  bool isVisible = false;
  double zoom = 1;
  @override
  void initState() {
    // channel.setMethodCallHandler(_methodCallHandler);
    controller = widget.controller ?? CameraKitPlusController();
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width * 0.9;
    final Map<String, dynamic> creationParams = <String, dynamic>{
      "showTextRectangles": widget.showTextRectangles,
    };

    return Stack(
      children: [
        VisibilityDetector(
          key: const Key('camera-kit-ocr-plus-view'),
          onVisibilityChanged: _onVisibilityChanged,
          child: Platform.isAndroid
              ? AndroidView(
                  viewType: 'camera-kit-ocr-plus-view',
                  onPlatformViewCreated: _onPlatformViewCreated,
                  creationParams: creationParams,
                  creationParamsCodec: const StandardMessageCodec(),
                )
              : UiKitView(
                  viewType: 'camera-kit-ocr-plus-view',
                  onPlatformViewCreated: _onPlatformViewCreated,
                  creationParams: creationParams,
                  creationParamsCodec: const StandardMessageCodec(),
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
                  log("zoom $a");
                  controller.setZoom(a);
                },
              ),
            ),
          ),
        ),
      ],
    );
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

  void _onPlatformViewCreated(int id) {
    channel.setMethodCallHandler(_methodCallHandler);
  }

  Future<dynamic> _methodCallHandler(MethodCall methodCall) async {
    if (methodCall.method == "onTextRead") {
      String jsonStr = methodCall.arguments.toString();
      OcrData data = OcrData.fromJson(jsonDecode(jsonStr));
      widget.onTextRead?.call(data);
    } else if (methodCall.method == "onMacroChanged") {
      // log("onMacroChanged");
      // String jsonStr = methodCall.arguments.toString();
      // log(jsonStr);
    } else if (methodCall.method == "onZoomChanged") {
      try {
        double? z = methodCall.arguments;
        log("on Zoom change d ${z}");
        if (z != null) {
          widget.onZoomChanged?.call(z);

          zoom = z;
          setState((){});
        }
      } catch (e) {
        log("$e");
      }
      // log("onMacroChanged");
      // String jsonStr = methodCall.arguments.toString();
      // log(jsonStr);
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

class OcrData {
  OcrData({
    required this.text,
    this.path = "",
    this.orientation = 0,
    required this.lines,
  });

  String text;
  String path;
  int orientation;
  List<OcrLine> lines;

  factory OcrData.fromJson(Map<String, dynamic> json) => OcrData(
        text: json["text"],
        path: json["path"] ?? "",
        orientation: json["orientation"] ?? 0,
        lines: List<OcrLine>.from((json["lines"] ?? []).map((x) => OcrLine.fromJson(x))),
      );

  Map<String, dynamic> toJson() => {
        "text": text,
        "path": path,
        "orientation": orientation,
        "lines": List<dynamic>.from(lines.map((x) => x.toJson())),
      };
}

class OcrLine {
  OcrLine({
    required this.text,
    required this.cornerPoints,
  });

  String text;
  List<OcrPoint> cornerPoints;

  factory OcrLine.fromJson(Map<String, dynamic> json) => OcrLine(
        text: json["text"] ?? json["a"] ?? "",
        cornerPoints: List<OcrPoint>.from((json["cornerPoints"] ?? json["b"] ?? []).map((x) => OcrPoint.fromJson(x))),
      );

  Map<String, dynamic> toJson() => {
        "text": text,
        "cornerPoints": List<dynamic>.from(cornerPoints.map((x) => x.toJson())),
      };
}

class OcrPoint {
  OcrPoint({
    required this.x,
    required this.y,
  });

  double x;
  double y;

  factory OcrPoint.fromJson(Map<String, dynamic> json) => OcrPoint(
        x: (json["x"] ?? json["a"]).toDouble(),
        y: (json["y"] ?? json["b"]).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "x": x,
        "y": y,
      };
}
