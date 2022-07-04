#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

export GIT_ROOT="$(pwd)"
mkdir -p "${GIT_ROOT}/artifacts"

# dependencies
alias sudo="$(which sudo)"
$sudo apt-get update -q -y
$sudo apt-get --no-install-recommends install -y curl ca-certificates gnupg2 curl sudo
curl --insecure -fSL "https://repo.uwucocoa.moe/pgp.key" | apt-key add -
echo "deb [arch=${ARCH_NAME}] https://repo.uwucocoa.moe/ stable main" | tee /etc/apt/sources.list.d/uwucocoa.list
alias sudo="$(which sudo)"
$sudo apt-get update -q -y
$sudo apt-get install -y wget gcc g++ make cmake-uwu build-essential git \
              automake autoconf pkg-config bc m4 unzip zip curl locales \
              python3 python3-pip python3-dev libgmp-dev
MAKEFLAGS="-j$(nproc)" pip3 install --user pyyaml setuptools future six requests \
              dataclasses numpy typing_extensions

# download pytorch source
wget "https://github.com/pytorch/pytorch/releases/download/v${TORCH_VER}/pytorch-v${TORCH_VER}.tar.gz" -O "pytorch-v${TORCH_VER}.tar.gz"
tar xf "pytorch-v${TORCH_VER}.tar.gz"
cd "pytorch-v${TORCH_VER}"

# disable XNNPACK for 32-bit builds
export CMAKE_OPTIONS='-D CMAKE_BUILD_TYPE=Release'
case "${ARCH}" in
    armv7*)
        # disable XNNPACK on armhf (even when a RPi 4 running in 32bit mode)
        # as it uses some arm instructions that are not supported by the RPi CPU
        CMAKE_OPTIONS='-D USE_XNNPACK=OFF' ;;
    aarch64)
        # https://github.com/pytorch/pytorch/blob/master/scripts/build_raspbian.sh
        CMAKE_OPTIONS='-DCAFFE2_CPU_FLAGS="-mfpu=neon -mfloat-abi=hard"' ;;
    *)
    ;;
esac

rm -rf build
mkdir -p build && cd build
cmake -D CMAKE_BUILD_TYPE=Release "${CMAKE_OPTIONS}" \
    -D CMAKE_INSTALL_PREFIX="/usr/local" \
    -D BUILD_PYTHON=False \
    -D BUILD_TEST=False \
    -D USE_FFMPEG=OFF \
    -D USE_OPENCV=OFF \
    -D USE_OPENMP=ON \
    -D USE_CUDA=OFF \
    -D USE_NUMPY=ON \
    -D USE_ROCM=OFF \
    -D CMAKE_PREFIX_PATH="$(python3 -c 'import site as s; print(s.getusersitepackages())')" \
    -D NUMPY_INCLUDE_DIR="$(python3 -c 'import numpy as n; print(n.get_include())')" \
    -D PYTHON_EXECUTABLE="$(which python3)" \
    -D PYTHON_INCLUDE_DIR="$(python3 -c 'import distutils.sysconfig as s; print(s.get_python_inc())')"
make -j"$(nproc)"

export DESTDIR="/artifacts/${ARCH_NAME}/libtorch"
mkdir -p "${DESTDIR}"
make DESTDIR="${DESTDIR}" install

export ARCHIVE_FILE_NAME="libtorch-${TORCH_VER}-${ARCH}" 
cd "/artifacts/${ARCH_NAME}/libtorch/usr"
mv local libtorch
dpkg -L libgomp1 | grep libgomp.so | xargs -I {}  cp -a {} "./libtorch/lib"
tar -czf "${ARCHIVE_FILE_NAME}.tar.gz" libtorch
zip --symlinks -r -9 "${ARCHIVE_FILE_NAME}.zip" libtorch

mv "${ARCHIVE_FILE_NAME}.tar.gz" "${GIT_ROOT}/artifacts/${ARCHIVE_FILE_NAME}.tar.gz"
mv "${ARCHIVE_FILE_NAME}.zip" "${GIT_ROOT}/artifacts/${ARCHIVE_FILE_NAME}.zip"
