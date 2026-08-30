# Troubleshooting Log

Every real issue hit during this migration, in the order encountered, with
root cause and fix. Kept separate from the step docs so it's easy to scan when
something looks familiar.

## 1. OIDC provider not registered

**Symptom:** `aws iam list-open-id-connect-providers` showed an OIDC provider
for a different ID (`<UNRELATED_OIDC_ID>`) than the cluster's
actual issuer (`<OIDC_ID>`). The stray provider was
likely leftover from an unrelated cluster in the same account.

**Impact:** The controller role's IRSA trust policy referenced an OIDC
provider ARN that didn't exist in IAM — would have caused
`AssumeRoleWithWebIdentity` to fail silently once Karpenter tried to use it.

**Fix:**
```bash
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME --region $AWS_REGION --approve
```

**Lesson:** Always verify the OIDC provider for *this specific cluster* is
registered — don't assume "an OIDC provider exists in this account" means
"the right one exists."

---

## 2. Karpenter version incompatible with Kubernetes version

**Symptom:**
```
panic: validating kubernetes version, karpenter version is not compatible with K8s version 1.36
```
Pods `CrashLoopBackOff`, exit code 2, immediately on startup.

**Root cause:** Installed Karpenter `1.1.1`, which only supports much older
Kubernetes versions. Checked the [official compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/):
K8s 1.36 requires Karpenter `>= 1.13`.

**Fix:** Reinstalled with `--version 1.13.1`.

**Lesson:** Always check the compatibility matrix for your *exact* K8s
version before picking a Karpenter version — don't default to "latest major
version I remember" or an old tutorial's pinned version.

---

## 3. Missing IAM permissions for instance-profile management

**Symptom:** Pods `Running` but logs full of:
```
AccessDenied ... not authorized to perform: iam:ListInstanceProfiles
```
repeating every few seconds.

**Root cause:** Karpenter v1's `instanceprofile.garbagecollection` controller
manages EC2 instance profiles itself (create/tag/attach/detach/delete) rather
than requiring a pre-created one — this needs IAM actions beyond the
original minimal policy.

**Fix:** Added to the controller policy: `iam:CreateInstanceProfile`,
`iam:TagInstanceProfile`, `iam:AddRoleToInstanceProfile`,
`iam:RemoveRoleFromInstanceProfile`, `iam:DeleteInstanceProfile`,
`iam:GetInstanceProfile`, `iam:ListInstanceProfiles`. Then:
```bash
aws iam put-role-policy --role-name $KARPENTER_CONTROLLER_ROLE \
  --policy-name KarpenterControllerPolicy \
  --policy-document file://../policies/controller-permissions-policy.json
kubectl rollout restart deployment karpenter -n kube-system
```

---

## 4. `VcpuLimitExceeded` on node launch

**Symptom:**
```
UnfulfillableCapacity ... VcpuLimitExceeded: You have requested more vCPU
capacity than your current vCPU limit of 16 allows...
```
appearing for multiple instance-type buckets in a row before one finally
succeeded.

**Root cause:** AWS account-level EC2 service quota `L-1216C47A` (Standard
A/C/D/H/I/M/R/T/Z on-demand vCPUs) was set to only 16 vCPU, shared across the
**entire account and region** — not per-cluster. Existing instances (this
cluster's 3× `t3.small` **plus** 3× `t3.small` from an unrelated stack,
`demonodesstack`, in the same account) already consumed most of that budget.

**Behavior observed (this is actually good news):** Karpenter did not get
stuck — it automatically tried different instance-type families
(`c4.2xlarge` → `g4dn.2xlarge` → ... → `t3a.xlarge`/`c6a.xlarge`) until it
found one with available quota/capacity, and succeeded.

**Fix applied:** Cleaned up the test workload to release the vCPU back
rather than requesting a quota increase, since this is a sandbox cluster.

**Check your own quota before repeating this:**
```bash
aws service-quotas get-service-quota --region $AWS_REGION \
  --service-code ec2 --quota-code L-1216C47A --query "Quota.Value"

aws ec2 describe-instances --region $AWS_REGION \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceType" --output text
```

**If you need a real increase:** [AWS quota increase guide](https://repost.aws/knowledge-center/ec2-on-demand-instance-vcpu-increase) —
requests can be made via Service Quotas console/CLI; small requests are often
auto-approved within minutes.

---

## 5. `helm registry login public.ecr.aws` fails with 401

**Symptom:**
```
Error: authenticating to "public.ecr.aws": ... response status code 401: denied: Not Authorized
```
when manually entering a username/password.

**Root cause:** `public.ecr.aws` is a public registry — anonymous pulls work
without any login at all. A manual username/password isn't the right
mechanism (it needs an AWS-signed token via `aws ecr-public
get-login-password`, and even that usually isn't necessary just to pull).

**Fix:** Skipped login entirely and ran `helm upgrade --install ...` directly
against `oci://public.ecr.aws/karpenter/karpenter` — worked immediately.

**If you do need to log in** (e.g. hitting anonymous pull rate limits):
```bash
aws ecr-public get-login-password --region us-east-1 | \
  helm registry login --username AWS --password-stdin public.ecr.aws
```
Note: always `us-east-1` for `ecr-public`, regardless of your cluster's
actual region — it's a global endpoint.
