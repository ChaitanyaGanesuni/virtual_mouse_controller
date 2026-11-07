package com.retroplay.app.data.device

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLSurface
import android.opengl.GLES20
import com.retroplay.app.compatibility.device.GpuInfoProvider
import com.retroplay.app.domain.model.GpuInfo
import javax.inject.Inject

/**
 * Reads GL_RENDERER / GL_VENDOR / GL_VERSION by creating a temporary 1×1 off-screen EGL context.
 * The context is created and destroyed on the calling thread; it never touches the UI surface.
 */
class EglGpuInfoProvider @Inject constructor() : GpuInfoProvider {

    override fun queryGpuInfo(): GpuInfo {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) return GpuInfo.unavailable("No EGL display")
        val version = IntArray(2)
        if (!EGL14.eglInitialize(display, version, 0, version, 1)) return GpuInfo.unavailable("EGL initialisation failed")

        var context: EGLContext = EGL14.EGL_NO_CONTEXT
        var surface: EGLSurface = EGL14.EGL_NO_SURFACE
        try {
            val configAttribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            if (!EGL14.eglChooseConfig(display, configAttribs, 0, configs, 0, 1, count, 0) || count[0] == 0) {
                return GpuInfo.unavailable("No suitable EGL configuration")
            }
            val config = configs[0]
            context = EGL14.eglCreateContext(
                display, config, EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
            )
            if (context == EGL14.EGL_NO_CONTEXT) return GpuInfo.unavailable("Could not create EGL context")
            surface = EGL14.eglCreatePbufferSurface(
                display, config, intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0,
            )
            if (surface == EGL14.EGL_NO_SURFACE) return GpuInfo.unavailable("Could not create EGL surface")
            if (!EGL14.eglMakeCurrent(display, surface, surface, context)) {
                return GpuInfo.unavailable("Could not activate EGL context")
            }
            return GpuInfo(
                renderer = GLES20.glGetString(GLES20.GL_RENDERER),
                vendor = GLES20.glGetString(GLES20.GL_VENDOR),
                glVersion = GLES20.glGetString(GLES20.GL_VERSION),
                glslVersion = GLES20.glGetString(GLES20.GL_SHADING_LANGUAGE_VERSION),
                eglVersion = "${version[0]}.${version[1]}",
            )
        } catch (e: Exception) {
            return GpuInfo.unavailable(e.message ?: e::class.java.simpleName)
        } finally {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
            if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
            EGL14.eglReleaseThread()
            // The default display is shared with the UI renderer, so it is intentionally not terminated.
        }
    }
}
