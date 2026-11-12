# Bring Them Home, Send Them Out

Lumen Parcel is a small, fictional parcel company. Its old platform team kept
credentials in AWS Secrets Manager; its delivery app now builds on GitHub
Actions. Vault becomes the one place those secrets live and change.

## The four acts

1. **Bring them home.** Three legacy secrets sit in the old store
   (LocalStack). Vault's Secrets Import plans the move, then pulls them into
   KV v2 under `parcel/`. The old store is unchanged.
2. **Send them out.** The delivery app's key is associated with two sync
   destinations: GitHub Actions (through the VaultSyncDemo GitHub App) and the
   AWS-shaped store. Vault pushes it; GitHub shows a repository secret
   updated seconds ago.
3. **Change once.** The key is rotated in Vault. Both destinations receive
   the new version; Vault's status and the destinations' own timestamps line
   up.
4. **Let go.** An association is removed. Vault deletes the copy at the
   destination; the source stays in Vault.

## What the lab proves, and what it only illustrates

Proves: Vault can pull existing secrets out of an AWS-shaped store; one change
in Vault reaches GitHub Actions and the AWS-shaped store without either one
connecting back to Vault; removing an association removes the copy; a GitHub
App authenticates Vault to GitHub without a person's token.

Illustrates only: LocalStack stands in for AWS Secrets Manager; Lumen Parcel
and its values are invented; one presenter drives everything; one Mac is not
production.
