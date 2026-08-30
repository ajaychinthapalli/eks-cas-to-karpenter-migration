# eks-cas-to-karpenter-migration

Cluster Autoscaler → Karpenter Migration

Documentation of the migration performed on the `achin16-workspace` EKS cluster
(account `<AWS_ACCOUNT_ID>`, region `us-east-2`), following the 6-step process below.
Every command here was actually run against a live cluster; outputs and
troubleshooting notes are captured in each step's doc.

## Cluster facts (as found)

| Item | Value |
|---|---|
| Cluster name | `achin16-workspace` |
| Region | `us-east-2` |
| Account ID | `<AWS_ACCOUNT_ID>` |
| Kubernetes version | `1.36` |
| OIDC issuer | `oidc.eks.us-east-2.amazonaws.com/id/<OIDC_ID>` |
| Existing compute | Self-managed ASG `achin16nodegroupstack-NodeGroup-*` (3× `t3.small`), **not** an EKS-managed nodegroup, **not** Fargate |
| Subnets | 3× **public** subnets (no NAT / private subnets in this VPC) |
| Node security group | `<NODE_SECURITY_GROUP_ID>` (`achin16nodegroupstack-NodeSecurityGroup-*`) |
| Karpenter version installed | `1.13.1` (required — `1.36` needs Karpenter `>= 1.13` per [compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/)) |

## Architecture Overview

![Cluster Autoscaler vs Karpenter — Migration Overview, Key Components, Node Provisioning Flow, and Required AWS Tags](https://github.com/user-attachments/assets/a1b08435-7438-45cc-92f4-3f2732c2335a)

The diagram above illustrates four key areas:

- **Cluster Autoscaler vs Karpenter** — Cluster Autoscaler scales existing node groups via Auto Scaling Groups; Karpenter provisions right-sized EC2 instances directly based on pending pods, yielding better utilisation, faster scaling, and lower cost.
- **Migration Overview** — Six sequential steps (Prepare → Tag Resources → Create IAM Role → Install Karpenter → Create EC2NodeClass & NodePool → Test & Migrate) leading to a final state of Karpenter Active + a small system node group + workloads on Karpenter nodes.
- **Karpenter Key Components** — Karpenter Controller watches for unschedulable pods; `EC2NodeClass` defines infrastructure (AMI, subnets, security groups, IAM role, tags); `NodePool` defines provisioning rules (instance types, capacity type, labels/taints, limits); `NodeClaim` represents a node being launched.
- **Karpenter Node Provisioning Flow** — Pending Pod → Karpenter Detects → Select Best Fit → Launch EC2 Instance → Register & Schedule, resulting in automated, right-sized, efficient compute.

## Steps

1. [Prepare](docs/01-prepare.md)
2. [Tag Resources](docs/02-tag-resources.md)
3. [Create IAM Role](docs/03-create-iam-role.md)
4. [Install Karpenter](docs/04-install-karpenter.md)
5. [Create EC2NodeClass & NodePool](docs/05-create-nodeclass-nodepool.md)
6. [Test & Migrate](docs/06-test-and-migrate.md)

See [troubleshooting.md](docs/troubleshooting.md) for every issue actually hit
during this migration and how it was resolved — worth reading before you repeat
this elsewhere, since several of these are easy to hit again.

## Repo layout

```
eks-cas-to-karpenter-migration/
├── README.md
├── docs/
│   ├── 01-prepare.md
│   ├── 02-tag-resources.md
│   ├── 03-create-iam-role.md
│   ├── 04-install-karpenter.md
│   ├── 05-create-nodeclass-nodepool.md
│   ├── 06-test-and-migrate.md
│   └── troubleshooting.md
├── manifests/
│   ├── ec2nodeclass.yaml
│   ├── nodepool.yaml
│   └── test-scaleup.yaml
├── policies/
│   ├── node-trust-policy.json
│   ├── controller-trust-policy.json
│   └── controller-permissions-policy.json
└── scripts/
    └── deploy.sh
```

## Final state (achieved)

- ✅ Karpenter `1.13.1` running, 2/2 pods healthy
- ✅ Existing `achin16nodegroupstack` ASG kept as small system node group
- ✅ Proven: pods scheduled on Karpenter-launched nodes, then consolidated away automatically
- ✅ Cluster Autoscaler was never present on this cluster, so there was nothing to disable

## Known limitations / follow-ups not yet done

- Subnets are public — no NAT gateway/private subnets exist in this VPC. Fine for
  a sandbox, revisit before production use.
- Account's shared EC2 vCPU quota (`L-1216C47A`, Standard A/C/D/H/I/M/R/T/Z family)
  is **16 vCPU**, shared with an unrelated stack (`demonodesstack`, 3× `t3.small`)
  in the same account/region. Real workloads needing larger/multiple instances
  may hit `VcpuLimitExceeded` — request a quota increase before relying on this
  for anything beyond testing.
- No SQS interruption queue configured (`settings.interruptionQueue` left empty)
  — only matters if/when Spot capacity is added.
- Only on-demand capacity type configured in the NodePool; Spot not yet enabled.
