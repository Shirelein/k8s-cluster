#!/bin/bash

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ${VERBOSE:-false}; then
	set -ex
	PS4='${BASH_SOURCE[0]}:$LINENO: ${FUNCNAME[0]}:  '
else
	set -e
fi

source $SELF_DIR/variables.sh
source $SELF_DIR/secrets.sh

set -o pipefail

self_node=$(hostname | sed -e 's/hetzner0//')
interface=${node_interface[$self_node]}

dependencies="retry etckeeper"

if ! which $dependencies >&/dev/null; then
	sudo apt-get -q install -qq -y $dependencies
fi

function setup_ufw() {
	sudo apt-get -q install -qq -y ufw

	sudo ufw --force reset

	sudo ufw default allow incoming
	sudo ufw default allow outgoing
	sudo ufw default allow routed

	for from in $nodes; do
		for to in $nodes; do
			if test $from != $to; then
				for v in ipv4 ipv6; do
					eval from_ip=\${node_$v[$from]}
					eval to_ip=\${node_$v[$to]}
					sudo ufw allow in on $interface from $from_ip to $to_ip
				done
			fi
		done
	done

	for host_ip in ${node_ipv4[$self_node]} ${node_ipv6[$self_node]}; do
		sudo ufw allow in on $interface to $host_ip port 22 proto tcp
		sudo ufw deny in on $interface log-all to $host_ip
	done

	for public_ip in $failover_ipv4 $failover_ipv6; do
		sudo ufw allow in on $interface to $public_ip port 22,80,443,2000:3000 proto tcp
		sudo ufw deny in on $interface log-all to $public_ip
	done

	sudo ufw enable
	sudo systemctl start ufw
	sudo systemctl enable ufw
	sudo ufw status verbose
}

function setup_drbd() {
	if ! test -f /etc/network/interfaces.d/drbd; then
		cat <<EOF | sudo tee /etc/network/interfaces.d/drbd
auto $interface.$node_drbd_vlan
iface $interface.$node_drbd_vlan inet static
  address $node_drbd_ipv4_prefix.$self_node
  netmask 255.255.255.0
  vlan-raw-device $interface
  mtu 1400
EOF
		sudo ifup $interface.$node_drbd_vlan
	fi
	sudo apt-get install -y drbd-utils
	res_file=/etc/drbd.d/$node_drbd_resource.res
	if ! sudo test -f $res_file; then
		(
			cat <<EOF
resource $node_drbd_resource {
    net {
        # A : write completion is determined when data is written to the local disk and the local TCP transmission buffer
        # B : write completion is determined when data is written to the local disk and remote buffer cache
        # C : write completion is determined when data is written to both the local disk and the remote disk
        protocol C;
        cram-hmac-alg sha1;
        # any secret key for authentication among nodes
        shared-secret "$node_drbd_shared_secret";
    }
    disk {
        resync-rate 100M;
    }
EOF
			for node in $nodes; do
				cat <<EOF
    on hetzner0$node {
        address $node_drbd_ipv4_prefix.$node:7788;
        volume 0 {
            device /dev/drbd0;
            disk ${node_drbd_device[$node]};
            meta-disk internal;
        }
    }
EOF
			done
			cat <<EOF
}
EOF
		) | sudo tee $res_file
	fi
	if ! sudo drbdadm status $node_drbd_resource >&/dev/null; then
		sudo drbdadm create-md $node_drbd_resource
		sudo systemctl enable drbd
		sudo systemctl start drbd
	fi
	if ! grep --quiet '^/dev/drbd0 /precious' /etc/fstab; then
		echo /dev/drbd0 /precious ext4 noauto,noatime,defaults 0 0 | sudo tee -a /etc/fstab
		sudo mkdir -p /precious
	fi
}

function setup_nfs() {
	sudo apt-get install -y nfs-kernel-server nfs-common

	if ! test -f /etc/network/interfaces.d/nfs; then
		cat <<EOF | sudo tee /etc/network/interfaces.d/nfs
auto $interface.$node_nfs_vlan
iface $interface.$node_nfs_vlan inet static
  address $node_nfs_ipv4_prefix.$self_node
  netmask 255.255.255.0
  vlan-raw-device $interface
  mtu 1400
EOF
		sudo ifup $interface.$node_nfs_vlan
	fi
	if ! grep --quiet '^/precious' /etc/exports; then
		cat <<EOF | sudo tee -a /etc/exports
/precious $node_nfs_ipv4_prefix.0/24(rw,fsid=0,no_root_squash,no_subtree_check)
/precious/k8s $node_nfs_ipv4_prefix.0/24(rw,nohide,insecure,no_subtree_check)
EOF
		sudo exportfs -va || true # it does not matter if the expored dirs do not exist, they will
		sudo exportfs -s
	fi
}

function setup_k8s() {
	existing=$1

	if ! test -f /etc/network/interfaces.d/k8s; then
		cat <<EOF | sudo tee /etc/network/interfaces.d/k8s
auto $interface.$node_k8s_vlan
iface $interface.$node_k8s_vlan inet static
  address $node_k8s_ipv4_prefix.$self_node
  netmask 255.255.0.0
  vlan-raw-device $interface
  mtu 1400
  up ip addr add $node_k8s_ipv6_prefix::$self_node/48 dev $interface.$node_k8s_vlan
  up ip addr add $failover_ipv4/$failover_ipv4_range dev $interface
  up ip addr add $failover_ipv6/$failover_ipv6_range dev $interface
EOF
		sudo ifup $interface.$node_k8s_vlan
	fi
	if ! grep --quiet 'export KUBECONFIG' ~/.bashrc; then
		echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >>~/.bashrc
	fi
	#
	# To upgrade, systemctl stop k3s before running this. A node
	# that is already part of a cluster does not need the --token
	# or --server so there is no need to provide the number of an
	# existing node.
	#
	if ! sudo systemctl --quiet is-active k3s; then
		args=""
		if test "$existing"; then
			if ! test "$node_k8s_token"; then
				echo "obtain the token from node $existing with sudo cat /var/lib/rancher/k3s/server/token and set node_k8s_token= in secrets.sh"
				exit 1
			fi
			args="$args --token $node_k8s_token --server https://$node_k8s_ipv4_prefix.$existing:6443"
		fi
		if test "$self_node" = $node_k8s_etcd; then
			args="$args --disable-apiserver --disable-controller-manager --disable-scheduler"
		fi
		export INSTALL_K3S_VERSION=$K3S_VERSION
		curl -fL https://get.k3s.io | sh -s - server $args --cluster-init --disable=servicelb --disable=traefik --write-kubeconfig-mode=600 --node-ip=$node_k8s_ipv4_prefix.$self_node,$node_k8s_ipv6_prefix::$self_node $node_k8s_cidr --flannel-ipv6-masq
		if test "$self_node" = $node_k8s_etcd; then
			retry --times 20 -- kubectl taint nodes $(hostname) key1=value1:NoSchedule
		fi
		if test "$self_node" != $node_k8s_etcd; then
			curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -
		fi
	fi
}

function setup_k8s_apply() {
	retry --delay 30 --times 10 -- bash -c "$SELF_DIR/subst.sh $1 | kubectl apply --server-side=true -f -"
}

function setup_k8s_pvc() {
	export pvc_name=$1
	export pvc_capacity=$2
	export pvc_owner=$3

	sudo mount -o nfsvers=4.2 $node_nfs_server:/k8s /opt
	sudo mkdir -p /opt/$pvc_name
	sudo chown $pvc_owner:$pvc_owner /opt/$pvc_name
	sudo umount /opt

	setup_k8s_apply pvc.yml
}

function setup_k8s_flux() {
	kubectl apply --server-side -f $FLUX_DIR/clusters/flux-system/gotk-components.yaml
	kubectl apply --server-side -f $FLUX_DIR/clusters/flux-system/gotk-sync.yaml
	kubectl annotate -n flux-system --field-manager=flux-client-side-apply --overwrite GitRepository/flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)"
}

"$@"
