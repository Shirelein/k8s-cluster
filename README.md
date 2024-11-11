There is a [dedicated chatroom](https://matrix.to/#/#forgejo-ci:matrix.org). A mirror of this repository is available at <https://git.pub.solar/forgejo/k8s-cluster>.

## Table of content

- Setting up a new [K8S/DRBD/NFS k8s node](k8s.md) deployed with flux.
- Maintenance and disaster recovery of a [K8S/DRBD/NFS k8s node](k8s-maintenance.md)
- Installing a [Forgejo instance in the K8S cluster](k8s-forgejo.md)
- Local [Development](#development)

## Monitoring

Cluster monitoring will send warnings to a private Matrix chatroom dedicated to this purpose. The error messages may contain sensitive information. They should not but they are error messages after all and that possibility cannot be dismissed.

The forgejo-matrix-devops account on matrix.org is associated with the matrix-devops at forgejo.org email which is an alias to contact. The password, session keys etc. are not stored anywhere. If there ever is a need for manual interaction with this account, the password will have to be reset.

## hetzner{05,06}

<https://hetzner05.forgejo.org> & <https://hetzner06.forgejo.org> run on [EX44](https://www.hetzner.com/dedicated-rootserver/ex44) Hetzner hardware.

Nodes of [a k8s cluster](k8s.md).

## Development

Install following tools locally:

- `node`
- `pnpm` or enable `corepack`
- `helm`
- `flux`

Run `pnpm install` after code checkout to prepare development.
This installs git hooks to fix simple lint issues.

You can run `pnpm lint` to run all lint checks.
