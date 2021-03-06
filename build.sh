#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

if [ -z "${1}"]; then
    echo "Please specify the torch version"
    exit 1
else
    export TORCH_VER="${1}"
fi
echo "Torch version: ${TORCH_VER}"

if [ -z "${2}"]; then
    echo "Please specify the CPU arch"
    exit 1
else
    export ARCH="${2}"
fi
echo "arch: ${ARCH}${ARCH_NAME}"

if [ -z "${3}"]; then
    echo "Please specify the CPU arch name for the deb package"
    exit 1
else
    export ARCH_NAME="${3}"
fi
echo "arch_name: ${ARCH_NAME}"

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
              python3 python3-pip python3-dev libgmp-dev libopenblas-openmp-dev
MAKEFLAGS="-j$(nproc)" pip3 install --user pyyaml setuptools future six requests \
              dataclasses numpy typing_extensions

# download pytorch source
case "${ARCH_NAME}" in
    armhf)
        wget --no-check-certificate "https://github.com/pytorch/pytorch/releases/download/v${TORCH_VER}/pytorch-v${TORCH_VER}.tar.gz" -O "pytorch-v${TORCH_VER}.tar.gz"
    ;;
    *)
        wget "https://github.com/pytorch/pytorch/releases/download/v${TORCH_VER}/pytorch-v${TORCH_VER}.tar.gz" -O "pytorch-v${TORCH_VER}.tar.gz"
    ;;
esac
tar xf "pytorch-v${TORCH_VER}.tar.gz"
cd "pytorch-v${TORCH_VER}"

# disable XNNPACK for 32-bit builds
export CMAKE_OPTIONS='-D CMAKE_BUILD_TYPE=Release'
case "${ARCH_NAME}" in
    armhf)
        # disable XNNPACK on armhf (even when a RPi 4 running in 32bit mode)
        # as it uses some arm instructions that are not supported by the RPi CPU
        CMAKE_OPTIONS='-D USE_XNNPACK=OFF' ;;
    arm64)
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
    -D USE_BLAS=ON \
    -D USE_CUDA=OFF \
    -D USE_NUMPY=ON \
    -D USE_ROCM=OFF \
    -D CMAKE_PREFIX_PATH="$(python3 -c 'import site as s; print(s.getusersitepackages())')" \
    -D NUMPY_INCLUDE_DIR="$(python3 -c 'import numpy as n; print(n.get_include())')" \
    -D PYTHON_EXECUTABLE="$(which python3)" \
    -D PYTHON_INCLUDE_DIR="$(python3 -c 'import distutils.sysconfig as s; print(s.get_python_inc())')" \
    ..
make -j"$(nproc)"

export DESTDIR="${GIT_ROOT}/libtorch-install/${ARCH_NAME}/libtorch"
mkdir -p "${DESTDIR}"
make DESTDIR="${DESTDIR}" install

export ARCHIVE_FILE_NAME="libtorch-${TORCH_VER}-${ARCH}"
cd "${GIT_ROOT}/libtorch-install/${ARCH_NAME}/libtorch/usr"
mv local libtorch
dpkg -L libgomp1 | grep libgomp.so | xargs -I {}  cp -a {} "./libtorch/lib"
dpkg -L libopenblas-openmp-dev | grep -E '*.so' | xargs -I {}  cp -a {} "./libtorch/lib"
dpkg -L libopenblas0-openmp | grep -E '*.so' | xargs -I {}  cp -a {} "./libtorch/lib"
tar -czf "${ARCHIVE_FILE_NAME}.tar.gz" libtorch

mv "${ARCHIVE_FILE_NAME}.tar.gz" "${GIT_ROOT}/artifacts/${ARCHIVE_FILE_NAME}.tar.gz"
echo "Build finished successfully: ${GIT_ROOT}/artifacts/${ARCHIVE_FILE_NAME}.tar.gz"
