# Step 6: Test & Migrate

## Approach: before / after comparison

### Before (baseline)

```bash
kubectl get nodes -o wide
kubectl get nodeclaims                 # empty — no Karpenter nodes yet
kubectl describe nodes | grep -A 5 "Allocated resources"
```

Result: 3× `t3.small`, each with ~82–88% CPU headroom free, 0 NodeClaims.

### Test 1: light load (did NOT trigger scale-up — correct behavior)

```bash
kubectl apply -f ../manifests/test-scaleup.yaml   # 5 replicas × 500m CPU request
```

**Result:** all 5 pods landed on the existing 3 nodes; **no NodeClaim was
created**. This is correct, not a failure — the pods fit in existing spare
capacity, and Karpenter correctly avoided provisioning unnecessary capacity.
It does *not* prove the scale-up path works on its own — see Test 2.

### Test 2: forced scale-up (proves the actual provisioning path)

Increased the per-pod CPU request so the pods could not fit anywhere existing:

```bash
kubectl scale deployment karpenter-test --replicas=0
# then apply a version requesting 1800m CPU / 512Mi per pod, replicas=3
# (t3.small only has ~1930m allocatable minus overhead, and 3 nodes were
#  already partially used, so this guarantees Pending pods)
```

**Timeline (from Karpenter's own logs):**

| Time (UTC) | Event |
|---|---|
| 08:01:13 | `found provisionable pod(s)` — detected within ~13s of apply |
| 08:01:13–08:01:43 | Tried several instance-type "buckets" (`c4.2xlarge`, `g4dn.2xlarge`, etc.); each failed with `VcpuLimitExceeded` — automatically retried other families |
| 08:01:43 | Succeeded: created NodeClaims for `t3a.xlarge` and `c6a.xlarge` |
| 08:01:45 | Both instances launched |
| 08:02:01 → 08:02:20 | Nodes registered and initialized in Kubernetes |
| ~08:02:26 | All 3 test pods `Running` |
| 08:03:25 | Karpenter **initiated a cost-saving consolidation** — tried replacing the `c6a.xlarge` node with a cheaper `t3a.xlarge` (savings: $0.10/hr); this replacement also hit `VcpuLimitExceeded` and Karpenter **safely aborted**, leaving the original node running rather than leaving the cluster short a node |

This demonstrates three of the diagram's core claims with real evidence:
- **Faster scaling** — Pending → Running in under 90 seconds including EC2
  boot time
- **Better utilization / right-sizing** — automatic fallback across dozens of
  instance types until one with available capacity was found
- **Cost efficient** — unprompted consolidation attempt to save money,
  correctly aborted rather than leaving the cluster in a bad state when it
  couldn't complete safely

### Root cause of the `VcpuLimitExceeded` errors

Account-level EC2 service quota `L-1216C47A` ("Running On-Demand Standard
(A, C, D, H, I, M, R, T, Z) instances") = **16 vCPU**, shared across the whole
account/region — not per-cluster. At the time of testing:

```bash
aws ec2 describe-instances --region $AWS_REGION \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceType" --output text
# t3.small × 6, t3a.xlarge × 1, c6a.xlarge × 1
```

3 of the 6 `t3.small` instances turned out to belong to a **completely
unrelated stack** (`demonodesstack`) in the same account/region — confirmed
via:

```bash
aws ec2 describe-instances --region $AWS_REGION \
  --filters "Name=instance-state-name,Values=running" "Name=instance-type,Values=t3.small" \
  --query "Reservations[].Instances[].{ID:InstanceId,Cluster:Tags[?Key=='aws:eks:cluster-name']|[0].Value,Stack:Tags[?Key=='aws:cloudformation:stack-name']|[0].Value}" \
  --output table
```

Total usage (20 vCPU) exceeded the 16 vCPU quota — expected, given the shared
account-level limit. Not a bug in the migration; a pre-existing account
constraint. See [troubleshooting.md](troubleshooting.md#3-vcpulimitexceeded).

### Cleanup

```bash
kubectl delete deployment karpenter-test

# Watch Karpenter deprovision the now-empty nodes on its own (consolidateAfter: 1m)
kubectl get nodeclaims -w
```

Confirmed result after ~90 seconds: both test NodeClaims gone, back to the
original 3 `t3.small` nodes, total account usage back to 12 vCPU (comfortably
under the 16 vCPU quota).

## Cluster Autoscaler disable step — N/A

The migration diagram calls for disabling Cluster Autoscaler in this step.
**Not applicable here** — Step 1 confirmed no Cluster Autoscaler deployment
existed on this cluster to begin with, so there was nothing to disable or
drain.

## Final state confirmed

| Diagram claim | Confirmed how |
|---|---|
| Karpenter Active | `kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter` → 2/2 Running |
| Small System Node Group | Existing `achin16nodegroupstack` ASG (3× t3.small), untouched throughout |
| Workloads on Karpenter Nodes | Test pods scheduled on 2 Karpenter-launched nodes, then cleanly removed |
| Optimized & Cost Efficient | Unprompted consolidation attempt logged; unnecessary capacity never launched in Test 1 |
