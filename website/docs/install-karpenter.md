---
id: install-karpenter
title: "Step 4: Install Karpenter"
sidebar_label: "4. Install Karpenter"
sidebar_position: 5
---

# Step 4: Install Karpenter (Helm)

## ⚠️ Version compatibility — read before copying this elsewhere

This cluster runs **Kubernetes 1.36**. Per Karpenter's official
[compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/):

| Kubernetes | 1.30 | 1.31 | 1.32 | 1.33 | 1.34 | 1.35 | 1.36 |
|---|---|---|---|---|---|---|---|
| karpenter | >= 0.37 | >= 1.0.5 | >= 1.2 | >= 1.5 | >= 1.6 | >= 1.9 | **>= 1.13** |

We initially installed `1.1.1`, which crash-looped with:

```
panic: validating kubernetes version, karpenter version is not compatible with K8s version 1.36
```

**Check your own cluster's K8s version against this table before picking a
Karpenter version** — don't copy `1.13.1` blindly if you're on an older EKS
version.

## Final working install

```bash
export KARPENTER_VERSION="1.13.1"
export KARPENTER_CONTROLLER_ROLE_ARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${KARPENTER_CONTROLLER_ROLE}
export CLUSTER_ENDPOINT=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.endpoint" --output text)

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace kube-system \
  --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_CONTROLLER_ROLE_ARN}" \
  --set "settings.interruptionQueue=" \
  --wait
```

Notes:
- `public.ecr.aws` is a **public** registry — no `helm registry login` is
  needed to pull from it. We hit a `401` trying to log in manually; the fix
  was simply skipping login entirely.
- `settings.interruptionQueue` intentionally left empty — no SQS interruption
  queue was set up (only needed for graceful Spot interruption handling; not
  used yet since the NodePool is on-demand only).

## Verification

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50
```

Expected: 2/2 pods `Running`, 0 restarts, no `panic` or `AccessDenied` lines in
logs.

## Second issue hit: missing IAM permission after install succeeded

Even after fixing the version, the pods came up `Running` but logged
repeated `AccessDenied` errors:

```
User: .../KarpenterControllerRole-achin16-workspace is not authorized to
perform: iam:ListInstanceProfiles on resource: .../instance-profile/karpenter/...
```

This is Karpenter's newer (v1) instance-profile garbage-collection
controller — it manages instance profiles itself now rather than requiring a
pre-created one, and needs extra IAM actions we hadn't granted. Fixed by
updating the controller policy (see
[`https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/controller-permissions-policy.json`](https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/controller-permissions-policy.json)
— already includes `iam:CreateInstanceProfile`, `iam:TagInstanceProfile`,
`iam:AddRoleToInstanceProfile`, `iam:RemoveRoleFromInstanceProfile`,
`iam:DeleteInstanceProfile`, `iam:GetInstanceProfile`,
`iam:ListInstanceProfiles`), then:

```bash
aws iam put-role-policy \
  --role-name $KARPENTER_CONTROLLER_ROLE \
  --policy-name KarpenterControllerPolicy \
  --policy-document file://https://github.com/ajaychinthapalli/eks-cas-to-karpenter-migration/blob/main/policies/controller-permissions-policy.json

kubectl rollout restart deployment karpenter -n kube-system
```

After the restart, logs were clean — all controllers started with no errors.
