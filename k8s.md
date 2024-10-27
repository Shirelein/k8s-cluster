# K8S node

Installing a K8S cluster deployed with [flux](https://fluxcd.io/) using [scripts from the k3s-host](k3s-host) directory.

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
git clone https://code.forgejo.org/infrastructure/k8s-cluster
cd k8s-cluster/k3s-host
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

For the first node:

- `./setup.sh setup_k8s`

For nodes joining the cluster:

- `./setup.sh setup_k8s 6` where `hetzner06` is an existing node.

## flux

Add [flux](https://fluxcd.io/flux/use-cases/helm/) to deploy from https://code.forgejo.org/infrastructure/k8s-cluster.

The [flux/clusters/flux-system/gotk-components.yaml](https://code.forgejo.org/infrastructure/k8s-cluster/src/branch/main/flux/clusters/flux-system/gotk-components.yaml) file is [created and committed to the repository](https://code.forgejo.org/infrastructure/documentation/issues/43#issuecomment-16755) with:

```sh
curl -s https://fluxcd.io/install.sh | sudo bash
flux check --pre
flux install --export  > flux/clusters/prod/flux-system/gotk-components.yaml
```

- `./setup.sh setup_flux`

Create the following secrets to be used by [the Receiver](https://code.forgejo.org/infrastructure/k8s-cluster/src/branch/main/flux/clusters/flux-system/receiver.yaml) to authenticate the Forgejo webhook created with the same secret to instruct flux to pull from the repository.

```sh
secret_name=webhook-???
TOKEN=$(head -c 12 /dev/urandom | shasum | cut -d ' ' -f1)
kubectl -n flux-system create secret generic $secret_name --from-literal=token=$TOKEN
kubectl -n flux-system get secret $secret_name -o json | jq -r .data.token | base64 -d
```

The URL of the webhook is composed as follows:

```sh
receiver_name=forgejo-???
echo https://flux.k8s.forgejo.org$(kubectl --namespace flux-system get -o go-template='{{.status.webhookPath}}' Receiver $receiver_name)
```

* For the [k8s-cluster repository webhook](https://code.forgejo.org/infrastructure/k8s-cluster/settings/hooks)
  * receiver_name=forgejo-flux-receiver
  * secret_name=webhook-flux-token
* For the [next-digest repository webhook](https://code.forgejo.org/infrastructure/next-digest/settings/hooks)
  * receiver_name=forgejo-next-digest-flux-receiver
  * secret_name=webhook-next-digest-flux-token

## Prepare storage

A directory must exist before a [PV](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) can be created to use it via NFS.

Create the `forgejo-data` directory, owned by user id 1000.

```sh
./setup.sh setup_k8s_pvc forgejo-data 1000
```
