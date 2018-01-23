# Android.mk
# Copyright (c) 2012 Jacek Marchwicki
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

#
#   Presets - comment out what you don't need
#
#           If you comment out FEATURE_NEON, you need to remove System.LoadLibrary
#           from the java code in VPlayerController.java. Also you may want to remove
#           libffmpeg-neon.so copying code in build.gradle, sorry gradle makes it too
#           complicated to merge settings
FEATURE_NEON:=yes
#LIBRARY_PROFILER:=yes
SUBTITLES:=yes

# add support for encryption
MODULE_ENCRYPT:=yes



#if armeabi-v7a
ifeq ($(TARGET_ARCH_ABI), armeabi-v7a)
    ifdef FEATURE_NEON
        # add neon optimization code (only armeabi-v7a)
        FEATURE_NEON:=yes
        LOCAL_ARM_NEON := true
    endif
else
    FEATURE_NEON:=
endif

#if armeabi or armeabi-v7a
ifeq ($(TARGET_ARCH_ABI),$(filter $(TARGET_ARCH_ABI),armeabi armeabi-v7a arm64-v8a))
    ifdef LIBRARY_PROFILER
        # add profiler (only arm)
        LIBRARY_PROFILER:=yes
	endif
else
    LIBRARY_PROFILER:=
endif

include $(CLEAR_VARS)
LOCAL_MODULE := ffmpeg-prebuilt
LOCAL_SRC_FILES := ffmpeg-build/$(TARGET_ARCH_ABI)/libffmpeg.so
LOCAL_EXPORT_C_INCLUDES := ffmpeg-build/$(TARGET_ARCH_ABI)/include
LOCAL_EXPORT_LDLIBS := ffmpeg-build/$(TARGET_ARCH_ABI)/libffmpeg.so
LOCAL_PRELINK_MODULE := true
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := libjpeg
LOCAL_SRC_FILES := $(LOCAL_PATH)/ffmpeg-build/$(TARGET_ARCH_ABI)/lib/libjpeg.a
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/libjpeg-turbo
LOCAL_EXPORT_LDLIBS := $(LOCAL_SRC_FILES)
LOCAL_PRELINK_MODULE := true
include $(PREBUILT_STATIC_LIBRARY)

#../../ffmpeg_build/ffmpeg

ifdef FEATURE_NEON
include $(CLEAR_VARS)
LOCAL_MODULE := ffmpeg-prebuilt-neon
LOCAL_SRC_FILES := ffmpeg-build/$(TARGET_ARCH_ABI)/libffmpeg-neon.so
LOCAL_EXPORT_C_INCLUDES := ffmpeg-build/$(TARGET_ARCH_ABI)-neon/include
LOCAL_EXPORT_LDLIBS := ffmpeg-build/$(TARGET_ARCH_ABI)/libffmpeg-neon.so
LOCAL_PRELINK_MODULE := true
include $(PREBUILT_SHARED_LIBRARY)
endif

#ffmpeg-jni library
include $(CLEAR_VARS)
LOCAL_ALLOW_UNDEFINED_SYMBOLS=false

LOCAL_MODULE := ffmpeg-jni
LOCAL_SRC_FILES := application/ffmpeg-jni.c application/player.c application/queue.c \
                   application/helpers.c application/jni-protocol.c application/blend.c \
                   application/convert.cpp
LOCAL_C_INCLUDES := $(LOCAL_PATH)/ffmpeg-build/$(TARGET_ARCH_ABI)/include \
                    $(LOCAL_PATH)/application
LOCAL_SHARED_LIBRARY := ffmpeg-prebuilt

ifdef SUBTITLES
LOCAL_CFLAGS += -DSUBTITLES
endif

#if enabled profiler add it
ifdef LIBRARY_PROFILER
LOCAL_CFLAGS += -pg -g -DPROFILER
LOCAL_STATIC_LIBRARIES += andprof
LOCAL_REQUIRED_MODULES += andprof
endif

LOCAL_CFLAGS += -DLIBYUV
LOCAL_C_INCLUDES += $(LOCAL_PATH)/libyuv/include
LOCAL_CPP_INCLUDES += $(LOCAL_PATH)/libyuv/include
LOCAL_STATIC_LIBRARIES += libyuv_static
LOCAL_REQUIRED_MODULES += libyuv_static

ifdef MODULE_ENCRYPT
LOCAL_CFLAGS += -DMODULE_ENCRYPT
LOCAL_SRC_FILES += application/aes-protocol.c
LOCAL_C_INCLUDES += $(LOCAL_PATH)/tropicssl/include
LOCAL_STATIC_LIBRARIES += tropicssl
LOCAL_REQUIRED_MODULES += tropicssl
endif

LOCAL_LDLIBS    += -landroid
LOCAL_LDLIBS += -llog -ljnigraphics -lz -lm -g $(LOCAL_PATH)/ffmpeg-build/$(TARGET_ARCH_ABI)/libffmpeg.so
include $(BUILD_SHARED_LIBRARY)


ifdef FEATURE_NEON
include $(CLEAR_VARS)
LOCAL_ALLOW_UNDEFINED_SYMBOLS=false
LOCAL_MODULE := ffmpeg-jni-neon
LOCAL_SRC_FILES := application/ffmpeg-jni.c application/player.c application/queue.c \
                   application/helpers.c application/jni-protocol.c application/blend.c \
                   application/convert.cpp
LOCAL_C_INCLUDES := $(LOCAL_PATH)/ffmpeg-build/$(TARGET_ARCH_ABI)/include \
                    $(LOCAL_PATH)/application
LOCAL_SHARED_LIBRARY := ffmpeg-prebuilt-neon

ifdef SUBTITLES
LOCAL_CFLAGS += -DSUBTITLES
endif

#if enabled profiler add it
ifdef LIBRARY_PROFILER
LOCAL_CFLAGS += -pg -g -DPROFILER
LOCAL_STATIC_LIBRARIES += andprof
LOCAL_REQUIRED_MODULES += andprof
endif

LOCAL_CFLAGS += -DLIBYUV
LOCAL_C_INCLUDES += $(LOCAL_PATH)/libyuv/include
LOCAL_CPP_INCLUDES += $(LOCAL_PATH)/libyuv/include
LOCAL_STATIC_LIBRARIES += libyuv_static
LOCAL_REQUIRED_MODULES += libyuv_static

ifdef MODULE_ENCRYPT
LOCAL_CFLAGS += -DMODULE_ENCRYPT
LOCAL_SRC_FILES += application/aes-protocol.c
LOCAL_C_INCLUDES += $(LOCAL_PATH)/tropicssl/include
LOCAL_STATIC_LIBRARIES += tropicssl
LOCAL_REQUIRED_MODULES += tropicssl
endif

LOCAL_LDLIBS    += -landroid
LOCAL_LDLIBS += -llog -ljnigraphics -lz -lm -g $(LOCAL_PATH)/ffmpeg-build/$(TARGET_ARCH_ABI)/libffmpeg-neon.so
include $(BUILD_SHARED_LIBRARY)
else
include $(CLEAR_VARS)
LOCAL_MODULE := ffmpeg-jni-neon
LOCAL_ALLOW_UNDEFINED_SYMBOLS=false
include $(BUILD_SHARED_LIBRARY)
endif

#nativetester-jni library
include $(CLEAR_VARS)

ifdef FEATURE_VFPV3
LOCAL_CFLAGS += -DFEATURE_VFPV3
endif

ifdef FEATURE_NEON
LOCAL_CFLAGS += -DFEATURE_NEON
endif

LOCAL_ALLOW_UNDEFINED_SYMBOLS=false
LOCAL_MODULE := nativetester-jni
LOCAL_SRC_FILES := application/nativetester-jni.c application/nativetester.c
LOCAL_STATIC_LIBRARIES := cpufeatures
LOCAL_LDLIBS  := -llog
include $(BUILD_SHARED_LIBRARY)

#includes
ifdef MODULE_ENCRYPT
include $(LOCAL_PATH)/Android-tropicssl.mk
endif

ifdef LIBRARY_PROFILER
include $(LOCAL_PATH)/android-ndk-profiler-3.1/android-ndk-profiler.mk
endif

include $(call all-makefiles-under,$(LOCAL_PATH))
$(call import-module,android/cpufeatures)
