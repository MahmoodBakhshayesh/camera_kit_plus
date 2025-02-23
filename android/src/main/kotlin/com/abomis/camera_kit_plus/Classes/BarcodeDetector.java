package com.abomis.camera_kit_plus.Classes;

import android.media.Image;
import android.media.ImageReader;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.common.InputImage;
import com.google.gson.Gson;

import java.util.List;

import io.flutter.plugin.common.MethodChannel;

public class BarcodeDetector {

    private static ImageReader imageReader;
    private static boolean isBusy = false;

    public static void setImageReader(ImageReader imageReader) {
        BarcodeDetector.imageReader = imageReader;
    }

    @RequiresApi(api = Build.VERSION_CODES.KITKAT)
    public static void detectImage(final ImageReader imageReader, BarcodeScanner scanner, final Image inputImage, MethodChannel methodChannel, int firebaseOrientation) {

        if (!isBusy) {
            if (imageReader == BarcodeDetector.imageReader && inputImage != null && scanner != null) {
                isBusy = true;
                scanner.process(InputImage.fromMediaImage(inputImage, firebaseOrientation)).addOnSuccessListener(barcodes -> {
                    if (imageReader == BarcodeDetector.imageReader) {
                        if (barcodes.size() > 0) {
                            for (Barcode barcode : barcodes

                            ) {
//                                    System.out.println("barcode read failed: " + barcode.getRawValue());
                                methodChannel.invokeMethod("onBarcodeScanned",barcode.getRawValue());
                                methodChannel.invokeMethod("onBarcodeDataScanned", new Gson().toJson(new BarcodeData(barcode)));
//                                            flutterMethodListener.onBarcodeRead(barcode.getRawValue());

                            }
                        }
                    }
                }).addOnFailureListener(e -> {
                    System.out.println("barcode read failed: " + e.getMessage());
                    inputImage.close();
                }).addOnCompleteListener(task -> {
                    isBusy = false;
                    inputImage.close();
                });
            } else {
                inputImage.close();
            }
        } else {
            inputImage.close();
        }

    }


}
