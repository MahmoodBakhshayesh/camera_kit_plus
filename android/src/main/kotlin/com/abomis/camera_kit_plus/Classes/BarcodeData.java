package com.abomis.camera_kit_plus.Classes;
import android.graphics.Point;

import com.google.gson.annotations.SerializedName;
import com.google.mlkit.vision.barcode.common.Barcode;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;

public class BarcodeData {
    @SerializedName("value")
    public String value;
    @SerializedName("type")
    public Integer type;

    @SerializedName("cornerPoints")
    public List<CornerPointModel> cornerPoints;


    public BarcodeData(Barcode b) {
        List<CornerPointModel> cornerPoints = new ArrayList<>();
        for (Point point : Objects.requireNonNull(b.getCornerPoints())) {
            cornerPoints.add(new CornerPointModel(point.x, point.y));
        }
        this.value = b.getRawValue();
        this.type = b.getFormat();
        this.cornerPoints =cornerPoints;
    }

    // Manual JSON Serialization

}
