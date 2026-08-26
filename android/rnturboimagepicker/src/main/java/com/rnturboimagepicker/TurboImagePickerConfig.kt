package com.rnturboimagepicker

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import java.util.Locale

object TurboImagePickerConfig {
    var languageCode: String = "en"

    fun attachBaseContext(newBase: Context): Context {
        val locale = Locale(languageCode)
        Locale.setDefault(locale)
        val config = android.content.res.Configuration(newBase.resources.configuration)
        config.setLocale(locale)
        return newBase.createConfigurationContext(config)
    }
    fun applyLocale(lang: String) {
        languageCode = lang
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(lang))
    }
}
