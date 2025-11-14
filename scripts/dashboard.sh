#!/bin/bash
#
# Deploys the Kubernetes dashboard using Helm with NodePort when enabled in settings.yaml

set -euxo pipefail

config_path="/vagrant/configs"

DASHBOARD_VERSION=$(grep -E '^\s*dashboard:' /vagrant/settings.yaml | sed -E -e 's/[^:]+: *//' -e 's/\r$//')

if [ -n "${DASHBOARD_VERSION}" ]; then
  # Wait for metrics server to be ready
  while sudo -i -u vagrant kubectl get pods -A -l k8s-app=metrics-server | awk 'split($3, a, "/") && a[1] != a[2] { print $0; }' | grep -v "RESTARTS"; do
    echo 'Waiting for metrics server to be ready...'
    sleep 5
  done
  echo 'Metrics server is ready. Installing dashboard...'

  # Install Helm if not already installed
  if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  # Add the Kubernetes Dashboard Helm repository
  echo "Adding Kubernetes Dashboard Helm repository..."
  sudo -i -u vagrant helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
  sudo -i -u vagrant helm repo update

  # Install/upgrade the Kubernetes Dashboard with NodePort on 30443 for HTTPS
  echo "Installing Kubernetes Dashboard version ${DASHBOARD_VERSION} with NodePort..."
  sudo -i -u vagrant helm upgrade --install kubernetes-dashboard \
    kubernetes-dashboard/kubernetes-dashboard \
    --create-namespace \
    --namespace kubernetes-dashboard \
    --version "${DASHBOARD_VERSION}" \
    --set kong.proxy.type=NodePort \
    --set kong.proxy.https.enabled=true \
    --set kong.proxy.https.nodePort=30443 \
    --set kong.proxy.http.enabled=false

  # Wait for dashboard to be ready
  echo "Waiting for dashboard pods to be ready..."
  sudo -i -u vagrant kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/instance=kubernetes-dashboard \
    -n kubernetes-dashboard \
    --timeout=300s

  # Create admin user for dashboard access
  echo "Creating the dashboard user..."

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

  # Wait a moment for the service account to be fully created
  sleep 5

  # Generate token using the new TokenRequest API (correct method for Dashboard 7.x)
  echo "Generating admin token..."
  sudo -i -u vagrant kubectl -n kubernetes-dashboard create token admin-user --duration=87600h > "${config_path}/token"

  # Get the control plane IP
  CONTROL_IP=$(grep -E '^\s*control_ip:' /vagrant/settings.yaml | sed -E -e 's/[^:]+: *//' -e 's/\r$//')

  echo ""
  echo "================================================================"
  echo "Kubernetes Dashboard installed successfully!"
  echo "================================================================"
  echo ""
  echo "Access Token (saved to configs/token):"
  cat "${config_path}/token"
  echo ""
  echo "================================================================"
  echo "Dashboard Access URL:"
  echo "================================================================"
  echo ""
  echo "  https://${CONTROL_IP}:30443"
  echo ""
  echo "================================================================"
  echo "Login Instructions:"
  echo "================================================================"
  echo "1. Open your browser and navigate to: https://${CONTROL_IP}:30443"
  echo "2. Accept the self-signed certificate warning:"
  echo "   - Click 'Advanced' or 'Show Details'"
  echo "   - Click 'Proceed to ${CONTROL_IP} (unsafe)' or 'Accept Risk'"
  echo "3. On the login page, select 'Token' authentication method"
  echo "4. Paste the token shown above (or from configs/token file)"
  echo "5. Click 'Sign in'"
  echo ""
  echo "Note: The token is valid for 10 years (87600 hours)"
  echo ""
  echo "If you need a new token, run:"
  echo "  kubectl -n kubernetes-dashboard create token admin-user --duration=87600h"
  echo "================================================================"
fi