#!/bin/bash

# Do it twice incase some repos are not cloned!
# You only need ffmpeg repo if you are not building it, but we have to update all submodules
git submodule update --init --recursive
git submodule update --init --recursive

# Copy all the header files into ffmpeg folder under the project
SRC_FOLDER=../../ffmpeg_build/ffmpeg
DST_FOLDER=ffmpeg
mkdir -p $DST_FOLDER
(cd $SRC_FOLDER && find . -name '*.h' -print | tar --create --files-from -) | (cd $DST_FOLDER && tar xvfp -)

# Copy all the header files into ffmpeg folder under the project
SRC_FOLDER=../../ffmpeg_build/
DST_FOLDER=libjpeg-turbo
mkdir -p $DST_FOLDER
(cd $SRC_FOLDER/$DST_FOLDER && find . -name '*.h' -print | tar --create --files-from -) | (cd $DST_FOLDER && tar xvfp -)