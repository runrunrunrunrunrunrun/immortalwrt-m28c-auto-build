#!/bin/bash
id
df -h
free -h
cat /proc/cpuinfo

IMM_REPO_DIR="immortalwrt"
IMM_REPO_URL="https://github.com/immortalwrt/immortalwrt"
IMM_REPO_BRANCH="openwrt-25.12"

is_valid_immortalwrt_repo() {
    local repo_dir="$1"

    [ -d "$repo_dir/.git" ] || return 1
    [ -f "$repo_dir/feeds.conf.default" ] || return 1
    [ -f "$repo_dir/scripts/feeds" ] || return 1

    local origin_url
    origin_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
    [ "$origin_url" = "$IMM_REPO_URL" ] || return 1

    return 0
}

echo "update submodules"
git submodule update --init --recursive --remote || { echo "submodule update failed"; exit 1; }

if [ -d "$IMM_REPO_DIR" ]; then
    echo "repo dir exists"
    if ! is_valid_immortalwrt_repo "$IMM_REPO_DIR"; then
        echo "repo dir is not a valid ImmortalWrt tree, recloning"
        rm -rf "$IMM_REPO_DIR"
    fi
fi

if [ ! -d "$IMM_REPO_DIR" ]; then
    echo "repo dir not exists"
    git clone -b "$IMM_REPO_BRANCH" --single-branch --filter=blob:none "$IMM_REPO_URL" "$IMM_REPO_DIR" || { echo "git clone failed"; exit 1; }
fi

git -C "$IMM_REPO_DIR" fetch origin "$IMM_REPO_BRANCH" || { echo "git fetch failed"; exit 1; }
git -C "$IMM_REPO_DIR" checkout "$IMM_REPO_BRANCH" || { echo "git checkout failed"; exit 1; }
git -C "$IMM_REPO_DIR" reset --hard "origin/$IMM_REPO_BRANCH" || { echo "git reset failed"; exit 1; }
git -C "$IMM_REPO_DIR" clean -fd || { echo "git clean failed"; exit 1; }

if ! is_valid_immortalwrt_repo "$IMM_REPO_DIR"; then
    echo "repo validation failed after sync"
    exit 1
fi

cd "$IMM_REPO_DIR" || { echo "cd failed"; exit 1; }

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
