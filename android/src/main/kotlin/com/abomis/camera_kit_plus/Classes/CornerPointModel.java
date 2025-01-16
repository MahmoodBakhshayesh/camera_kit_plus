package com.abomis.camera_kit_plus.Classes;

import com.google.gson.annotations.SerializedName;

public class CornerPointModel {
    public CornerPointModel(float x, float y) {

        this.x = x;
        this.y = y;
    }

    @SerializedName("x")

    public float x;

    @SerializedName("y")

    public float y;
}
