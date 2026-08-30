# Step 1: Prepare

## Goal

Confirm cluster access, Kubernetes version, existing compute, and VPC layout
before touching anything.

## Commands run

```bash
export CLUSTER_NAME=achin16-workspace
export AWS_REGION=us-east-2

# Cluster status
aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.status"
# -> "ACTIVE"

# OIDC issuer (needed for IAM role trust policy later)
aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION \
  --query "cluster.identity.oidc.issuer" --output text
# -> https://oidc.eks.us-east-2.amazonaws.com/id/<OIDC_ID>

# Any eksctl/EKS-managed nodegroups?
eksctl get nodegroup --cluster $CLUSTER_NAME --region $AWS_REGION
# -> Error: No nodegroups found

aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $AWS_REGION
# -> { "nodegroups": [] }

# Any Fargate profiles?
aws eks list-fargate-profiles --cluster-name $CLUSTER_NAME --region $AWS_REGION
# -> { "fargateProfileNames": [] }

# Actual running nodes
kubectl get nodes -o wide
kubectl version --short   # Server Version: v1.36.2-eks-... (later observed v1.36.3 after Karpenter nodes joined)
```

## Findings

- **3 running nodes**, but no EKS-managed nodegroup and no Fargate — they turned
  out to be a **self-managed ASG** created via CloudFormation:

  ```bash
  aws ec2 describe-instances \
    --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" "Name=instance-state-name,Values=running" \
    --region $AWS_REGION \
    --query "Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,AZ:Placement.AvailabilityZone,Tags:Tags}"
  ```

  Tags revealed: ASG name `achin16nodegroupstack-NodeGroup-rLRAjjHQWDYr`,
  CFN stack `achin16nodegroupstack`, instance type `t3.small` × 3, one per AZ
  (`us-east-2a/b/c`).

- **No Cluster Autoscaler deployment found** (`kubectl get deployment
  cluster-autoscaler -n kube-system` → NotFound). Nothing to disable in Step 6.

- System pods (`aws-node`, `coredns`, `kube-proxy`) plus a test `nginx`
  deployment were already running fine on the ASG nodes — this ASG became our
  **small system node group** without needing to create a new one.

## Decision

Kept the existing `achin16nodegroupstack` ASG as-is to serve as the small
system node group called for in the migration diagram, rather than creating a
new managed nodegroup from scratch. No changes made in this step — read-only
discovery only.
