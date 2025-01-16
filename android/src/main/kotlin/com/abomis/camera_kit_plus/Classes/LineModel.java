package com.abomis.camera_kit_plus.Classes;

import java.util.ArrayList;
import java.util.List;

public class LineModel {

    public String text;
    public List<CornerPointModel> cornerPoints;

    public LineModel(String text) {
        this.text = text;
        this.cornerPoints = new ArrayList<>();
    }


}
