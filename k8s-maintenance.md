# Disaster recovery and maintenance

## When a machine or disk is scheduled for replacement.

* `kubectl drain hetzner05` # evacuate all the pods out of the node to be shutdown
* `kubectl taint nodes hetzner05 key1=value1:NoSchedule` # prevent any pod from being created there (metallb speaker won't be drained, for instance)
* `kubectl delete node hetzner05` # let the cluster know it no longer exists so a new one by the same name can replace it

## Routing the failover IP

When the machine to which the failover IP (failover.forgejo.org) is routed is unavailable or to be shutdown, to the [Hetzner server panel](https://robot.hetzner.com/server), to the IPs tab and change the route of the failover IP to another node. All nodes are configured with the failover IP, there is nothing else to do.

## Manual boot operations

### On the machine that runs the NFS server

* `sudo drbdadm primary r1` # Switch the DRBD to primary
* `sudo mount /precious` # DRBD volume shared via NFS
* `sudo ip addr add 10.53.101.100/24 dev enp5s0.4001` # add NFS server IP

### On the other machines

* `sudo ip addr del 10.53.101.100/24 dev enp5s0.4001` # remove NFS server IP
