# K8S node

Installing a K8S node using [scripts from the k3s-host](k3s-host) directory.

## Imaging

Using installimage from the rescue instance.

- `wipefs -fa /dev/nvme*n1`
- `installimage -r no -n hetzner0?`
- Debian bookworm
- `PART / ext4 100G`
- `PART /srv ext4 all`
- ESC 0 + yes
- reboot

Partitioning.

- First disk
  - OS
  - non precious data such as the LXC containers with runners.
- Second disk
  - a partition configured with DRBD

Debian user.

- `ssh root@hetzner0?.forgejo.org`
- `useradd --shell /bin/bash --create-home --groups sudo debian`
- `mkdir -p /home/debian/.ssh ; cp -a .ssh/authorized_keys /home/debian/.ssh ; chown -R debian /home/debian/.ssh`
- in `/etc/sudoers` edit `%sudo   ALL=(ALL:ALL) NOPASSWD:ALL`

## Install helpers

Each node is identifed by the last digit of the hostname.

```sh
sudo apt-get install git etckeeper
git clone https://code.forgejo.org/infrastructure/documentation
cd documentation/k3s-host
cp variables.sh.example variables.sh
cp secrets.sh.example secrets.sh
```

Variables that must be set depending on the role of the node.

- first server node
  - secrets.sh: node_drbd_shared_secret
- other server node
  - secrets.sh: node_drbd_shared_secret
  - secrets.sh: node_k8s_token: content of /var/lib/rancher/k3s/server/token on the first node
  - variables.sh: node_k8s_existing: identifier of the first node (e.g. 5)
- etcd node
  - secrets.sh: node_k8s_token: content of /var/lib/rancher/k3s/server/token on the first node
  - variables.sh: node_k8s_existing: identifier of the first node (e.g. 5)
  - variables.sh: node_k8s_etcd: identifier of the node whose role is just etcd (e.g. 3)

The other variables depend on the setup.

## Firewall

`./setup.sh setup_ufw`

## DRBD

DRBD is [configured](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/#p-work) with:

`./setup.sh setup_drbd`

Once two nodes have DRBD setup for the first time, it can be initialized by [pretending all is in sync](https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/#s-skip-initial-resync) to save the initial bitmap sync since there is actually no data at all.


```sh
sudo drbdadm primary r1
sudo drbdadm new-current-uuid --clear-bitmap r1/0
sudo mount /precious
```

## NFS

`./setup.sh setup_nfs`

On the node that has the DRBD volume `/precious` mounted, set the IP of the NFS server to be used by k8s:

```sh
sudo ip addr add 10.53.101.100/24 dev enp5s0.4001
```

## K8S

For the first node `./setup.sh setup_k8s`. For nodes joining the cluster `./setup.sh setup_k8s 6` where `hetzner06` is an existing node.

- [metallb](https://metallb.universe.tf) instead of the default load balancer because it does not allow for a public IP different from the `k8s` node IP.
  `./setup.sh setup_k8s_metallb`
- [traefik](https://traefik.io/) [v2.10](https://doc.traefik.io/traefik/v3.1/) installed from the [v25.0](https://github.com/traefik/traefik-helm-chart/tree/v31.1.1) helm chart.
  `./setup.sh setup_k8s_traefik`
- [cert-manager](https://cert-manager.io/).
  `./setup.sh setup_k8s_certmanager`
- NFS storage class
  `./setup.sh setup_k8s_nfs`

## K8S NFS storage creation

Define the 20GB `forgejo-data` pvc owned by user id 1000.

```sh
./setup.sh setup_k8s_pvc forgejo-data 20Gi 1000
```
