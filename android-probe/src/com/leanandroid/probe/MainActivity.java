package com.leanandroid.probe;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    static {
        System.loadLibrary("leanjni");
    }

    public native String leanProbe();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView tv = new TextView(this);
        tv.setTextSize(16f);
        tv.setPadding(32, 64, 32, 32);
        String result;
        try {
            result = leanProbe();
        } catch (Throwable t) {
            result = "threw: " + t;
        }
        tv.setText(result);
        setContentView(tv);
        android.util.Log.i("LeanProbe", result);
    }
}
