#import "SurfaceViewController.h"

#include "jni.h"
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"

int clientAPI;

void JNI_LWJGL_changeRenderer(const char* value_c) {

    JNIEnv *env;

    (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);

    const char *lwjgl_value = value_c;

    /*
     * GL4ES 1.1.6 is preloaded by native Amethyst below with dlopen("@rpath/...").
     * Do not let LWJGL/MacOSXLibraryDL load libgl4es_116.dylib directly again.
     * It can fail on iOS even after native preload.
     *
     * Keep POJAV_RENDERER as libgl4es_116.dylib, but route LWJGL's
     * org.lwjgl.opengl.libname to the stable GL4ES 1.1.4 library name.
     */
    if (value_c && strcmp(value_c, RENDERER_NAME_GL4ES_116) == 0) {
        lwjgl_value = RENDERER_NAME_GL4ES;
    }

    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");

    jstring value = (*env)->NewStringUTF(env, lwjgl_value);

    jclass clazz = (*env)->FindClass(env, "java/lang/System");

    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");

    (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
}

void pojavTerminate() {
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pojavGetCurrentContext() {
    return br_get_current();
}

int pojavInit(BOOL useStackQueue) {
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    isUseStackQueueCall = useStackQueue;
    return JNI_TRUE;
}

int pojavInitOpenGL() {
    NSString *renderer = NSProcessInfo.processInfo.environment[@"POJAV_RENDERER"];
    BOOL isAuto = [renderer isEqualToString:@"auto"];

    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // Default GL4ES renderer
        renderer = @ RENDERER_NAME_GL4ES;
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();

    } else if ([renderer isEqualToString:@ RENDERER_NAME_GL4ES_116]) {
        // GL4ES 1.1.6 renderer: use the same GL bridge as GL4ES 1.1.4
        renderer = @ RENDERER_NAME_GL4ES_116;
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();

    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();

    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();

    } else if ([renderer hasPrefix:@"libOSMesa"]) {
        setenv("GALLIUM_DRIVER", "zink", 1);
        set_osm_bridge_tbl();
    }

    JNI_LWJGL_changeRenderer(renderer.UTF8String);

    // Preload renderer library
    dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);

    return !br_init();
}

void pojavSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
    } else if (strcmp(getenv("POJAV_RENDERER"), "auto") == 0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                setenv("POJAV_RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;

            // case 4: use Zink?
            default:
                setenv("POJAV_RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pojavSwapBuffers() {
    br_swap_buffers();
}

void pojavMakeCurrent(basic_render_window_t* window) {
    br_make_current(window);
}

void* pojavCreateContext(basic_render_window_t* contextSrc) {
    if (clientAPI == GLFW_NO_API) {
        // Game has selected Vulkan API to render
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    static BOOL inited = NO;
    if (!inited) {
        inited = YES;
        pojavInitOpenGL();
    }

    return br_init_context(contextSrc);
}

void pojavSwapInterval(int interval) {
    if (!br_swap_interval) return;
    br_swap_interval(interval);
}