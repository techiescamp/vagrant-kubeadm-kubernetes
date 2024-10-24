
# Vagrantfile and Scripts to Automate Kubernetes Setup using Kubeadm [Practice Environment for CKA/CKAD and CKS Exams]

A fully automated setup for CKA, CKAD, and CKS practice labs is tested on the following systems:

- Windows
- Ubuntu Desktop
- Mac Intel-based systems

If you are MAC Silicon user, Please use the follwing repo.

- [Vagrant Kubeadm Setup on MAC Silicon](https://github.com/techiescamp/vagrant-kubeadm-mac-silicon)

## Kubernetes Certification Voucher (UpTo 40% OFF) 🎉

As part of our commitment to helping the DevOps community save money on Kubernetes Certifications, we continuously update the latest voucher codes from the Linux Foundation

🚀  CKA, CKAD, CKS, or KCNA exam aspirants can **save 35%** today using code **SPOOKY35CT** at https://kube.promo/devops. It is a limited-time offer from the Linux Foundation.

The following are the best bundles to **save 40% (up to $788)** with code **SPOOKY35CT**

- KCNA + KCSA + CKA + CKAD + CKS ($788 Savings): [kube.promo/kubestronaut](https://kube.promo/kubestronaut)
- CKA + CKAD + CKS Exam bundle ($528 Savings): [kube.promo/k8s-bundle](https://kube.promo/k8s-bundle)
- CKA + CKS Bundle ($355 Savings) [kube.promo/bundle](https://kube.promo/bundle)
- KCNA + CKA ( $288 Savings) [kube.promo/kcka-bundle](https://kube.promo/kcna-cka)
- KCSA + CKS Exam Bundle ($229 Savings) [kube.promo/kcsa-cks](https://kube.promo/kcsa-cks)
- KCNA + KCSA Exam Bundle ($203 Savings) [kube.promo/kcna-kcsa](https://kube.promo/kcna-kcsa)

>Note: You have one year of validity to appear for the certification exam after registration

## Setup Prerequisites

- A working Vagrant setup using Vagrant + VirtualBox

Here is the high level workflow.


<p align="center">
  <img src="https://github.com/user-attachments/assets/cc5594b5-42c2-4c56-be21-6441f849f537" width="65%" />
</p>

## Documentation

Current k8s version for CKA, CKAD, and CKS exam: 1.30

The setup is updated with 1.31 cluster version.

Refer to this link for documentation full: https://devopscube.com/kubernetes-cluster-vagrant/


## Prerequisites

1. Working Vagrant setup
2. 8 Gig + RAM workstation as the Vms use 3 vCPUS and 4+ GB RAM

## For MAC/Linux Users

The latest version of Virtualbox for Mac/Linux can cause issues.

Create/edit the /etc/vbox/networks.conf file and add the following to avoid any network-related issues.
<pre>* 0.0.0.0/0 ::/0</pre>

or run below commands

```shell
sudo mkdir -p /etc/vbox/
echo "* 0.0.0.0/0 ::/0" | sudo tee -a /etc/vbox/networks.conf
```

So that the host only networks can be in any range, not just 192.168.56.0/21 as described here:
https://discuss.hashicorp.com/t/vagrant-2-2-18-osx-11-6-cannot-create-private-network/30984/23

## Bring Up the Cluster

To provision the cluster, execute the following commands.

```shell
git clone https://github.com/scriptcamp/vagrant-kubeadm-kubernetes.git
cd vagrant-kubeadm-kubernetes
vagrant up
```
## Set Kubeconfig file variable

```shell
cd vagrant-kubeadm-kubernetes
cd configs
export KUBECONFIG=$(pwd)/config
```

or you can copy the config file to .kube directory.

```shell
cp config ~/.kube/
```

## Install Kubernetes Dashboard

The dashboard is automatically installed by default, but it can be skipped by commenting out the dashboard version in _settings.yaml_ before running `vagrant up`.

If you skip the dashboard installation, you can deploy it later by enabling it in _settings.yaml_ and running the following:
```shell
vagrant ssh -c "/vagrant/scripts/dashboard.sh" controlplane
```

## Kubernetes Dashboard Access

To get the login token, copy it from _config/token_ or run the following command:
```shell
kubectl -n kubernetes-dashboard get secret/admin-user -o go-template="{{.data.token | base64decode}}"
```

Make the dashboard accessible:
```shell
kubectl proxy
```

Open the site in your browser:
```shell
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login
```

## To shutdown the cluster,

```shell
vagrant halt
```

## To restart the cluster,

```shell
vagrant up
```

## To destroy the cluster,

```shell
vagrant destroy -f
```
# Network graph

```
                  +-------------------+
                  |    External       |
                  |  Network/Internet |
                  +-------------------+
                           |
                           |
             +-------------+--------------+
             |        Host Machine        |
             |     (Internet Connection)  |
             +-------------+--------------+
                           |
                           | NAT
             +-------------+--------------+
             |    K8s-NATNetwork          |
             |    192.168.99.0/24         |
             +-------------+--------------+
                           |
                           |
             +-------------+--------------+
             |     k8s-Switch (Internal)  |
             |       192.168.99.1/24      |
             +-------------+--------------+
                  |        |        |
                  |        |        |
          +-------+--+ +---+----+ +-+-------+
          |  Master  | | Worker | | Worker  |
          |   Node   | | Node 1 | | Node 2  |
          |192.168.99| |192.168.| |192.168. |
          |   .99    | | 99.81  | | 99.82   |
          +----------+ +--------+ +---------+
```

This network graph shows:

1. The host machine connected to the external network/internet.
2. The NAT network (K8s-NATNetwork) providing a bridge between the internal network and the external network.
3. The internal Hyper-V switch (k8s-Switch) connecting all the Kubernetes nodes.
4. The master node and two worker nodes, each with their specific IP addresses, all connected to the internal switch.

