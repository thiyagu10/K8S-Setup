##################################################################################################
#	Create the K8S Cluster and deploy the NGINX Webserver on it                              #
##################################################################################################

#! /bin/bash
sed -i '/PermitRootLogin/s/no/yes/' /etc/ssh/sshd_config
sed -i '/PasswordAuthentication/s/no/yes/' /etc/ssh/sshd_config
systemctl restart sshd
timedatectl set-timezone Asia/Kolkata
apt update -y
apt install wget -y
apt install tcpdump -y
apt install net-tools -y
wget -qO- https://get.docker.com/ | sh
sudo swapoff -a

lsmod | grep br_netfilter
sudo modprobe br_netfilter
lsmod | grep br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward=1
EOF
sudo sysctl --system

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl


### For Flannel CNI on Master Node
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml
kubectl get nodes
kubectl get pods --all-namespaces


### On Worker Node
kubeadm join 10.10.50.23:6443 --token d93rwm.yvtvuzsyeo9rgktw \
        --discovery-token-ca-cert-hash sha256:01bdc1ba7b34927da0923023b0e87292dd7e11f3fa860520d0d85ba9edc189dd
kubectl get nodes


### To Install K8S Dashboard UI
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml
kubectl proxy

### Create Namespace
kubectl create namespace blr-websvr-cl01
kubectl get namespace


### Deploy the NGINX Webserver Cluster
kubectl apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml				## Creates Only Internal POD OR below yaml file ##
kubectl apply -f nginx-deployment.yaml --namespace=blr-websvr-cl01
kubectl get deployments --namespace=blr-websvr-cl01
## Exposes the deployed Webserver ##
kubectl expose deployment nginx-webcluster --type=LoadBalancer --name=nginx-web-server	--namespace=blr-websvr-cl01
kubectl get services --namespace=blr-websvr-cl01
kubectl rollout status deployment nginx-webcluster --namespace=blr-websvr-cl01
kubectl get pods --show-labels
kubectl get deployment nginx-webcluster --namespace=blr-websvr-cl01
kubectl describe deployments --namespace=blr-websvr-cl01

kubectl get all ### Get all deployments

### Access the NGIX Webserver with the Port provide on the Services
http://<public-IP-masterNode>:<portNo-in-service>/

### Modify the NGINX Webserver Cluster
kubectl set image deployment/nginx-deployment nginx=nginx:1.161
kubectl edit deployment nginx-webcluster

### Delete the NGINX Webserver Cluster
kubectl get services
kubectl delete service nginx-web-server
kubectl get services
kubectl get deployments
kubectl delete deployment nginx-webcluster
kubectl get deployments

##################################################################################################
