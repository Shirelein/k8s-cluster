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
