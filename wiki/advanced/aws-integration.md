# AWS Integration

## Overview

AI VaultIO can pull secrets from AWS Secrets Manager using SSO authentication. This lets you sync your cloud secrets into your local vault.

## Setup

1. Go to **Settings > AWS Secrets Manager**
2. Configure your SSO settings:
   - **SSO Start URL** — Your AWS SSO portal URL
   - **SSO Region** — The AWS region for SSO (e.g., `us-east-1`)
   - **Account ID** — The AWS account to access
   - **Role Name** — The SSO role with Secrets Manager read access
3. Tap **Sign In** to authenticate via SSO
4. Once connected, your AWS secrets are available for import

## How It Works

```
AI VaultIO -> AWS SSO (browser auth) -> Temporary credentials
           -> AWS Secrets Manager API -> List/Get secrets
           -> Import to local vault (encrypted)
```

## Security

- SSO authentication is handled via the system browser
- Temporary credentials expire automatically
- Imported secrets are encrypted locally with your master PIN
- AWS credentials are not stored — only the SSO session token

## Syncing

- Pull secrets on-demand from the AWS settings screen
- Secrets are imported with their AWS name as the title
- Existing secrets with matching titles can be updated
- Deleted AWS secrets are not automatically removed locally
