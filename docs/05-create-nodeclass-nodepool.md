# Step 5: Create EC2NodeClass & NodePool

## Goal

Define *what* Karpenter should launch: AMI, IAM role, subnets/SGs
(`EC2NodeClass`), and instance requirements/limits/disruption policy
(`NodePool`).

Manifests: [`../manifests/ec2nodeclass.yaml`](../manifests/ec2nodeclass.yaml),
[`../manifests/nodepool.yaml`](../manifests/nodepool.yaml).

## Apply

```bash
kubectl apply -f ../manifests/ec2nodeclass.yaml
kubectl apply -f ../manifests/nodepool.yaml
```

## Design choices made (and why)

| Setting | Value | Why |
|---|---|---|
| `amiFamily` | `AL2023` | Current recommended AMI family |
| `capacity-type` | `on-demand` only | Safer for first test; spot not yet enabled |
| `instance-category` | `t`, `c`, `m` | General-purpose/compute; excludes GPU/memory-optimized to avoid surprise cost |
| `instance-generation` | `> 2` | Avoids very old generations |
| `limits.cpu` / `limits.memory` | `20` / `40Gi` | Safety cap — a runaway pod backlog can't launch unlimited nodes |
| `consolidationPolicy` | `WhenEmptyOrUnderutilized` | Standard cost-saving default |
| `consolidateAfter` | `1m` | Aggressive for a sandbox; use longer (5–30m) in production to avoid thrashing |
| `expireAfter` | `720h` (30 days) | Forces periodic node refresh |

## Verification

```bash
kubectl get ec2nodeclass
kubectl get nodepool
kubectl describe nodepool default
```

Expected: both show `READY: True`. Confirmed result:

```
NAME      READY   AGE
default   True    53s

NAME      NODECLASS   NODES   READY   AGE
default   default     0       True    21s
```

`describe nodepool` conditions all showed `Status: True` for
`ValidationSucceeded`, `NodeClassReady`, and `Ready`.
