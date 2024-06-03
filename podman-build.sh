#!/bin/bash
set -xe
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh

source "variants/${TARGET}-${VARIANT}.sh"

for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

TESTFILE="uidtestfile"
rm -f "$TESTFILE"
podman run --rm --security-opt label=disable -v "$PWD:/uidtestdir" "$IMAGE" touch "/uidtestdir/$TESTFILE"
DOCKERUID="$(stat -c "%u" "$TESTFILE")"
rm -f "$TESTFILE"
[[ "$DOCKERUID" != "$(id -u)" ]] && UIDARGS=( -u "$(id -u):$(id -g)" ) || UIDARGS=()
unset TESTFILE

rm -rf ffbuild
mkdir ffbuild

FFMPEG_REPO="${FFMPEG_REPO:-https://github.com/FFmpeg/FFmpeg.git}"
FFMPEG_REPO="${FFMPEG_REPO_OVERRIDE:-$FFMPEG_REPO}"
GIT_BRANCH="${GIT_BRANCH:-master}"
GIT_BRANCH="${GIT_BRANCH_OVERRIDE:-$GIT_BRANCH}"

BUILD_SCRIPT="$(mktemp)"
trap "rm -f -- '$BUILD_SCRIPT'" EXIT

cat <<EOF >"$BUILD_SCRIPT"
    set -xe
    cd /ffbuild
    rm -rf ffmpeg prefix

    cd /ffmpeg

    ./configure --prefix=/ffbuild/prefix --pkg-config-flags="--static" \$FFBUILD_TARGET_FLAGS \$FF_CONFIGURE \
        --extra-cflags="\$FF_CFLAGS" --extra-cxxflags="\$FF_CXXFLAGS" --extra-libs="\$FF_LIBS" \
        --extra-ldflags="\$FF_LDFLAGS" --extra-ldexeflags="\$FF_LDEXEFLAGS" \
        --cc="\$CC" --cxx="\$CXX" --ar="\$AR" --ranlib="\$RANLIB" --nm="\$NM" \
        --extra-version="\$(date +%Y%m%d)"
    make -j\$(nproc) 
    make install install-doc
    # FATE tests run the created binaries against test files
    # We can't run the created binaries unless the build platform and target platform match
    # The builder container is Linux, so it can run the FATE tests
    make fate
EOF

[[ -t 1 ]] && TTY_ARG="-t" || TTY_ARG=""

# save a copy of the ffmpeg source
rm -Rf src
git clone --branch="$GIT_BRANCH" "$FFMPEG_REPO" src
cd src
# get FATE unit tests
rsync -vrltLW --timeout=60  rsync://fate-suite.ffmpeg.org/fate-suite/ fate-suite/
cd ..

podman run --rm --security-opt label=disable -i $TTY_ARG "${UIDARGS[@]}" -v $PWD/ffbuild:/ffbuild -v "$PWD/src:/ffmpeg" -v "$BUILD_SCRIPT":/build.sh "$IMAGE" bash /build.sh

mkdir -p artifacts
ARTIFACTS_PATH="$PWD/artifacts"
BUILD_NAME="ffmpeg-$(src/ffbuild/version.sh src)-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"

mkdir -p "ffbuild/pkgroot/$BUILD_NAME"
package_variant ffbuild/prefix "ffbuild/pkgroot/$BUILD_NAME"

[[ -n "$LICENSE_FILE" ]] && cp "ffbuild/ffmpeg/$LICENSE_FILE" "ffbuild/pkgroot/$BUILD_NAME/LICENSE.txt"

cd ffbuild/pkgroot
if [[ "${TARGET}" == win* ]]; then
    OUTPUT_FNAME="${BUILD_NAME}.zip"
    zip -9 -r "${ARTIFACTS_PATH}/${OUTPUT_FNAME}" "$BUILD_NAME"
else
    OUTPUT_FNAME="${BUILD_NAME}.tar.xz"
    tar cJf "${ARTIFACTS_PATH}/${OUTPUT_FNAME}" "$BUILD_NAME"
fi
cd -

rm -rf ffbuild

if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${OUTPUT_FNAME}" > "${ARTIFACTS_PATH}/${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}.txt"
fi
