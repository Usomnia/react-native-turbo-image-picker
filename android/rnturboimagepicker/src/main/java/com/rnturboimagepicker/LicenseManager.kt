package com.rnturboimagepicker

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object LicenseManager {
    private const val SECRET_KEY = "43664971c55c33ac701caa010c3ddcd12ef6ba082c0e83cf6aa8f5ba3c600340"
    var isLicensed = false
        private set

    fun initialize(context: Context, key: String): Boolean {
        try {
            val packageName = context.packageName
            val mac = Mac.getInstance("HmacSHA256")
            val secretKeySpec = SecretKeySpec(SECRET_KEY.toByteArray(Charsets.UTF_8), "HmacSHA256")
            mac.init(secretKeySpec)
            
            val hmacBytes = mac.doFinal(packageName.toByteArray(Charsets.UTF_8))
            val expectedKey = hmacBytes.joinToString("") { "%02x".format(it) }
            
            if (key == expectedKey) {
                isLicensed = true
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        isLicensed = false
        return false
    }

    fun isValidLicense(context: Context): Boolean {
        return isLicensed
    }

    fun showLicenseAlert(activity: Activity) {
        activity.runOnUiThread {
            AlertDialog.Builder(activity)
                .setTitle("Unauthorized License")
                .setMessage("This RNTurboImagePicker library is strictly licensed By Usomnia. Contact: contact@usomnia.co.kr")
                .setCancelable(false)
                .setPositiveButton("OK") { dialog, _ ->
                    dialog.dismiss()
                }
                .show()
        }
    }
}
