ARG CUDA_VERSION=11.8.0

# base
FROM nvidia/cuda:${CUDA_VERSION}-cudnn8-devel-ubuntu22.04 AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root

ARG PYTHON_VERSION=3.10.8
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_DRIVER_CAPABILITIES=all

RUN apt-get -y update --fix-missing && \
    apt-get -y install --no-install-recommends \
    sudo software-properties-common gnupg2 ca-certificates \
    build-essential pkg-config git vim netcat file xvfb \
    wget curl zip unzip bzip2 p7zip gfortran graphviz tree libjsoncpp-dev \
    openjdk-17-jdk libgoogle-glog-dev libeigen3-dev libgflags-dev libsuitesparse-dev \
    libtesseract-dev tesseract-ocr tesseract-ocr-kor tesseract-ocr-eng \
    libjpeg-dev libpng-dev ffmpeg libavcodec-dev libgtkglext1-dev libatlas-base-dev \
    libavformat-dev libswscale-dev libxvidcore-dev libx264-dev libxine2-dev \
    libv4l-dev v4l-utils mesa-utils libgl1-mesa-dri p7zip locales \
    libglx-dev libavutil-dev libldap2-dev libsasl2-dev libssl-dev \
    && apt-get -y purge --autoremove && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# tesseract-ocr
RUN mkdir -p /usr/local/share/tessdata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/kor.traineddata?raw=true" -O /usr/local/share/tessdata/kor.traineddata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/chi_tra.traineddata?raw=true" -O /usr/local/share/tessdata/chi_tra.traineddata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/jpn.traineddata?raw=true" -O /usr/local/share/tessdata/jpn.traineddata && \
    wget -q "https://github.com/tesseract-ocr/tessdata_best/blob/main/eng.traineddata?raw=true" -O /usr/local/share/tessdata/eng.traineddata
ENV TESSDATA_PREFIX=/usr/local/share/tessdata

ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=${CONDA_DIR}/bin:${PATH}

RUN set -x && \
    arch=$(uname -m) && \
    if [ "${arch}" == "x86_64" ]; then arch="64"; fi && \
    wget -q "https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-${arch}" -O micromamba && \
    chmod +x micromamba && \
    PYTHON_SPECIFIER="python=${PYTHON_VERSION}" && \
    if [ "${PYTHON_VERSION}" == "default" ]; then PYTHON_SPECIFIER="python"; fi && \
    ./micromamba install \
        -c conda-forge \
        --root-prefix="${CONDA_DIR}" \
        --prefix="${CONDA_DIR}" \
        --yes \
        "${PYTHON_SPECIFIER}" \
        'mamba' 'conda' && \
    rm micromamba && \
    mamba list python | awk '$1 ~ /^python$/{print $1, $2}' >> "${CONDA_DIR}/conda-meta/pinned" && \
    mamba clean --all -f -y

RUN conda config --add channels conda-forge && \
    conda config --set channel_priority strict && \
    conda config --remove channels defaults

FROM base AS base-gpu
ARG CUDA_ARCH_BIN=8.6

RUN mamba install -y scikit-build cmake 'numpy<2.0.0' && mamba clean --all -f -y
RUN git clone --recursive https://github.com/opencv/opencv-python.git && \
    cd opencv-python && \
    ENABLE_CONTRIB=1 python setup.py bdist_wheel -- \
    -DBUILD_EXAMPLES=OFF \
    -DINSTALL_C_EXAMPLES=OFF \
    -DINSTALL_PYTHON_EXAMPLES=OFF \
    -DBUILD_DOCS=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_PERF_TESTS=OFF \
    -DWITH_TBB=OFF \
    -DWITH_IPP=OFF \
    -DWITH_1394=OFF \
    -DWITH_GTK=ON \
    -DWITH_XINE=ON \
    -DWITH_OPENGL=ON \
    -DWITH_CUDA=ON \
    -DWITH_CUDDN=ON \
    -DOPENCV_DNN_CUDA=ON \
    -DENABLE_FAST_MATH=1 \
    -DCUDA_FAST_MATH=1 \
    -DWITH_CUBLAS=1 \
    -DCUDA_ARCH_PTX=${CUDA_ARCH_BIN} \
    -DCUDA_ARCH_BIN=${CUDA_ARCH_BIN} -- \
    -j $(nproc) && \
    cd dist && \
    target_file=$(ls | head -n 1) && \
    python -m pip install --upgrade $target_file && \
    rm -rf opencv-python

COPY requirements-pip.txt /
RUN pip install --no-cache --no-user -r /requirements-pip.txt && rm /requirements*.txt

COPY requirements-jupyter.txt /
RUN mamba install -y --file /requirements-jupyter.txt && mamba clean --all -f -y && rm /requirements*.txt

WORKDIR /workspaces

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd -s /bin/bash --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && mkdir -p /home/${USERNAME}/.vscode-server/extensions \
    && chown -R ${USERNAME} /home/${USERNAME}/.vscode-server

# if use video device
RUN usermod -a -G video ${USERNAME}


# BACKEND: '', '-gpu'
FROM base-gpu AS main
ARG BACKEND

COPY requirements${BACKEND}.txt requirements-common.txt /
RUN pip install --no-cache --no-user -r /requirements${BACKEND}.txt && rm /requirements*.txt

RUN mamba install -y pillow==9.4.0 && mamba clean --all -f -y
