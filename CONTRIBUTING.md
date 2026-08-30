# Contributing

Thank you for your interest in contributing to **eks-cas-to-karpenter-migration**!

This repository documents the migration from Cluster Autoscaler to Karpenter on
an Amazon EKS cluster.  Contributions that improve accuracy, add troubleshooting
notes, or extend the manifests/scripts for new use-cases are very welcome.

## Code of Conduct

Please be respectful and constructive in all interactions.

## How to contribute

### Reporting issues

Open a GitHub Issue describing:

- What you expected to happen
- What actually happened (include any error messages / log snippets)
- The Kubernetes and Karpenter versions you are using

### Suggesting improvements

Open an Issue first to discuss the change before submitting a pull request.
This keeps effort aligned and avoids duplicate work.

### Submitting a pull request

1. **Fork** the repository and create a new branch from `main`:

   ```bash
   git checkout -b fix/short-description
   ```

2. **Make your changes** — keep each commit focused on a single concern.

3. **Test locally** where applicable (e.g. `kubectl apply --dry-run=client -f manifests/`).

4. **Open a pull request** against `main`.  Fill in the PR template, link any
   related Issues, and describe *what* changed and *why*.

5. A [code owner](.github/CODEOWNERS) will review and merge once approved.

## Style guide

| Area | Convention |
|---|---|
| Markdown | Wrap prose at ~100 characters; use ATX headings (`#`) |
| YAML manifests | 2-space indent; include `metadata.labels` on every resource |
| Shell scripts | `set -euo pipefail`; quote all variable expansions |
| Commit messages | Imperative mood, ≤72 chars subject line (e.g. `docs: add troubleshooting note for VcpuLimitExceeded`) |

## Repository layout

```
eks-cas-to-karpenter-migration/
├── README.md
├── docs/            # Step-by-step migration guides
├── manifests/       # Kubernetes YAML (EC2NodeClass, NodePool, test workload)
├── policies/        # IAM trust & permissions policies (JSON)
└── scripts/         # Helper shell scripts
```

## License

By contributing you agree that your contributions will be released under the
same license as this project.
