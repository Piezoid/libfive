#!/bin/bash
set -x -e

EXE=Studio
APP=$EXE.app

VERSION=`git describe --exact-match --tags || echo "($(git rev-parse --abbrev-ref HEAD))"`
VERSION=`echo $VERSION|sed s:/:-:g`

cd ../../..
rm -rf build
mkdir build
cd build
cmake -GNinja\
    -DCMAKE_PREFIX_PATH=/usr/local/Cellar/qt/5.15.0 \
    -DLIBFIVE_CCACHE_BUILD=ON \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.12  ..
rm -rf $APP studio/$APP
ninja clean
ninja

# Copy to a new location before modifying, so that the built app doesn't
# get modified and future builds don't misbehave due to duplicate frameworks
cp -r studio/$APP $APP

# Pull out framework paths info with otool
MACDEPLOYQT=`otool -L $APP/Contents/MacOS/$EXE | sed -n -e "s:\(.*\)lib/QtCore.*:\1/bin/macdeployqt:gp"`
GUILE_SCM=`otool -L $APP/Contents/MacOS/$EXE | sed -n -e "s:lib/libguile.*:share/guile/3.0/:gp"`
GUILE_CCACHE=`otool -L $APP/Contents/MacOS/$EXE | sed -n -e "s:lib/libguile.*:lib/guile/3.0/ccache/:gp"`

$MACDEPLOYQT $APP

# Delete unused Qt plugins
cd $APP/Contents/PlugIns
rm -rf accessible audio imageformats mediaservice playlistformats position printsupport qml1tooling sensorgestures sensors bearer

fix_qt () {
    echo "Fixing Qt for $1"
    for LIB in $( otool -L $1 | sed -n -e "s:\(.*Qt.*.framework[^ ]*\).*:\1:gp" )
    do
        RENAMED=`echo $LIB | sed -n -e "s:.*\(Qt.*\)\.framework.*:@executable_path/../Frameworks/\1.framework/Versions/5/\1:gp"`
        install_name_tool -change $LIB $RENAMED $1
    done
}

# Remap platform links
cd platforms
fix_qt libqcocoa.dylib

# Delete unused Qt frameworks (wow, there's a lot of them)
cd ../../Frameworks
rm -rf \
    Qt3DCore.framework \
    Qt3DRender.framework \
    QtDeclarative.framework \
    QtLocation.framework \
    QtMultimedia.framework \
    QtMultimediaWidgets.framework \
    QtNetwork.framework \
    QtPdf.framework \
    QtPositioning.framework \
    QtQml.framework \
    QtQmlModels.framework \
    QtQuick.framework \
    QtScript.framework \
    QtSensors.framework \
    QtSerialBus.framework \
    QtSerialPort.framework \
    QtSql.framework \
    QtSvg.framework \
    QtVirtualKeyboard.framework \
    QtXmlPatterns.framework

# Clean up remaining Qt frameworks
for LIB in $( ls|sed -n -e "s:\(Qt.*\)\.framework:\1:gp" )
do
    fix_qt $LIB.framework/Versions/Current/$LIB
done

# Deploy Guile library (including both bare scm files and precompiled,
# on the assumption that stuff which is useful for this application
# will have been pre-compiled at least one)
cd ../Resources
mkdir -p guile/scm
mkdir -p guile/ccache
cp -r $GUILE_SCM guile/scm/
cp -r $GUILE_CCACHE guile/ccache/
cp -r ../../../../libfive/bind/guile/libfive guile/scm

# Update release number in Info.plist
cd ../../..
cp ../studio/deploy/mac/Info.plist $APP/Contents/Info.plist
sed -i "" "s:0\.0\.0:$VERSION:g" $APP/Contents/Info.plist

# Build icon and deploy into bundle
inkscape --export-filename=icon512.png ../studio/deploy/icon/icon.svg
convert icon512.png -resize 256x256 icon256.png
convert icon512.png -resize 128x128 icon128.png
convert icon512.png -resize 32x32 icon32.png
convert icon512.png -resize 16x16 icon16.png
png2icns studio.icns icon512.png icon256.png icon128.png icon32.png icon16.png
mv studio.icns $APP/Contents/Resources/studio.icns
rm icon512.png icon256.png icon128.png icon32.png icon16.png

wargarble
# Create the disk image
rm -rf deploy $EXE.dmg
mkdir deploy
cp ../README.md ./deploy/README.txt
cp -r ../studio/examples ./deploy/examples
mv $APP ./deploy
mkdir deploy/.Trash
hdiutil create $EXE.dmg -volname "$EXE $VERSION" -srcfolder deploy
rm -rf deploy
mv $EXE.dmg ..
