#!/bin/bash

echo "-----------------------------------------------------------------------------------------------------------------------------"
echo "Checking Kubernetes Cluster Connectivity"

if kubectl cluster-info >/dev/null 2>&1; then
    
    echo "Cluster is reachable."

else

    echo "Cluster not found. Creating one..."
    kind create cluster --config 00_00_cluster/kind-3node.yaml

     echo "Verifying"
     kubectl cluster-info

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Checking Metrics Server"


if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    
    echo "Metrics Server is already installed."

else

    echo "Metrics Server not found. Installing..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml


    echo "---------------------------------------------------------"
    echo "Patching Metrics Server"

    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

    echo "---------------------------------------------------------"
    echo "Waiting for Metrics Server rollout..."

    kubectl rollout status deployment/metrics-server -n kube-system --timeout=3m

    echo "---------------------------------------------------------"
    echo "Testing Metrics Server"

    kubectl top nodes || true

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Check if NGINX Ingress Controller is present"

if kubectl get deployment -n ingress-nginx ingress-nginx-controller >/dev/null 2>&1; then
    
    echo "NGINX Ingress Controller is installed"

else

    echo "NGINX Ingress Controller is not installed, Installing it ....."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

    echo "Waiting for NGINX Ingress Controller to be ready..."
    kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s

    echo "Verifying"
    kubectl get deployment -n ingress-nginx ingress-nginx-controller

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Check if cert-manager is present"

if kubectl get cert-manager >/dev/null 2>&1; then
    
    echo "cert-manager is installed"

else

    echo "cert-manager is not installed, Installing it ....."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

    echo "Verifying"
    kubectl get deployment -n cert-manager cert-manager

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Check if Calico is present"

if kubectl get deploy calico-kube-controllers -n kube-system >/dev/null 2>&1; then
    
    echo "Calico is installed"

else

    echo "Calico is not installed, Installing it ....."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

    echo "Verifying"
    kubectl get deploy calico-kube-controllers -n kube-system

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

echo "Checking Helm"

if command -v helm >/dev/null 2>&1; then
    
    echo "Helm is already installed."

else

    echo "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    echo "Verifying Helm..."
    helm version

fi

echo "-----------------------------------------------------------------------------------------------------------------------------"

helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm upgrade --install kyverno kyverno/kyverno --namespace kyverno --create-namespace