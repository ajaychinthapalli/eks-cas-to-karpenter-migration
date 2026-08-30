---
id: intro
title: Overview
sidebar_label: Overview
sidebar_position: 1
slug: /
---

# EKS Cluster Autoscaler → Karpenter Migration

Documentation of the migration performed on the `achin16-workspace` EKS cluster following a 6-step process.
Every command here was actually run against a live cluster; outputs and troubleshooting notes are captured in each step's doc.

## Cluster Facts (as found)

| Item | Value |
|---|---|
| Cluster name | `achin16-workspace` |
| Region | `us-east-2` |
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

1. [Prepare](./prepare) — Confirm cluster access, K8s version, existing compute, and VPC layout.
2. [Tag Resources](./tag-resources) — Tag subnets and node security group for Karpenter discovery.
3. [Create IAM Role](./create-iam-role) — Create node and controller IAM roles.
4. [Install Karpenter](./install-karpenter) — Install via Helm.
5. [Create EC2NodeClass & NodePool](./create-nodeclass-nodepool) — Define what Karpenter launches.
6. [Test & Migrate](./test-and-migrate) — Verify provisioning and complete migration.

See [Troubleshooting](./troubleshooting) for every issue actually hit during this migration.

## Final State (achieved)

- ✅ Karpenter `1.13.1` running, 2/2 pods healthy
- ✅ Existing `achin16nodegroupstack` ASG kept as small system node group
- ✅ Proven: pods scheduled on Karpenter-launched nodes, then consolidated away automatically
- ✅ Cluster Autoscaler was never present on this cluster, so there was nothing to disable

## Known Limitations / Follow-ups

- Subnets are public — no NAT gateway/private subnets exist in this VPC. Fine for a sandbox, revisit before production use.
- Account's shared EC2 vCPU quota (`L-1216C47A`, Standard A/C/D/H/I/M/R/T/Z family) is **16 vCPU**, shared with an unrelated stack (`demonodesstack`, 3× `t3.small`) in the same account/region.
- No SQS interruption queue configured (`settings.interruptionQueue` left empty) — only matters if/when Spot capacity is added.
- Only on-demand capacity type configured in the NodePool; Spot not yet enabled.
