FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04 AS base

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN apt update --fix-missing && \
    apt install -y --no-install-recommends sudo \
        software-properties-common gnupg2 ca-certificates \
        build-essential cmake pkg-config git vim netcat file xvfb \
        wget curl zip unzip bzip2 p7zip gfortran graphviz tree libjsoncpp-dev \
        openjdk-17-jdk libgoogle-glog-dev libeigen3-dev libgflags-dev libsuitesparse-dev \
        libtesseract-dev tesseract-ocr tesseract-ocr-kor tesseract-ocr-eng \
        libjpeg-dev libpng-dev ffmpeg libavcodec-dev libgtkglext1-dev libatlas-base-dev \
        libavformat-dev libswscale-dev libxvidcore-dev libx264-dev libxine2-dev \
        libv4l-dev v4l-utils mesa-utils libgl1-mesa-dri p7zip
RUN apt -y clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# tesseract-ocr
RUN mkdir -p /usr/local/share/tessdata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/kor.traineddata?raw=true" -O /usr/local/share/tessdata/kor.traineddata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/chi_tra.traineddata?raw=true" -O /usr/local/share/tessdata/chi_tra.traineddata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/jpn.traineddata?raw=true" -O /usr/local/share/tessdata/jpn.traineddata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/eng.traineddata?raw=true" -O /usr/local/share/tessdata/eng.traineddata
ENV TESSDATA_PREFIX=/usr/local/share/tessdata

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd -s /bin/bash --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && mkdir -p /home/${USERNAME}/.vscode-server/extensions \
    && chown -R ${USERNAME} /home/${USERNAME}/.vscode-server

# if use video device
RUN usermod -a -G video ${USERNAME}

ENV CONDA_DIR=/opt/conda
ENV PYTHON_VERSION=3.10
RUN mkdir -p ${CONDA_DIR}
ENV PATH=${CONDA_DIR}/bin:$PATH

RUN set -x && \
    arch=$(uname -m) && \
    if [ "${arch}" = "x86_64" ]; then \
        arch="64"; \
    fi && \
    wget "https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-${arch}" -O micromamba && \
    chmod +x micromamba && \
    PYTHON_SPECIFIER="python=${PYTHON_VERSION}" && \
    if [ "${PYTHON_VERSION}" = "default" ]; then PYTHON_SPECIFIER="python"; fi && \
    ./micromamba install \
        --root-prefix="${CONDA_DIR}" \
        --prefix="${CONDA_DIR}" \
        --yes \
        "${PYTHON_SPECIFIER}" \
        'mamba' \
        -c conda-forge && \
    rm micromamba && \
    mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
    conda config --add channels conda-forge && \
    conda config --set channel_priority strict && \
    conda config --remove channels defaults

COPY requirements-base.txt /
RUN mamba install -y --file requirements-base.txt && rm -f /requirements-base.txt
COPY requirements-base-jupyter.txt /
RUN mamba install -y --file /requirements-base-jupyter.txt && rm -f /requirements-base-jupyter.txt
RUN mamba clean --all -f -y

FROM base AS dev-keras2

RUN git clone https://ceres-solver.googlesource.com/ceres-solver && \
    cd ceres-solver && git checkout 2.0.0 && mkdir build && cd build && cmake .. && \
    make -j$(nproc) && make install && ldconfig && \
    cd ../../ && rm -rf ceres-solver

# https://en.wikipedia.org/wiki/CUDA  CUDA_ARCH_BIN 참고
RUN mkdir -p opencv_build && cd opencv_build && \
    git clone --single-branch -b 4.7.0 https://github.com/opencv/opencv_contrib.git && \
    git clone --single-branch -b 4.7.0 https://github.com/opencv/opencv.git && cd opencv && \
    git submodule update --init --recursive && \
    mkdir -p build && cd build && \
    export PYTHON_VERSION="$(${CONDA_DIR}/bin/python --version | cut -d ' ' -f 2)" && \
    export CPLUS_INCLUDE_PATH=${CONDA_DIR}/lib/python${PYTHON_VERSION%.*} && \
    cmake -D CMAKE_BUILD_TYPE=RELEASE \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D INSTALL_C_EXAMPLES=OFF \
    -D INSTALL_PYTHON_EXAMPLES=OFF \
    -D OPENCV_GENERATE_PKGCONFIG=ON \
    -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
    -D BUILD_SHARED_LIBS=OFF \
    -D WITH_TBB=OFF \
    -D WITH_IPP=OFF \
    -D WITH_1394=OFF \
    -D BUILD_WITH_DEBUG_INFO=OFF \
    -D BUILD_DOCS=OFF \
    -D BUILD_TESTS=OFF \
    -D BUILD_PERF_TESTS=OFF \
    -D BUILD_TIFF=ON \
    -D WITH_QT=OFF \
    -D WITH_GTK=ON \
    -D WITH_OPENGL=OFF \
    -D WITH_V4L=ON  \
    -D WITH_LIBV4L=ON \
    -D WITH_FFMPEG=ON \
    -D WITH_XINE=ON \
    -D WITH_GSTREAMER=OFF \
    -D BUILD_NEW_PYTHON_SUPPORT=ON \
    -D BUILD_EXAMPLES=OFF \
    -D PYTHON3_INCLUDE_DIR=${CONDA_DIR}/include/python${PYTHON_VERSION%.*} \
    -D PYTHON3_NUMPY_INCLUDE_DIRS=${CONDA_DIR}/lib/python${PYTHON_VERSION%.*}/site-packages/numpy/core/include \
    -D PYTHON3_PACKAGES_PATH=${CONDA_DIR}/lib/python${PYTHON_VERSION%.*}/site-packages \
    -D PYTHON3_LIBRARY=${CONDA_DIR}/lib/libpython${PYTHON_VERSION%.*}.so \
    -D PYTHON_EXECUTABLE=${CONDA_DIR}/bin/python \
    -D WITH_CUDA=ON \
    -D WITH_CUDNN=ON \
    -D OPENCV_DNN_CUDA=ON \
    -D ENABLE_FAST_MATH=1 \
    -D CUDA_FAST_MATH=1 \
    -D CUDA_ARCH_BIN=8.6 \
    -D WITH_CUBLAS=1 \
    .. && make -j$(nproc) && make install && \
    ln -s /usr/local/lib/pkgconfig/opencv4.pc /usr/share/pkgconfig/ && \
    echo "/usr/local/lib" > /etc/ld.so.conf.d/opencv4.conf && ldconfig && \
    cd ../../ && rm -rf opencv_build

COPY requirements-pip.txt requirements-pip-jupyter.txt requirements-common.txt /
RUN pip install --no-cache --no-user --use-deprecated=legacy-resolver -r /requirements-pip.txt \
    && pip install --no-cache --no-user --use-deprecated=legacy-resolver -r /requirements-pip-jupyter.txt \
    && pip install --no-cache --no-user --use-deprecated=legacy-resolver -r /requirements-common.txt \
    && rm -f /requirements-*.txt
