#!/bin/bash
id
df -h
free -h
cat /proc/cpuinfo

echo "update submodules"
git submodule update --init --recursive --remote || { echo "submodule update failed"; exit 1; }

if [ -d "immortalwrt" ]; then
    echo "repo dir exists"
    cd immortalwrt
    git pull || { echo "git pull failed"; exit 1; }
    git reset --hard HEAD
    git clean -fd
else
    echo "repo dir not exists"
    git clone -b openwrt-25.12 --single-branch --filter=blob:none "https://github.com/immortalwrt/immortalwrt" || { echo "git clone failed"; exit 1; }
    cd immortalwrt
fi

echo "add feeds"
cat feeds.conf.default > feeds.conf
echo "" >> feeds.conf
echo "src-git momo https://github.com/nikkinikki-org/OpenWrt-momo.git" >> feeds.conf
echo "src-git qmodem https://github.com/FUjr/QModem" >> feeds.conf

echo "update files"
rm -rf files
cp -r ../files .

echo "update feeds"
./scripts/feeds update -a || { echo "update feeds failed"; exit 1; }
echo "install feeds"
./scripts/feeds install -a || { echo "install feeds failed"; exit 1; }
if grep -q "^src-git[[:space:]]\+momo[[:space:]]" feeds.conf; then
    ./scripts/feeds install -a -f -p momo || { echo "install momo feeds failed"; exit 1; }
else
    echo "momo feed not configured, skip momo install"
fi
if grep -q "^src-git[[:space:]]\+qmodem[[:space:]]" feeds.conf; then
    ./scripts/feeds install -a -f -p qmodem || { echo "install qmodem feeds failed"; exit 1; }
else
    echo "qmodem feed not configured, skip qmodem install"
fi

if [ -L "package/zz-packages" ]; then
    echo "package/zz-packages is already a symlink"
else
    if [ -d "package/zz-packages" ]; then
        echo "package/zz-packages directory exists, removing it"
        rm -rf package/zz-packages
    fi
    ln -s ../../zz-packages package/zz-packages
    echo "Created symlink package/zz-packages -> ../../zz-packages"
fi

bash -c "cd package/zz-packages/theme/luci-theme-alpha && git reset --hard && sed -i 's/^\(PKG_VERSION:=[^[:space:]]*\)-beta$/\1/' Makefile"

echo "Fix Rust build remove CI LLVM download"
if [ -f "feeds/packages/lang/rust/Makefile" ]; then
    sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "feeds/packages/lang/rust/Makefile"
fi
