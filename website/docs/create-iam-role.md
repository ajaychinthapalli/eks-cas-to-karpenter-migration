---
id: create-iam-role
title: "Step 3: Create IAM Role"
sidebar_label: "3. Create IAM Role"
sidebar_position: 4
---

# Step 3: Create IAM Role

## Goal

Create two IAM roles:

1. **Node role** (`KarpenterNodeRole-achin16-workspace`) — attached to EC2
   instances Karpenter launches, via an instance profile.
2. **Controller role** (`KarpenterControllerRole-achin16-workspace`) — used by
   the Karpenter pod itself via IRSA to call EC2/IAM APIs.

Trust/permission policy JSON files are in [`https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/`](https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/).

## 3a. Node role

```bash
export AWS_ACCOUNT_ID=<AWS_ACCOUNT_ID>
export OIDC_ID=<OIDC_ID>
export KARPENTER_NODE_ROLE=KarpenterNodeRole-${CLUSTER_NAME}
export KARPENTER_CONTROLLER_ROLE=KarpenterControllerRole-${CLUSTER_NAME}

aws iam create-role \
  --role-name $KARPENTER_NODE_ROLE \
  --assume-role-policy-document file://https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/node-trust-policy.json

aws iam attach-role-policy --role-name $KARPENTER_NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name $KARPENTER_NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --role-name $KARPENTER_NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name $KARPENTER_NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name $KARPENTER_NODE_ROLE
aws iam add-role-to-instance-profile \
  --instance-profile-name $KARPENTER_NODE_ROLE \
  --role-name $KARPENTER_NODE_ROLE
```

## 3b. Controller role (IRSA)

```bash
aws iam create-role \
  --role-name $KARPENTER_CONTROLLER_ROLE \
  --assume-role-policy-document file://https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/controller-trust-policy.json
```

### ⚠️ Issue hit: wrong/missing OIDC provider

`aws iam list-open-id-connect-providers` showed only an OIDC provider for a
**different** ID (`<UNRELATED_OIDC_ID>`) — this cluster's own OIDC
provider (`<OIDC_ID>`) had never been registered with
IAM. The controller role's trust policy referenced an ARN that didn't exist
yet, so IRSA would have silently failed. Fixed with:

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --approve
```

Re-checking `aws iam list-open-id-connect-providers` afterward showed the
correct provider registered. See [troubleshooting.md](troubleshooting#1-oidc-provider-not-registered)
for full detail.

## 3c. Permissions policy on the controller role

The full policy is in [`https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/controller-permissions-policy.json`](https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/controller-permissions-policy.json).
Note it was **updated once** after the first Karpenter install attempt
surfaced a missing-permission error (`iam:ListInstanceProfiles` etc. — see
troubleshooting doc). The version in this repo already includes the fix.

```bash
aws iam put-role-policy \
  --role-name $KARPENTER_CONTROLLER_ROLE \
  --policy-name KarpenterControllerPolicy \
  --policy-document file://https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/controller-permissions-policy.json
```

## 3d. aws-auth mapping so Karpenter-launched nodes can join

```bash
eksctl create iamidentitymapping \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${KARPENTER_NODE_ROLE} \
  --username system:node:{{EC2PrivateDNSName}} \
  --group system:bootstrappers \
  --group system:nodes
```

## Verification

```bash
aws iam get-role --role-name $KARPENTER_CONTROLLER_ROLE --query "Role.Arn" --output text
# arn:aws:iam::<AWS_ACCOUNT_ID>:role/KarpenterControllerRole-achin16-workspace

aws iam list-role-policies --role-name $KARPENTER_CONTROLLER_ROLE
# { "PolicyNames": ["KarpenterControllerPolicy"] }

aws iam get-role --role-name $KARPENTER_NODE_ROLE --query "Role.Arn" --output text
# arn:aws:iam::<AWS_ACCOUNT_ID>:role/KarpenterNodeRole-achin16-workspace
```
