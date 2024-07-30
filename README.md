# dev-keras
vscode devcontainer for keras

## envioronment
* nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04
  * rtx-3050
  * cuda-arch-bin=8.6
* mamba channel conda-forge
* python3.10
* opencv-4.7.0 source build
* keras2 or 3, jax, torch

## image build
```bash
docker build -f keras2.Dockerfile -t dev-keras2:latest . && \
docker build -f keras3.Dockerfile -t dev-keras3:jax --build-arg 'BACKEND=-jax-cuda' . && \
docker build -f keras3.Dockerfile -t dev-keras3:torch --build-arg 'BACKEND=-torch-cuda' . && \
docker build -f keras3.Dockerfile -t dev-keras3:tensorflow --build-arg 'BACKEND=-tensorflow-cuda' . 
```
