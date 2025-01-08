ARG CUDA_VERSION=11.8.0

# base
FROM nvidia/cuda:${CUDA_VERSION}-cudnn8-devel-ubuntu22.04 AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root

ARG PYTHON_VERSION=3.10
ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_DRIVER_CAPABILITIES=all

# jupyter docker-stacks-foundation
RUN apt-get update --fix-missing && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    bash-completion \
    libgl1 \
    libgl1-mesa-glx \
    libegl-dev \
    libegl1 \
    libxrender1 \
    libglib2.0-0 \
    ffmpeg \
    libgtk2.0-dev \
    pkg-config \
    libvulkan-dev \
    libgles2 \
    libglvnd0 \
    libglx0 \
    sudo \
    bzip2 zip unzip \
    ca-certificates \
    locales \
    tini \
    vim \
    tree \
    libldap2-dev libsasl2-dev libssl-dev \
    libtesseract-dev tesseract-ocr tesseract-ocr-kor tesseract-ocr-eng \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* \
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

WORKDIR /tmp
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

RUN mamba install -y scikit-build cmake 'numpy<2.0.0' && mamba clean --all -f -y
RUN git clone --recursive https://github.com/opencv/opencv-python.git && \
    cd opencv-python && \
    ENABLE_CONTRIB=1 python setup.py bdist_wheel -- \
	-DWITH_CUDA=ON \
	-DWITH_CUDDN=ON \
	-DOPENCV_DNN_CUDA=ON \
	-DENABLE_FAST_MATH=1 \
	-DCUDA_FAST_MATH=1 \
	-DWITH_CUBLAS=1 \
	-DCUDA_ARCH_BIN=8.6 -- \
	-j $(nproc) && \
    cd dist && \
    target_file=$(ls | head -n 1) && \
    python -m pip install --upgrade $target_file && \
    rm -rf /tmp/opencv-python

COPY keras2.requirements.txt /tmp
RUN pip install --no-cache --no-user -r /tmp/keras2.requirements.txt && rm /tmp/keras2.requirements.txt

COPY requirements-pip.txt /tmp
RUN pip install --no-cache --no-user -r /tmp/requirements-pip.txt && rm /tmp/requirements*.txt

COPY requirements-jupyter.txt /tmp
RUN mamba install -y --file /tmp/requirements-jupyter.txt && mamba clean --all -f -y && rm /tmp/requirements*.txt

WORKDIR /workspace

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

COPY keras2.requirements-post.txt /tmp
RUN pip install --no-cache --no-user -r /tmp/keras2.requirements-post.txt && rm /tmp/keras2.requirements*.txt
