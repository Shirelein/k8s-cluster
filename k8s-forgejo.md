# Forgejo k8s instance

[forgejo](https://code.forgejo.org/forgejo-helm/forgejo-helm) configuration in [ingress](https://code.forgejo.org/forgejo-helm/forgejo-helm#ingress) for the reverse proxy (`traefik`) to route the domain and for the ACME issuer (`cert-manager`) to obtain a certificate. And in [service](https://code.forgejo.org/forgejo-helm/forgejo-helm#service) for the `ssh` port to be bound to the desired IPs of the load balancer (`metallb`). A [PVC](https://code.forgejo.org/forgejo-helm/forgejo-helm#persistence) is created on the networked storage.

## Secrets

### New

- `cp forgejo-secrets.yml.example $name-secrets.yml`
- edit
- `kubectl create secret generic forgejo-$name-secrets --from-file=value=$name-secrets.yml`

### Existing

- `kubectl get secret forgejo-$name-secrets -o json | jq -r  '.data.value' | base64 -d > $name-secrets.yml`

## Storage

- `../k3s-host/setup.sh setup_k8s_pvc forgejo-$name 4Gi 1000`

## Pod

- `../k3s-host/subst.sh forgejo-values.yml | helm upgrade forgejo-$name -f - -f $name-values.yml -f crawler-block-values.yml -f $name-secrets.yml oci://code.forgejo.org/forgejo-helm/forgejo --atomic --wait --install`
