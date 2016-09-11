#!/bin/bash
# make a bin-snapshot.sh library source tree from a source build tree for raspberry pi
mkdir -p snap/{cd,iup}
cp cd/lib/Linux44_arm/*.so snap/cd
cp cd/lib/Linux44_arm/Lua52/*.so snap/cd
cp cd/COPYRIGHT snap/cd
cp iup/lib/Linux44_arm/*.so snap/iup
cp iup/lib/Linux44_arm/Lua52/*.so snap/iup
cp iup/COPYRIGHT snap/iup
