#!bin/bash/

# Exit on any error
set -e

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or use sudo"
  exit 1
fi

# Variables
K8S_VERSION="1.28.3-00"  # Specify desired Kubernetes version
CONTAINERD_VERSION="1.7.7"  # Specify containerd version
NODE_TYPE=$1  # 'master' or 'worker' (default to master if not specified)

# Log function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Step 1: Update and install dependencies
log "Updating system and installing dependencies"
apt-get update && apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Step 2: Install containerd
log "Installing containerd"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y containerd.io=$CONTAINERD_VERSION-1

# Configure containerd
log "Configuring containerd"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Enable SystemdCgroup for Kubernetes
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Step 3: Disable swap
log "Disabling swap"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 4: Load kernel modules
log "Loading kernel modules"
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Step 5: Set sysctl parameters
log "Setting sysctl parameters"
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# Step 6: Install Kubernetes components
log "Installing Kubernetes components"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
apt-mark hold kubelet kubeadm kubectl

# Step 7: Initialize Kubernetes cluster (only for master node)
if [ "$NODE_TYPE" = "master" ]; then
  log "Initializing Kubernetes control plane"
  kubeadm init --pod-network-cidr=10.244.0.0/16 --kubernetes-version=v1.28.3

  # Set up kubeconfig for the root user
  log "Setting up kubeconfig"
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config

  # Install Flannel CNI
  log "Installing Flannel network plugin"
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.22.0/Documentation/kube-flannel.yml

  # Allow scheduling on control plane (single-node setup)
  log "Tainting control plane to allow scheduling"
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

  log "Kubernetes cluster initialized. Join command for workers:"
  kubeadm token create --print-join-command
else
  log "Worker node setup complete. Run the join command provided by the master node."
fi

log "Installation complete!"
