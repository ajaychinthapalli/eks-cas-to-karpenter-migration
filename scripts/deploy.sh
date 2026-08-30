#!/usr/bin/env bash
# Consolidated, working end-to-end script for this migration.
# This is a record of what was actually run, in the corrected order —
# NOT a blind "run this on any cluster" script. Review env vars and the
# troubleshooting notes in ../docs/troubleshooting.md before reusing.
set -euo pipefail

# ---- Step 0: environment -----------------------------------------------
export CLUSTER_NAME=achin16-workspace
export AWS_REGION=us-east-2
export AWS_ACCOUNT_ID=<AWS_ACCOUNT_ID>
export OIDC_ID=<OIDC_ID>
export KARPENTER_NODE_ROLE=KarpenterNodeRole-${CLUSTER_NAME}
export KARPENTER_CONTROLLER_ROLE=KarpenterControllerRole-${CLUSTER_NAME}
export KARPENTER_VERSION="1.13.1"   # must satisfy your cluster's K8s version — see docs/04-install-karpenter.md

# Subnets and node SG discovered in docs/01-prepare.md / 02-tag-resources.md
SUBNETS="<SUBNET_ID_A> <SUBNET_ID_B> <SUBNET_ID_C>"
NODE_SG="<NODE_SECURITY_GROUP_ID>"

# ---- Step 2: Tag Resources ---------------------------------------------
aws ec2 create-tags --region "$AWS_REGION" \
  --resources $SUBNETS \
  --tags Key=karpenter.sh/discovery,Value="$CLUSTER_NAME"

aws ec2 create-tags --region "$AWS_REGION" \
  --resources "$NODE_SG" \
  --tags Key=karpenter.sh/discovery,Value="$CLUSTER_NAME"

# ---- Step 3: Create IAM Role -------------------------------------------
aws iam create-role \
  --role-name "$KARPENTER_NODE_ROLE" \
  --assume-role-policy-document file://../policies/node-trust-policy.json

for POLICY in \
  arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
  arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
  arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
do
  aws iam attach-role-policy --role-name "$KARPENTER_NODE_ROLE" --policy-arn "$POLICY"
done

aws iam create-instance-profile --instance-profile-name "$KARPENTER_NODE_ROLE"
aws iam add-role-to-instance-profile \
  --instance-profile-name "$KARPENTER_NODE_ROLE" \
  --role-name "$KARPENTER_NODE_ROLE"

# IMPORTANT: register the cluster's own OIDC provider BEFORE creating the
# controller role's trust policy — see docs/troubleshooting.md #1.
eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --approve

aws iam create-role \
  --role-name "$KARPENTER_CONTROLLER_ROLE" \
  --assume-role-policy-document file://../policies/controller-trust-policy.json

aws iam put-role-policy \
  --role-name "$KARPENTER_CONTROLLER_ROLE" \
  --policy-name KarpenterControllerPolicy \
  --policy-document file://../policies/controller-permissions-policy.json

eksctl create iamidentitymapping \
  --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
  --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${KARPENTER_NODE_ROLE}" \
  --username system:node:{{EC2PrivateDNSName}} \
  --group system:bootstrappers \
  --group system:nodes

# ---- Step 4: Install Karpenter -----------------------------------------
export KARPENTER_CONTROLLER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${KARPENTER_CONTROLLER_ROLE}"
export CLUSTER_ENDPOINT
CLUSTER_ENDPOINT=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query "cluster.endpoint" --output text)

# No `helm registry login` needed — public.ecr.aws allows anonymous pulls.
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace kube-system \
  --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_CONTROLLER_ROLE_ARN}" \
  --set "settings.interruptionQueue=" \
  --wait

kubectl rollout status deployment/karpenter -n kube-system

# ---- Step 5: EC2NodeClass & NodePool -----------------------------------
kubectl apply -f ../manifests/ec2nodeclass.yaml
kubectl apply -f ../manifests/nodepool.yaml

kubectl wait --for=condition=Ready ec2nodeclass/default --timeout=60s
kubectl wait --for=condition=Ready nodepool/default --timeout=60s

echo "Migration steps 2-5 complete. Run Step 6 (test/validate) manually —"
echo "see ../docs/06-test-and-migrate.md — since it involves live traffic"
echo "and manual verification of scale-up/consolidation behavior."
