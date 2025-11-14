#!/bin/bash
#
# Deploys the Kubernetes dashboard using Helm when enabled in settings.yaml

set -euxo pipefail

config_path="/vagrant/configs"

DASHBOARD_VERSION=$(grep -E '^\s*dashboard:' /vagrant/settings.yaml | sed -E -e 's/[^:]+: *//' -e 's/\r$//')

if [ -n "${DASHBOARD_VERSION}" ]; then
  # Wait for metrics server to be ready
  while sudo -i -u vagrant kubectl get pods -A -l k8s-app=metrics-server | \
    awk 'split($3, a, "/") && a[1] != a[2] { print $0; }' | grep -v "RESTARTS"; do
    echo 'Waiting for metrics server to be ready...'
    sleep 5
  done

  echo 'Metrics server is ready. Installing dashboard...'

  # Install Helm
  echo "Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  # Add the Kubernetes Dashboard Helm repository
  echo "Adding Kubernetes Dashboard Helm repository..."
  sudo -i -u vagrant helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
  sudo -i -u vagrant helm repo update

  # Install/upgrade the Kubernetes Dashboard
  echo "Installing Kubernetes Dashboard version ${DASHBOARD_VERSION}..."
  sudo -i -u vagrant helm upgrade --install kubernetes-dashboard \
    kubernetes-dashboard/kubernetes-dashboard \
    --create-namespace \
    --namespace kubernetes-dashboard \
    --version "${DASHBOARD_VERSION}"

  # Wait for dashboard to be ready
  echo "Waiting for dashboard pods to be ready..."
  sudo -i -u vagrant kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/instance=kubernetes-dashboard \
    -n kubernetes-dashboard \
    --timeout=300s

  # Create admin user
  echo "Creating the dashboard admin user..."

  cat <<EOF | sudo -i -u vagrant kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF

  cat <<EOF | sudo -i -u vagrant kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

  sleep 5

  # Generate token (Dashboard 7.x compatible)
  echo "Generating admin token..."
  sudo -i -u vagrant kubectl -n kubernetes-dashboard create token admin-user --duration=87600h > "${config_path}/token"

  # Get the control plane IP
  CONTROL_IP=$(grep -E '^\s*control_ip:' /vagrant/settings.yaml | sed -E -e 's/[^:]+: *//' -e 's/\r$//')

  echo "Kubernetes Dashboard installed successfully!"

  echo "Access Token (saved to configs/token):"
  cat "${config_path}/token"

  echo "Dashboard Access URL:"
  echo "  https://${CONTROL_IP}:30443"
fi
