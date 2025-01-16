package com.abomis.camera_kit_plus.Classes;
import com.google.gson.annotations.SerializedName;

import java.util.ArrayList;
import java.util.List;

public class LineModel {
    @SerializedName("text")
    public String text;
    @SerializedName("cornerPoints")
    public List<CornerPointModel> cornerPoints;

    public LineModel(String text) {
        this.text = text;
        this.cornerPoints = new ArrayList<>();
    }

    // Manual JSON Serialization

}
