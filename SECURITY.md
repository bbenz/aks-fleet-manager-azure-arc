# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for a security vulnerability. Use
GitHub's [private vulnerability
reporting](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository instead.

## Scope and intent

This is **demonstration infrastructure**, not a production reference
architecture. Several defaults deliberately trade security/resilience
hardening for cost and simplicity, and are documented as such in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md):

- **EKS nodes run in public subnets with public IPs** and no NAT gateway. A
  production cluster should use private subnets plus NAT or VPC endpoints.
- **All three storefronts are exposed on public LoadBalancers with no TLS,
  authentication, or WAF.** Custom DNS and certificates are explicit
  non-goals.
- **GKE is a single-zone cluster** with `deletion_protection = false`.
- **AKS uses the Free SKU tier**, which carries no uptime SLA.
- **No network policy, service mesh, or mTLS** between services.

Do not deploy this into a production account, a shared production
subscription, or any environment holding real data. Tear it down with
`make destroy` when you're finished.

## Credential handling

This repository is designed so that no credential ever needs to be committed:

- Cloud authentication is **always** via each provider's official interactive
  login (`az login`, `aws sso login`, `gcloud auth login`). Nothing here
  accepts, stores, or exchanges a raw username/password.
- Real values live in `.env`, which is gitignored. Only `.env.example` is
  committed, and it contains no real identifiers.
- Terraform state and `*.tfvars` are gitignored; `*.tfvars.example` is not.
- `scripts/lib/secret-scan.ps1` scans everything that would actually be
  committed for high-confidence secret patterns, and runs in CI on every push
  and pull request.

If you believe a credential has been committed to this repository, report it
privately as above — and rotate it immediately regardless.
