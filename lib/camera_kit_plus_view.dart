
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraKitPlusView extends StatefulWidget {
  final void Function(String code) onBarcodeRead;
  const CameraKitPlusView({super.key,required this.onBarcodeRead});

  @override
  State<CameraKitPlusView> createState() => _CameraKitPlusViewState();
}

class _CameraKitPlusViewState extends State<CameraKitPlusView> {
  static const channel = MethodChannel('camera_kit_plus');

  @override
  void initState() {
    channel.setMethodCallHandler((call) async {
      if (call.method == "onBarcodeScanned") {
        widget.onBarcodeRead.call(call.arguments);
        // print("Barcode: ${call.arguments}");
      }
    });

    super.initState();
  }
  @override
  Widget build(BuildContext context) {

    return Container(
      color: Colors.orange,
      height: double.infinity,
      width: double.infinity,
      child: Platform.isAndroid
          ? const AndroidView(
              viewType: 'camera-kit-plus-view',
            )
          : const UiKitView(
              viewType: 'camera-kit-plus-view',
            ),
    );
  }
}