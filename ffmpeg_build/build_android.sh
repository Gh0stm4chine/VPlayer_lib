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
ENABLE_X264=yes

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

#
# =======================================================================

if [ -f "$NDK/ndk-build" ]; then
    NDK="$NDK"
elif [ -z "$NDK" ]; then
    echo NDK variable not set or in path, exiting
    echo "   Example: export NDK=/your/path/to/android-ndk"
    echo "   Or add your ndk path to ~/.bashrc"
    echo "   Then run ./build_android.sh"
    exit 1
fi

# Check the Application.mk for the architectures we need to compile for
while read line; do
    if [[ $line =~ ^APP_ABI\ *?:= ]]; then
        line=`echo $line | sed 's/\\r//g'`
        archs=(${line#*=})
        if [[ " ${archs[*]} " == *" all "* ]]; then
            build_all=true
        fi
        break
    fi
done <"../VPlayer_library/jni/Application.mk"
if [ -z "$archs" ]; then
    echo "Application.mk has not specified any architecture, please use 'APP_ABI:=<ARCH>'"
    exit 1
else
    echo "Building for the following architectures: "${archs[@]}
fi

# Get the platform version from Application.mk
PLATFORM_VERSION=9
while read line; do
    if [[ $line =~ ^APP_PLATFORM\ *?:= ]]; then
        line=`echo $line | sed 's/\\r//g'`
        PLATFORM_VERSION=${line#*-}
        break
    fi
done <"../VPlayer_library/jni/Application.mk"
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
while read line; do
    if [[ $line =~ ^SUBTITLES\ *?:= ]]; then
        echo "Going to build with subtitles"
        BUILD_WITH_SUBS=true
    fi
done <"../VPlayer_library/jni/Android.mk"

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
        make STRIP= -j4 install || exit 1
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
    make -j4 install || exit 1
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
    make -j4 install || exit 1
    cd ..
}
function build_png
{
    LINKER_LIBS="$LINKER_LIBS -lpng"
    cd libpng
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
    make -j4 install || exit 1
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
    make -j4 || exit 1
    make -j4 install || exit 1
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
    make V=1 -j4 install || exit 1
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
    make -j4 install || exit 1
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
    make -j4 install || exit 1
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
    if [ ! -z "$BUILD_WITH_SUBS" ]; then
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
    build_ffmpeg
    build_one
    echo "Successfully built $ARCH"
    HOST=
}

# Deprecated architectures only compilable with GCC (which is also deprecated)
if [ ! -z "$USE_GCC" ]; then
    #mips
    if [[ " ${archs[*]} " == *" mips "* ]] || [ "$build_all" = true ]; then
    EABIARCH=mipsel-linux-android
    ARCH=mips
    OPTIMIZE_CFLAGS="-EL -march=mips32 -mips32 -mhard-float"
    PREFIX=../../VPlayer_library/jni/ffmpeg-build/mips
    OUT_LIBRARY=$PREFIX/libffmpeg.so
    ADDITIONAL_CONFIGURE_FLAG="--disable-mipsdspr1 --disable-mipsdspr2 --disable-asm"
    SONAME=libffmpeg.so
    build
    fi

    #arm v5
    if [[ " ${archs[*]} " == *" armeabi "* ]] || [ "$build_all" = true ]; then
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
    fi
fi

#x86
if [[ " ${archs[*]} " == *" x86 "* ]] || [ "$build_all" = true ]; then
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
if [[ " ${archs[*]} " == *" x86_64 "* ]] || [ "$build_all" = true ]; then
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
if [[ " ${archs[*]} " == *" arm64-v8a "* ]] || [ "$build_all" = true ]; then
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
if [[ " ${archs[*]} " == *" armeabi-v7a "* ]] || [ "$build_all" = true ]; then
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