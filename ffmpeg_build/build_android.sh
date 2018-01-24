#!/bin/bash
#
# build_android.sh
# Copyright (c) 2012 Jacek Marchwicki
# Modified work Copyright 2014 Matthew Ng
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

# =======================================================================
#   Customize FFmpeg build
#       Comment out what you do not need, specifying 'no' will not
#       disable them.
#
#   Building with x264
#       Will not work for armv5
#ENABLE_X264=yes

#   Toolchain version
#       Comment out if you want default or specify a version
#       Default takes the highest toolchain version from NDK
# TOOLCHAIN_VER=4.6

#   Use fdk-aac instead of vo-amrwbenc
#       Default uses vo-amrwbenc and it is worse than fdk-aac but
#       because of licensing, it requires you to build FFmpeg from
#       scratch if you want to use fdk-aac. Uncomment to use fdk-aac
# PREFER_FDK_AAC=yes

#   Use GCC or Clang
#       GCC is being deprecated and Android recommends clang. If you use clang,
#       the toolchain root below will be used. By default it will use clang, use
#       GCC by uncommenting below. GCC can build mips and armv5 while not for
#       clang (linker errors and deprecated).
#USE_GCC=yes

#   Specify Toolchain root
#       https://developer.android.com/ndk/guides/standalone_toolchain.html#creating_the_toolchain
TOOLCHAIN_ROOT=/tmp/android-toolchain/

#   Include libjpeg-turbo in build
#       Jpeg is only needed for the application not shared library for libyuv,
#       If you need libjpeg-turbo inside the shared library then uncomment.
#       It is not included to save space in the binary.
#INCLUDE_JPEG=yes

#
# =======================================================================

# Parse command line
for i in "$@"
do
case $i in
    -j*)
    JOBS="${i#*j}"
    shift
    ;;
    -a=*|--arch=*)
    BUILD_ARCHS="${i#*=}"
    if [[ " ${BUILD_ARCHS[*]} " == *" all_with_deprecated "* ]]; then
        BUILD_ALL_WITH_DEPS=true
        BUILD_ALL=true
    fi
    shift
    ;;
    --gcc)
    USE_GCC=yes
    shift;;
    --use-h264)
    ENABLE_X264=yes
    shift
    ;;
    --use-fdk-aac)
    PREFER_FDK_AAC=yes
    shift
    ;;
    -p=*|--platform=*)
    PLATFORM_VERSION="${i#*=}"
    shift
    ;;
    --no-subs)
    BUILD_WITH_SUBS=no
    shift
    ;;
    --ndk=*)
    eval NDK="${i#*=}"
    shift
    ;;
    -h|--help)
    echo "Usage: build_android.sh [options]"
    echo "  Options here will override options from files it may read from"
    echo
    echo "Help options:"
    echo "  -h, --help                  displays this message and exits"
    echo
    echo "Building library options:"
    echo "  --use-h264                  build with h264 encoding library"
    echo "  --use-fdk-aac               build with fdk acc instead of vo-aacenc"
    echo "  --no-subs                   do not build with subs"
    echo "                              this will override the setting in ../VPlayer_library/jni/Android.mk"
    echo
    echo "Optional build flags:"
    echo "  -j#[4]                      number of jobs, default is 4 (threads)"
    echo "                              this will override the setting in ../VPlayer_library/build.gradle"
    echo "                              'android.defaultConfig.externalNativeBuild.ndkBuild.arguments' line"
    echo "  -p=[9], --platform=[9]      build with sdk platform"
    echo "                              this will override the setting in ../VPlayer_library/build.gradle"
    echo "                              'android.compileSdkVersion'"
    echo "  --ndk=[DIR]                 path to your ndk and will override the environment variable"
    echo "  -a=[LIST], --arch=[LIST]    enter a list of architectures to build with"
    echo "                              this will override the setting in ../VPlayer_library/build.gradle"
    echo "                              of the first match of line 'abiFilters'"
    echo "                              options include mips, armeabi (both deprecated), arm64-v8a, x86,"
    echo "                              x86_64, armeabi-v7a"
    echo "                              'all' would built all non-deprecated architectures and"
    echo "                              'all_with_deprecated' will build mips and armeabi with gcc and"
    echo "                              clang with the rest"
    echo
    echo "Notes:"
    echo "  armeabi and mips are deprecated and will only build with gcc, clang will"
    echo "  be the prefered way to compile however you can force build everything with"
    echo "  gcc."
    exit 1
    shift
    ;;
    *)
    echo "Warning: unknown argument '${i#*=}'"
    ;;
esac
done

# Check environment for ndk build
if [ -f "$NDK/ndk-build" ]; then
    NDK="$NDK"
elif [ -z "$NDK" ]; then
    echo NDK variable not set or in path, exiting
    echo "   Example: export NDK=/your/path/to/android-ndk"
    echo "   Or add your ndk path to ~/.bashrc"
    echo "   Or use --ndk=<path> with command"
    echo "   Then run ./build_android.sh"
    exit 1
fi

# Read the build.gradle for default inputs
while read line; do
    # Parse the platform sdk version
    if [ -z "$PLATFORM_VERSION" ] && [[ $line = compileSdkVersion* ]]; then
        a=${line##compileSdkVersion}
        PLATFORM_VERSION=`echo $a | sed 's/\\r//g'`
    fi

    # Parse for the architectures
    if [ -z "$BUILD_ARCHS" ] && [[ $line = abiFilters* ]]; then
        a=${line##abiFilters}
        BUILD_ARCHS=`echo ${a%%//,*} | sed 's/\*[^]]*\*//g'| sed "s/'//g"| sed "s/\"//g"| sed "s/\///g"`
    fi

    # Read jobs
    if [ -z "$JOBS" ] && [[ $line = arguments* ]]; then
        JOBS=`echo $line | sed 's/.*-j\([0-9]*\).*/\1/'`
    fi
done <"../VPlayer_library/build.gradle"

# Default jobs
if [ -z "$JOBS" ]; then
    JOBS=4
fi

# Check if architectures are specified
if [ -z "$BUILD_ARCHS" ]; then
    echo "build.gradle has not specified any architectures, please use 'abiFilters'"
    exit 1
else
    BUILD_ARCHS=`echo $BUILD_ARCHS | sed "s/,/ /g"`
    if [[ " ${BUILD_ARCHS[*]} " == *" all "* ]]; then
        BUILD_ALL=true
    fi
    # Check for architecture inputs are correct
    if [ -z $BUILD_ALL ]; then
        if [[ " ${BUILD_ARCHS[*]} " != *" armeabi-v7a "* ]] \
               && [[ " ${BUILD_ARCHS[*]} " != *" armeabi "* ]] \
               && [[ " ${BUILD_ARCHS[*]} " != *" mips "* ]] \
               && [[ " ${BUILD_ARCHS[*]} " != *" x86 "* ]] \
               && [[ " ${BUILD_ARCHS[*]} " != *" x86_64 "* ]] \
               && [[ " ${BUILD_ARCHS[*]} " != *" arm64-v8a "* ]]; then
           echo "Cannot build with invalid input architectures: ${BUILD_ARCHS[@]}"
           exit
       fi
    fi
    echo "Building for the following architectures: "${BUILD_ARCHS[@]}
fi

# Further parse the platform version
if [ -z "$PLATFORM_VERSION" ]; then
    PLATFORM_VERSION=9      # Default
fi
if [ ! -d "$NDK/platforms/android-$PLATFORM_VERSION" ]; then
    echo "Android platform doesn't exist, try to find a lower version than" $PLATFORM_VERSION
    while [ $PLATFORM_VERSION -gt 0 ]; do
        if [ -d "$NDK/platforms/android-$PLATFORM_VERSION" ]; then
            break
        fi
        let PLATFORM_VERSION=PLATFORM_VERSION-1
    done
    if [ ! -d "$NDK/platforms/android-$PLATFORM_VERSION" ]; then
        echo Cannot find any valid Android platforms inside $NDK/platforms/
        exit 1
    fi
fi
echo Using Android platform from $NDK/platforms/android-$PLATFORM_VERSION

# Get the newest arm-linux-androideabi version
if [ -z "$TOOLCHAIN_VER" ]; then
    folders=$NDK/toolchains/arm-linux-androideabi-*
    for i in $folders; do
        n=${i#*$NDK/toolchains/arm-linux-androideabi-}
        reg='.*?[a-zA-Z].*?'
        if ! [[ $n =~ $reg ]] ; then
            TOOLCHAIN_VER=$n
        fi
    done
    if [ ! -d $NDK/toolchains/arm-linux-androideabi-$TOOLCHAIN_VER ]; then
        echo $NDK/toolchains/arm-linux-androideabi-$TOOLCHAIN_VER does not exist
        exit 1
    fi
fi
echo Using $NDK/toolchains/{ARCH}-$TOOLCHAIN_VER
if [ ! -z "$USE_GCC" ]; then
    echo "Compile with GCC"
else
    echo "Compile with clang (standalone toolchain)"
    # If using clang, check to see if there is gas-preprocessor.pl avaliable, this will require sudo!
    GAS_PREPRO_PATH="/usr/local/bin/gas-preprocessor.pl"
    if [ -z "$USE_GCC" ] && [ ! -x "$GAS_PREPRO_PATH" ]; then
        echo "Downloading needed gas-preprocessor.pl for FFMPEG"
        wget --no-check-certificate https://raw.githubusercontent.com/FFmpeg/gas-preprocessor/master/gas-preprocessor.pl
        chmod +x gas-preprocessor.pl
        mv gas-preprocessor.pl $GAS_PREPRO_PATH
        if  [ ! -x "$GAS_PREPRO_PATH" ]; then
            echo "  Cannot move file, please run this script with permissions [ sudo -E ./build_android.sh ]"
            exit 1
        fi
        echo "  Finished downloading gas-preprocessor.pl"
    fi
fi

# Read from the Android.mk file to build subtitles (fribidi, libpng, freetype2, libass)
if [ -z "$BUILD_WITH_SUBS" ]; then
    while read line; do
        if [[ $line =~ ^SUBTITLES\ *?:= ]]; then
            echo "Going to build with subtitles"
            BUILD_WITH_SUBS=yes
        fi
    done <"../VPlayer_library/jni/Android.mk"
fi

OS=`uname -s | tr '[A-Z]' '[a-z]'`

# Runs routines to find folders and links once per architecture
function setup
{
    # For clang, use standalone toolchain, gcc use the default NDK folder
    PREBUILT=$TOOLCHAIN_ROOT
    PLATFORM=$NDK/platforms/android-$PLATFORM_VERSION/arch-$ARCH/
    if [ ! -d "$PREBUILT" ] || [ ! -z "$USE_GCC" ]; then
        if [ -d "$NDK/toolchains/$EABIARCH-$TOOLCHAIN_VER/" ]; then
            PREBUILT=$NDK/toolchains/$EABIARCH-$TOOLCHAIN_VER/prebuilt/$OS-x86
        else
            PREBUILT=$NDK/toolchains/$ARCH-$TOOLCHAIN_VER/prebuilt/$OS-x86
        fi
        if [ ! -d "$PREBUILT" ]; then PREBUILT="$PREBUILT"_64; fi
    fi
    export PATH=${PATH}:$PREBUILT/bin/
    CROSS_COMPILE=$PREBUILT/bin/$EABIARCH-

    # Changes in NDK leads to new folder paths, add them if they exist
    # https://android.googlesource.com/platform/ndk.git/+/master/docs/UnifiedHeaders.md
    if [ -z "$USE_GCC" ] && [ -d "$TOOLCHAIN_ROOT/sysroot" ]; then
        SYSROOT=$TOOLCHAIN_ROOT/sysroot
    elif [ -d "$NDK/sysroot" ]; then
        SYSROOT=$NDK/sysroot
    else
        SYSROOT=$PLATFORM
    fi
    if [ -d "$SYSROOT/usr/include/$EABIARCH/" ]; then
        OPTIMIZE_CFLAGS=$OPTIMIZE_CFLAGS" -isystem $SYSROOT/usr/include/$EABIARCH/ -D__ANDROID_API__=$PLATFORM_VERSION"
    fi

    # Find libgcc.a to merge and link all the libraries
    LIBGCC_PATH=
    folders=$PREBUILT/lib/gcc/$EABIARCH/$TOOLCHAIN_VER*
    for i in $folders; do
        if [ -f "$i/libgcc.a" ]; then
            LIBGCC_PATH="$i/libgcc.a"
            break
        fi
    done
    if [ -z "$LIBGCC_PATH" ]; then
        echo "Failed: Unable to find libgcc.a from toolchain path, file a bug or look for it"
        exit 1
    fi

    # Link the GCC library if arm below and including armv7
    LIBGCC_LINK=
    if [[ $HOST == *"arm"* ]]; then
        LIBGCC_LINK="-l$LIBGCC_PATH"
    else
        LIBGCC_LINK="-lgcc"
    fi

    # Handle 64bit paths
    ARCH_BITS=
    if [[ "$ARCH" == *64 ]]; then
        ARCH_BITS=64
    fi

    # Find the library link folder
    if [ ! -z "$USE_GCC" ]; then
        LINKER_FOLDER=$PLATFORM/usr/lib
    else
        LINKER_FOLDER=$SYSROOT/usr/lib
    fi
    if [ -d "$LINKER_FOLDER$ARCH_BITS" ]; then
        LINKER_FOLDER=$LINKER_FOLDER$ARCH_BITS
    fi

    LINKER_LIBS=
    CFLAGS=$OPTIMIZE_CFLAGS
    export LDFLAGS="-Wl,-rpath-link=$LINKER_FOLDER -L$LINKER_FOLDER -lc -lm -ldl -llog -nostdlib $LIBGCC_LINK"
    export CPPFLAGS="$CFLAGS"
    export CFLAGS="$CFLAGS"
    export CXXFLAGS="$CFLAGS"
    if [ ! -z "$USE_GCC" ]; then
        export CXX="${CROSS_COMPILE}g++ --sysroot=$SYSROOT"
        export AS="${CROSS_COMPILE}gcc --sysroot=$SYSROOT"
        export CC="${CROSS_COMPILE}gcc --sysroot=$SYSROOT"
    else
        export CXX="clang++"
        export AS="clang"
        export CC="clang"
    fi
    export NM="${CROSS_COMPILE}nm"
    export STRIP="${CROSS_COMPILE}strip"
    export RANLIB="${CROSS_COMPILE}ranlib"
    export AR="${CROSS_COMPILE}ar"
    export LD="${CROSS_COMPILE}ld"
}
function build_x264
{
    find x264/ -name "*.o" -type f -delete
    if [ ! -z "$ENABLE_X264" ] && [ "$CPU" != "armv5" ]; then
        ADDITIONAL_CONFIGURE_FLAG="$ADDITIONAL_CONFIGURE_FLAG --enable-gpl --enable-libx264"
        LINKER_LIBS="$LINKER_LIBS -lx264"
        cd x264
        ./configure --prefix=$(pwd)/$PREFIX --disable-gpac --host=$HOST --enable-pic --enable-static $ADDITIONAL_CONFIGURE_FLAG || exit 1
        make clean || exit 1
        make STRIP= -j${JOBS} install || exit 1
        cd ..
    fi
}

function build_amr
{
    LINKER_LIBS="$LINKER_LIBS -lvo-amrwbenc"
    cd vo-amrwbenc
    ADDITIONAL_CONFIGURE_FLAG="$ADDITIONAL_CONFIGURE_FLAG --enable-libvo-amrwbenc"
    ./configure \
        --prefix=$(pwd)/$PREFIX \
        --host=$HOST \
        --disable-dependency-tracking \
        --disable-shared \
        --enable-static \
        --with-pic \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make -j${JOBS} install || exit 1
    cd ..
}

function build_aac
{
    if [ ! -z "$PREFER_FDK_AAC" ]; then
        echo "Using fdk-aac encoder for AAC"
        find vo-aacenc/ -name "*.o" -type f -delete
        ADDITIONAL_CONFIGURE_FLAG="$ADDITIONAL_CONFIGURE_FLAG --enable-libfdk_aac"
        LINKER_LIBS="$LINKER_LIBS -lfdk-aac"
        cd fdk-aac
    else
        echo "Using vo-aacenc encoder for AAC"
        find fdk-aac/ -name "*.o" -type f -delete
        ADDITIONAL_CONFIGURE_FLAG="$ADDITIONAL_CONFIGURE_FLAG --enable-libvo-aacenc"
        LINKER_LIBS="$LINKER_LIBS -lvo-aacenc"
        cd vo-aacenc
    fi
    export PKG_CONFIG_LIBDIR=$(pwd)/$PREFIX/lib/pkgconfig/
    export PKG_CONFIG_PATH=$(pwd)/$PREFIX/lib/pkgconfig/
    ./configure \
        --prefix=$(pwd)/$PREFIX \
        --host=$HOST \
        --disable-dependency-tracking \
        --disable-shared \
        --enable-static \
        --with-pic \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make -j${JOBS} install || exit 1
    cd ..
}
function build_jpeg
{
    if [ ! -z "$INCLUDE_JPEG" ]; then
        LINKER_LIBS="$LINKER_LIBS -ljpeg"
    fi
    cd libjpeg-turbo
    ./configure \
        --prefix=$(pwd)/$PREFIX \
        --host=$HOST \
        --build=$ARCH-unknown-linux-gnu \
        --disable-dependency-tracking \
        --disable-shared \
        --enable-static \
        --with-pic \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make -j${JOBS} install || exit 1
    cd ..
}
function build_png
{
    LINKER_LIBS="$LINKER_LIBS -lpng"
    cd libpng
    ./configure \
        --prefix=$(pwd)/$PREFIX \
        --host=$HOST \
        --build=$ARCH-unknown-linux-gnu \
        --disable-dependency-tracking \
        --disable-shared \
        --enable-static \
        --with-pic \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make -j${JOBS} install || exit 1
    cd ..
}
function build_freetype2
{
    LINKER_LIBS="$LINKER_LIBS -lfreetype"
    cd freetype2
    export PKG_CONFIG_LIBDIR=$(pwd)/$PREFIX/lib/pkgconfig/
    export PKG_CONFIG_PATH=$(pwd)/$PREFIX/lib/pkgconfig/
    ./configure \
        --prefix=$(pwd)/$PREFIX \
        --host=$HOST \
        --build=$ARCH-unknown-linux-gnu \
        --disable-dependency-tracking \
        --disable-shared \
        --enable-static \
        --with-pic \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make -j${JOBS} || exit 1
    make -j${JOBS} install || exit 1
    cd ..
}
function build_ass
{
    LINKER_LIBS="$LINKER_LIBS -lass"
    ADDITIONAL_CONFIGURE_FLAG=$ADDITIONAL_CONFIGURE_FLAG" --enable-libass"
    cd libass
    export PKG_CONFIG_LIBDIR=$(pwd)/$PREFIX/lib/pkgconfig/
    export PKG_CONFIG_PATH=$(pwd)/$PREFIX/lib/pkgconfig/
    ./configure \
        --prefix=$(pwd)/$PREFIX \
        --host=$HOST \
        --disable-fontconfig \
        --disable-dependency-tracking \
        --disable-shared \
        --enable-static \
        --with-pic \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make V=1 -j${JOBS} install || exit 1
    cd ..
}
function build_fribidi
{
    export PATH=${PATH}:$PREBUILT/bin/
    LINKER_LIBS="$LINKER_LIBS -lfribidi"
    cd fribidi
    ./configure \
        --prefix=$(pwd)/$PREFIX \
        --host=$HOST \
        --build=$ARCH-unknown-linux-gnu \
        --disable-bin \
        --disable-dependency-tracking \
        --disable-shared \
        --enable-static \
        --with-pic \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make -j${JOBS} install || exit 1
    cd ..
}
function build_ffmpeg
{
    LINKER_LIBS="$LINKER_LIBS -lavcodec -lavformat -lavresample -lavutil -lswresample -lswscale"
    PKG_CONFIG=${CROSS_COMPILE}pkg-config
    if [ ! -f $PKG_CONFIG ];
    then
        cat > $PKG_CONFIG << EOF
#!/bin/bash
pkg-config \$*
EOF
        chmod u+x $PKG_CONFIG
    fi
    cd ffmpeg
    export PKG_CONFIG_LIBDIR=$(pwd)/$PREFIX/lib/pkgconfig/
    export PKG_CONFIG_PATH=$(pwd)/$PREFIX/lib/pkgconfig/
    ./configure --target-os=linux \
        --prefix=$PREFIX \
        --enable-cross-compile \
        --arch=$ARCH \
        --cc=$CC \
        --cross-prefix=$CROSS_COMPILE \
        --nm=$NM \
        --sysroot=$SYSROOT \
        --extra-libs=$LIBGCC_LINK \
        --extra-cflags=" -O3 -DANDROID -fpic -DHAVE_SYS_UIO_H=1 -Dipv6mr_interface=ipv6mr_ifindex -fasm -Wno-psabi -fno-short-enums  -fno-strict-aliasing -finline-limit=300 -I$PREFIX/include $OPTIMIZE_CFLAGS" \
        --disable-shared \
        --enable-static \
        --enable-runtime-cpudetect \
        --extra-ldflags="-Wl,-rpath-link=$SYSROOT/usr/lib -L$SYSROOT/usr/lib  -nostdlib -lc -lm -ldl -llog -L$PREFIX/lib" \
        --enable-bsfs \
        --enable-decoders \
        --enable-encoders \
        --enable-parsers \
        --enable-hwaccels \
        --enable-muxers \
        --enable-avformat \
        --enable-avcodec \
        --enable-avresample \
        --enable-zlib \
        --disable-doc \
        --disable-ffplay \
        --disable-ffmpeg \
        --disable-ffplay \
        --disable-ffprobe \
        --disable-ffserver \
        --disable-avfilter \
        --disable-avdevice \
        --enable-nonfree \
        --enable-version3 \
        --enable-memalign-hack \
        --enable-asm \
        $ADDITIONAL_CONFIGURE_FLAG \
        || exit 1
    make clean || exit 1
    make -j${JOBS} install || exit 1
    cd ..
}

function build_one {
    cd ffmpeg

    # Link all libraries into one shared object
    ${LD} -rpath-link=$LINKER_FOLDER -L$LINKER_FOLDER -L$PREFIX/lib -soname $SONAME -shared -nostdlib -Bsymbolic \
    --whole-archive --no-undefined -o $OUT_LIBRARY $LINKER_LIBS -lc -lm -lz -ldl -llog   \
    --dynamic-linker=/system/bin/linker -zmuldefs $LIBGCC_PATH || exit 1
    $PREBUILT/bin/$EABIARCH-strip --strip-unneeded $OUT_LIBRARY
    cd ..
}
function build_subtitles
{
    if [[ "$BUILD_WITH_SUBS" == "yes" ]]; then
        build_fribidi
        build_png
        build_freetype2
        build_ass
    fi
}
function build
{
    echo "================================================================"
    echo "================================================================"
    echo "                      Building $ARCH"
    echo "$OUT_LIBRARY"
    echo "================================================================"
    echo "================================================================"
    if [ -z "$USE_GCC" ] && [ ! -z "$TOOLCHAIN_ROOT" ] && [ ! -d "$TOOLCHAIN_ROOT/$EABIARCH" ]; then
        echo "Creating standalone toolchain in $TOOLCHAIN_ROOT"
        $NDK/build/tools/make_standalone_toolchain.py --arch "$ARCH" --api $PLATFORM_VERSION --stl=libc++ --install-dir $TOOLCHAIN_ROOT --force
        echo "      Built the standalone toolchain"
    fi
    if [ -z "$HOST" ]; then
        HOST=$ARCH-linux
    fi
    setup
    build_x264
    build_amr
    build_aac
    build_subtitles
    build_jpeg
    build_ffmpeg
    build_one
    echo "Successfully built $ARCH"
    HOST=
}

# Delete the distributed folder in library
if [ -d "../VPlayer_library/jni/dist" ]; then
    echo "Deleting old binaries from dist folder in library"
    rm -rf ../VPlayer_library/jni/dist
fi

# Deprecated architectures only compilable with GCC (which is also deprecated)
#mips
if [[ " ${BUILD_ARCHS[*]} " == *" mips "* ]] || [ ! -z "$BUILD_ALL_WITH_DEPS" ]; then
WAS_USING_GCC=$USE_GCC
USE_GCC=yes
EABIARCH=mipsel-linux-android
ARCH=mips
OPTIMIZE_CFLAGS="-EL -march=mips32 -mips32 -mhard-float"
PREFIX=../../VPlayer_library/jni/ffmpeg-build/mips
OUT_LIBRARY=$PREFIX/libffmpeg.so
ADDITIONAL_CONFIGURE_FLAG="--disable-mipsdspr1 --disable-mipsdspr2 --disable-asm"
SONAME=libffmpeg.so
build
if  [ -z "$WAS_USING_GCC" ]; then
    USE_GCC=
fi
fi

#arm v5
if [[ " ${BUILD_ARCHS[*]} " == *" armeabi "* ]] || [ ! -z "$BUILD_ALL_WITH_DEPS" ]; then
WAS_USING_GCC=$USE_GCC
USE_GCC=yes
EABIARCH=arm-linux-androideabi
ARCH=arm
CPU=armv5
OPTIMIZE_CFLAGS="-marm -march=$CPU"
PREFIX=../../VPlayer_library/jni/ffmpeg-build/armeabi
OUT_LIBRARY=$PREFIX/libffmpeg.so
ADDITIONAL_CONFIGURE_FLAG=
SONAME=libffmpeg.so
# If you want x264, compile armv6
find x264/ -name "*.o" -type f -delete
build
if  [ -z "$WAS_USING_GCC" ]; then
    USE_GCC=
fi
fi

#x86
if [[ " ${BUILD_ARCHS[*]} " == *" x86 "* ]] || [ "$BUILD_ALL" = true ]; then
EABIARCH=i686-linux-android
ARCH=x86
OPTIMIZE_CFLAGS="-m32"
PREFIX=../../VPlayer_library/jni/ffmpeg-build/x86
OUT_LIBRARY=$PREFIX/libffmpeg.so
ADDITIONAL_CONFIGURE_FLAG=--disable-asm
SONAME=libffmpeg.so
build
fi

#x86_64
if [[ " ${BUILD_ARCHS[*]} " == *" x86_64 "* ]] || [ "$BUILD_ALL" = true ]; then
ARCH=x86_64
EABIARCH=$ARCH-linux-android
OPTIMIZE_CFLAGS="-m64"
PREFIX=../../VPlayer_library/jni/ffmpeg-build/$ARCH
OUT_LIBRARY=$PREFIX/libffmpeg.so
ADDITIONAL_CONFIGURE_FLAG=--disable-asm
SONAME=libffmpeg.so
build
fi

#arm64-v8a
if [[ " ${BUILD_ARCHS[*]} " == *" arm64-v8a "* ]] || [ "$BUILD_ALL" = true ]; then
CPU=arm64
ARCH=$CPU
HOST=aarch64-linux
EABIARCH=$HOST-android
OPTIMIZE_CFLAGS=
PREFIX=../../VPlayer_library/jni/ffmpeg-build/arm64-v8a
OUT_LIBRARY=$PREFIX/libffmpeg.so
ADDITIONAL_CONFIGURE_FLAG=--enable-neon
SONAME=libffmpeg-neon.so
build
fi

#arm v7vfpv3
if [[ " ${BUILD_ARCHS[*]} " == *" armeabi-v7a "* ]] || [ "$BUILD_ALL" = true ]; then
EABIARCH=arm-linux-androideabi
ARCH=arm
CPU=armv7-a
OPTIMIZE_CFLAGS="-mfloat-abi=softfp -mfpu=vfpv3-d16 -marm -march=$CPU "
PREFIX=../../VPlayer_library/jni/ffmpeg-build/armeabi-v7a
OUT_LIBRARY=$PREFIX/libffmpeg.so
ADDITIONAL_CONFIGURE_FLAG=
SONAME=libffmpeg.so
build

#arm v7 + neon (neon also include vfpv3-32)
EABIARCH=arm-linux-androideabi
OPTIMIZE_CFLAGS="-mfloat-abi=softfp -mfpu=neon -marm -march=$CPU -mtune=cortex-a8 -mthumb -D__thumb__ "
PREFIX=../../VPlayer_library/jni/ffmpeg-build/armeabi-v7a-neon
OUT_LIBRARY=../../VPlayer_library/jni/ffmpeg-build/armeabi-v7a/libffmpeg-neon.so
ADDITIONAL_CONFIGURE_FLAG=--enable-neon
SONAME=libffmpeg-neon.so
build
fi

echo "All built"