#!/bin/bash
GIT_SSL_NO_VERIFY=true

function addAutomakeOpts() {
    if !(grep -Rq "AUTOMAKE_OPTIONS" Makefile.am)
    then
        sed -i '1iAUTOMAKE_OPTIONS=subdir-objects' Makefile.am
    fi
}

cd ..
git submodule update --init --recursive
cd ffmpeg_build

# Configure libjpeg
cd libjpeg-turbo
autoreconf -fiv
cd ..

# configure the environment
cd libpng
sh ./autogen.sh
cd ..

# configure the environment
cd freetype2
sh ./autogen.sh
cd ..

# fribidi
cd fribidi
autoreconf -ivf
cd ..

# libass
cd libass
autoreconf -ivf
cd ..

# aacenc environment
cd vo-aacenc
addAutomakeOpts
autoreconf -ivf
cd ..

# vo-amrwbenc environment
cd vo-amrwbenc
addAutomakeOpts
autoreconf -ivf
cd ..

# fdk-aac environment
cd fdk-aac
sh ./autogen.sh
cd ..

# Start the build!
source build_android.sh "$@"

