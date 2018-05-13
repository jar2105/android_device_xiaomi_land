package com.cyanogenmod.settings.device;

import android.content.Context;
import android.content.SharedPreferences;
import android.preference.Preference;
import android.preference.Preference.OnPreferenceChangeListener;
import android.preference.PreferenceManager;

public class TapToWakeSwitch implements OnPreferenceChangeListener {

    private static final String FILE = "/sys/android_touch/doubletap2wake";

    public static String getFile() {
        if (Utils.fileWritable(FILE)) {
            return FILE;
        }
        return null;
    }

    public static boolean isSupported() {
        return Utils.fileWritable(getFile());
    }

    public static boolean isCurrentlyEnabled(Context context) {
        return Utils.getFileValueAsBoolean(getFile(), false);
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        Boolean enabled = (Boolean) newValue;
        Utils.writeValue(getFile(), enabled ? "1" : "0");
        return true;
    }
}
