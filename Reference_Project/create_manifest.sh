#!/bin/bash

echo "Creating namespace"
kubectl create ns petclinic-dev

echo "Applying manifests"
cd kubernetes-manifest
kubectl apply -f namespace.yml
kubectl apply -f .