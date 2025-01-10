# dev-keras
vscode devcontainer for keras

## envioronment
* nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04
  * rtx-3050
  * cuda-arch-bin=8.6
* python3.10
* numa
  * https://stackoverflow.com/questions/44232898/memoryerror-in-tensorflow-and-successful-numa-node-read-from-sysfs-had-negativ
```bash
for pcidev in $(lspci -D|grep 'VGA compatible controller: NVIDIA'|sed -e 's/[[:space:]].*//'); do echo 0 | sudo  tee -a /sys/bus/pci/devices/${pcidev}/numa_node; done
```
## image build
```bash
docker build -f keras2.Dockerfile -t dev-keras2:gpu . && \
#docker build -f keras3.Dockerfile -t dev-keras3:cpu . && \
docker build -f keras3.Dockerfile -t dev-keras3:gpu --build-arg BACKEND=-gpu .
```
