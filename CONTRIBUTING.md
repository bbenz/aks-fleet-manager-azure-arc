# Contributing

Thanks for your interest. This is a demonstration repository, so the bar for
changes is "does it make the demo clearer, cheaper, or more reliable to
reproduce?"

## Before you open a PR

Run the local checks — all three are also enforced in CI:

```powershell
make fmt           # terraform fmt -recursive
make lint          # terraform validate on every root (+ tflint if installed)
make secret-scan   # high-confidence secret patterns across committed files
```

## Ground rules

**Never commit secrets or real account identifiers.** `.gitignore` is the
primary control and `scripts/lib/secret-scan.ps1` is the safety net. Real
values belong in your local `.env` (gitignored); only `.env.example` is
committed, and it must stay free of real subscription IDs, account numbers,
project IDs, and email addresses.

**Never commit Terraform state or `*.tfvars`.** `terraform.tfvars` is
generated from your `.env` by `scripts/03-init-plan.ps1`. Only
`*.tfvars.example` is committed.

**Don't fork the application manifests per cloud.** The entire point of this
demo is that `kubernetes/base/` has zero cloud-specific content. Cloud
differences belong in `kubernetes/overrides/` as Fleet `ResourceOverride`
rules — one file per concern, one `overrideRule` per cloud.

**Don't hardcode names, regions, or IDs in committed files.** Resource names
derive from `NAME_PREFIX`/`ENVIRONMENT`; regions come from
`scripts/02-select-regions.ps1`. If a manifest genuinely needs a value only
known post-apply (as the AWS subnet annotation does), use a placeholder
token and render it in the relevant script — see
`New-RenderedOverridesDir` in `scripts/07-deploy-workload.ps1` for the
pattern.

**Keep scripts cross-platform.** Never build paths with hardcoded `\`. Use
nested `Join-Path`. See the "Why the code looks like this" section of
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for the specific traps
this repo has already hit.

**Keep every script idempotent and re-runnable.** The operational model is
"fix the one thing that broke, re-run the same numbered script."

## Documenting issues you hit

If you hit a real, reproducible problem, add it to
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) with the symptom, the
cause, and the verified fix. Write it generically — no dates, session
narratives, or personal account identifiers.

## Cost

Anything that changes default node counts, VM sizes, SKUs, or adds a billable
resource must also update the cost table in [README.md](README.md) and the
cost section of [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
