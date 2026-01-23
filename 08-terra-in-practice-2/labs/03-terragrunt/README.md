# Lab 3: Terragrunt

## Overview

DRY configuration with inheritance. Provider and backend config defined once in root.

## Structure

```
03-terragrunt/
├── terragrunt.hcl         ← Root config (generates provider.tf)
├── modules/
│   └── app-stack/         ← Same module as Lab 2
└── environments/
    ├── dev/
    │   └── terragrunt.hcl ← Just inputs (~25 lines)
    ├── staging/
    │   └── terragrunt.hcl
    └── prod/
        └── terragrunt.hcl
```

## Prerequisites

Install Terragrunt:

```bash
# macOS
brew install terragrunt

# Linux
curl -LO https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
```

## Commands

```bash
# Deploy single environment
cd environments/dev
terragrunt init
terragrunt plan
terragrunt apply

# Deploy ALL environments at once
cd environments
terragrunt run-all plan
terragrunt run-all apply --terragrunt-non-interactive
```

## Try This

1. Deploy dev and look at the generated `provider.tf`
2. Compare file sizes between Lab 2 and Lab 3 environment folders
3. Use `terragrunt run-all apply` to deploy everything

## Key Insight

Each environment folder has ONE file. Everything else is inherited or generated.

```bash
# Lab 2: 4-5 files per environment
ls environments/dev/  # main.tf, providers.tf, outputs.tf, ...

# Lab 3: 1 file per environment
ls environments/dev/  # terragrunt.hcl (that's it)
```

## Cleanup

```bash
cd environments
terragrunt run-all destroy --terragrunt-non-interactive
```
