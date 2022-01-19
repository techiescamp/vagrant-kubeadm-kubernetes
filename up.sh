#!/bin/bash

set -x
set -euo pipefail

vagrant box update
vagrant up
cp configs/config ~/.kube/config
kubectl cluster-info
kubectl get no -o wide