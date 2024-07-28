# BACKEND: '', '-jax-cuda', '-torch-cuda', '-tensorflow-cuda'
ARG BASE_CONTAINER=dev-keras2
FROM ${BASE_CONTAINER}
ARG BACKEND

COPY requirements${BACKEND}.txt requirements-common.txt /
RUN pip install --no-cache --no-user -r requirements${BACKEND}.txt && rm -f requirements*.txt
