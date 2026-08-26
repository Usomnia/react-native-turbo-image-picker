package com.rnturboimagepicker;

import android.graphics.drawable.Drawable;
import android.view.View;
import android.widget.ProgressBar;
import com.bumptech.glide.load.DataSource;
import com.bumptech.glide.load.engine.GlideException;
import com.bumptech.glide.request.RequestListener;
import com.bumptech.glide.request.target.Target;

public class GlideHelper {
    public static RequestListener<Drawable> getListener(ProgressBar progressBar) {
        return new RequestListener<Drawable>() {
            @Override
            public boolean onLoadFailed(GlideException e, Object model, Target<Drawable> target, boolean isFirstResource) {
                progressBar.setVisibility(View.GONE);
                return false;
            }

            @Override
            public boolean onResourceReady(Drawable resource, Object model, Target<Drawable> target, DataSource dataSource, boolean isFirstResource) {
                progressBar.setVisibility(View.GONE);
                return false;
            }
        };
    }
}
