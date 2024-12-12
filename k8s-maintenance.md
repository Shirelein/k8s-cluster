# Disaster recovery and maintenance

## When a machine or disk is scheduled for replacement

### Local and NFS PVC

For all pods there are two PVC:

- NFS (e.g. `claimName: forgejo-next`). They are slower but allow pods to move to any node in the cluster.
- Local (e.g. `claimName: forgejo-next-local`). They are faster but require the pods to run from the node that mounts the DRBD device.

### Move the pods out of the node

- Ensure all pods use the NFS PVC
- `kubectl drain hetzner05` # evacuate all the pods out of the node to be shutdown
- `kubectl taint nodes hetzner05 key1=value1:NoSchedule` # prevent any pod from being created there (metallb speaker won't be drained, for instance)
- `kubectl delete node hetzner05` # let the cluster know it no longer exists so a new one by the same name can replace it

### Labeling the Local storage node

- `kubectl label node --all forgejo.org/drbd-`
- `kubectl label node hetzner06 forgejo.org/drbd=primary`

## Routing the failover IP

When the machine to which the failover IP (failover.forgejo.org) is routed is unavailable or to be shutdown, to the [Hetzner server panel](https://robot.hetzner.com/server), to the IPs tab and change the route of the failover IP to another node. All nodes are configured with the failover IP, there is nothing else to do.

## Manual boot operations

### On the machine that runs the NFS server

- `sudo drbdadm primary r1` # Switch the DRBD to primary
- `sudo mount /precious` # DRBD volume shared via NFS
- `sudo ip addr add 10.53.101.100/24 dev enp5s0.4001` # add NFS server IP

### On the other machines

- `sudo ip addr del 10.53.101.100/24 dev enp5s0.4001` # remove NFS server IP

## When code.forgejo.org is down

A [push mirror is configured](https://code.forgejo.org/infrastructure/k8s-cluster/settings) and available at <https://codeberg.org/forgejo/k8s-cluster>. It is synchronized on every push. The service account used for this purpose is a [write collaborator](https://codeberg.org/forgejo/k8s-cluster/settings/collaboration).

Both repositories have [a webhook configured](./k8s.md#flux) so that the cluster is notified on every push. But only one of them must be activated at any given time. It must be the repository from which k8s will pull, i.e. the one in code.forgejo.org most of the time. Only when code.forgejo.org is unavailable should the other webhook be activated.

1. activate the [webhook of the mirror](https://codeberg.org/forgejo/k8s-cluster/settings/hooks).
1. [update mirror repo to point to mirror](https://codeberg.org/forgejo/k8s-cluster/src/commit/56dc6d19d5a12a131d052dc0018496daba360f87/flux/clusters/flux-system/gotk-sync.yaml#L11).
   ```diff
    modified   flux/clusters/flux-system/gotk-sync.yaml
    @@ -8,7 +8,7 @@ spec:
       interval: 15m
       ref:
         branch: main
    -  url: https://code.forgejo.org/infrastructure/k8s-cluster.git
    +  url: https://codeberg.org/forgejo/k8s-cluster.git
     ---
     apiVersion: kustomize.toolkit.fluxcd.io/v1
     kind: Kustomization
   ```
1. push to main on <https://codeberg.org/forgejo/k8s-cluster>
1. patch in-cluster to force loading from mirror
   ```sh
   cat > use-mirror.yml <<'EOF'
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: GitRepository
   metadata:
     name: flux-system
     namespace: flux-system
   spec:
     interval: 15m
     ref:
       branch: main
     url: https://codeberg.org/forgejo/k8s-cluster.git
   EOF
   kubectl apply --server-side --force-conflicts -f use-mirror.yml
   ```
1. when code.forgejo.org is back, [deactivate the webhook](https://code.forgejo.org/infrastructure/k8s-cluster/settings/hooks) and push <https://codeberg.org/forgejo/k8s-cluster> main branch to the <https://code.forgejo.org/infrastructure/k8s-cluster> main branch so they are identical
