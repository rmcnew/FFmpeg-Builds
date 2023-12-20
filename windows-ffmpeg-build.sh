#!/bin/bash
cd src
make distclean
cd ..
set -- "win64" "nonfree" "6.1"
set -xe
shopt -s globstar
cd "$(dirname "$0")"
source util/podman-vars.sh

# ensure group name is defined for extra version
if [[ -z "${FF_GROUP_NAME}" ]]; then
    echo "Required environment variable FF_GROUP_NAME is not defined"
    exit 1
fi

# ensure feature name is defined for extra version
if [[ -z "${FF_FEATURE_NAME}" ]]; then
    echo "Required environment variable FF_FEATURE_NAME is not defined"
    exit 1
fi

get_output() {
    (
        SELF="$1"
        source $1
        if ffbuild_enabled; then
            ffbuild_$2 || exit 0
        else
            ffbuild_un$2 || exit 0
        fi
    )
}

source "variants/${TARGET}-${VARIANT}.sh"

for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

export FFBUILD_PREFIX="$(podman run --rm --security-opt label=disable "$IMAGE" bash -c 'echo $FFBUILD_PREFIX')"

for script in scripts.d/**/*.sh; do
    FF_CONFIGURE+=" $(get_output $script configure)"
    FF_CFLAGS+=" $(get_output $script cflags)"
    FF_CXXFLAGS+=" $(get_output $script cxxflags)"
    FF_LDFLAGS+=" $(get_output $script ldflags)"
    FF_LDEXEFLAGS+=" $(get_output $script ldexeflags)"
    FF_LIBS+=" $(get_output $script libs)"
done

FF_CONFIGURE="$(xargs <<< "$FF_CONFIGURE") --samples=fate-suite/"
FF_CFLAGS="$(xargs <<< "$FF_CFLAGS")"
FF_CXXFLAGS="$(xargs <<< "$FF_CXXFLAGS")"
FF_LDFLAGS="$(xargs <<< "$FF_LDFLAGS")"
FF_LDEXEFLAGS="$(xargs <<< "$FF_LDEXEFLAGS")"
FF_LIBS="$(xargs <<< "$FF_LIBS")"

TESTFILE="uidtestfile"
rm -f "$TESTFILE"
podman run --rm --security-opt label=disable -v "$PWD:/uidtestdir" "$IMAGE" touch "/uidtestdir/$TESTFILE"
DOCKERUID="$(stat -c "%u" "$TESTFILE")"
rm -f "$TESTFILE"
[[ "$DOCKERUID" != "$(id -u)" ]] && UIDARGS=( -u "$(id -u):$(id -g)" ) || UIDARGS=()

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

    ./configure --prefix=/ffbuild/prefix --pkg-config-flags="--static" \$FFBUILD_TARGET_FLAGS $FF_CONFIGURE \
        --extra-cflags='$FF_CFLAGS' --extra-cxxflags='$FF_CXXFLAGS' \
        --extra-ldflags='$FF_LDFLAGS' --extra-ldexeflags='$FF_LDEXEFLAGS' --extra-libs='$FF_LIBS' \
        --extra-version="${FF_GROUP_NAME}_${FF_FEATURE_NAME}"
    make -j\$(nproc)
    make install install-doc
    # FATE tests run the created binaries against test files
    # We can't run the created binaries unless the build platform and target platform match
    # Comment out the FATE run since the builder container cannot run Windows binaries
    # make fate
EOF

[[ -t 1 ]] && TTY_ARG="-t" || TTY_ARG=""

podman run --rm --security-opt label=disable -i $TTY_ARG "${UIDARGS[@]}" -v $PWD/ffbuild:/ffbuild -v "$PWD/src:/ffmpeg" -v "$BUILD_SCRIPT":/build.sh "$IMAGE" bash /build.sh

mkdir -p artifacts
ARTIFACTS_PATH="$PWD/artifacts"
BUILD_NAME="ffmpeg-6.1-$FF_GROUP_NAME-$(date +%F)"

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

