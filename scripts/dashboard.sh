#!/bin/bash
#
# Deploys the Kubernetes dashboard when enabled in settings.yaml
# Uses Helm for v7.x installations

set -euxo pipefail

config_path="/vagrant/configs"

DASHBOARD_VERSION=$(grep -E '^\s*dashboard_helm:' /vagrant/settings.yaml | sed -E -e 's/[^:]+: *//' -e 's/\r$//')
if [ -n "${DASHBOARD_VERSION}" ]; then
  while sudo -i -u vagrant kubectl get pods -A -l k8s-app=metrics-server | awk 'split($3, a, "/") && a[1] != a[2] { print $0; }' | grep -v "RESTARTS"; do
    echo 'Waiting for metrics server to be ready...'
    sleep 5
  done
  echo 'Metrics server is ready. Installing dashboard...'

  # Install Helm if not present
  if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  # Add Kubernetes Dashboard Helm repository
  echo "Adding Kubernetes Dashboard Helm repository..."
  sudo -i -u vagrant helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
  sudo -i -u vagrant helm repo update

  # Install Kubernetes Dashboard using Helm
  echo "Installing Kubernetes Dashboard v${DASHBOARD_VERSION} using Helm..."
  sudo -i -u vagrant helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --create-namespace \
    --namespace kubernetes-dashboard \
    --version ${DASHBOARD_VERSION} \
    --set=service.externalPort=443 \
    --set=replicaCount=1 \
    --set=extraArgs={--enable-skip-login} \
    --set=protocolHttp=true \
    --set=service.type=ClusterIP

  # Wait for dashboard pods to be ready
  echo "Waiting for dashboard pods to be ready..."
  sleep 10
  sudo -i -u vagrant kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kubernetes-dashboard -n kubernetes-dashboard --timeout=300s || true

  # Create admin user service account
  echo "Creating admin user..."
  cat <<EOF | sudo -i -u vagrant kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: admin-user
---
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

  # Wait for secret to be created
  sleep 5

  # Get and save the token
  echo "Retrieving admin token..."
  sudo -i -u vagrant kubectl -n kubernetes-dashboard get secret/admin-user -o go-template="{{.data.token | base64decode}}" > "${config_path}/token"

  echo ""
  echo "=========================================="
  echo "Kubernetes Dashboard installed successfully!"
  echo "=========================================="
  echo ""
  echo "The admin token has been saved to: configs/token"
  echo ""
  echo "Token:"
  cat "${config_path}/token"
  echo ""
  echo ""
  echo "To access the dashboard:"
  echo "1. Run: kubectl proxy"
  echo "2. Open: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard-kong-proxy:443/proxy/"
  echo "3. Use the token above to log in"
  echo ""
  echo "Or use port-forward:"
  echo "kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443"
  echo "Then open: https://localhost:8443"
  echo ""
fi
