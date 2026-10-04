# How to Test This Project on Windows (with Docker Desktop)

Prerequisites: Docker Desktop running with the engine started.

All commands below are run from **PowerShell** on the Windows host unless
explicitly marked as running *inside the container*.

## Step-by-step

### 1. Go to the project folder

```powershell
cd C:\path\to\keycloak-datadog-example
```

### 2. Start the test container

```powershell
cd tests
docker compose up -d
```

This starts an Ubuntu 22.04 container named `keycloak-dd-test` with the project
mounted at `/ansible` (read-only).

### 3. Prepare the environment

```powershell
docker exec -w /ansible keycloak-dd-test bash /ansible/tests/setup-test-env.sh
```

The script installs Ansible, writes a fake `datadog.yaml` with pre-existing tags,
and creates a dummy `datadog-agent` systemd unit.

> **Why `bash script.sh` instead of `chmod +x` then `./script.sh`?**
> The project is mounted `:ro`, so `chmod` fails with *"Read-only file system"*.
> Invoking it through `bash` needs no execute permission.

You will see the current (fake) Datadog tags:

```
tags:
  - "env:test"
  - "team:platform"
  - "os:linux"
```

### 4. Run the Ansible playbook

```powershell
docker exec -w /ansible keycloak-dd-test ansible-playbook -i inventory/hosts.yml playbook.yml --connection=local
```

### 5. Verify the result

```powershell
docker exec keycloak-dd-test cat /etc/datadog-agent/datadog.yaml
```

You should now see:

```yaml
tags:
  - "component:keycloak"
  - "app:keycloak"
  - "service:keycloak"
  - "env:test"
  - "team:platform"
  - "os:linux"
```

The original tags are still there — only the Keycloak ones were added.

> **Note the order:** `lineinfile` inserts each item right after the `tags:` line, so
> the Keycloak tags end up **above** the pre-existing ones and in reverse loop order.
> This is expected and harmless — Datadog treats tags as an unordered set.

### 6. Run it a second time (idempotency test)

```powershell
docker exec -w /ansible keycloak-dd-test ansible-playbook -i inventory/hosts.yml playbook.yml --connection=local
```

You should see all tasks `ok` and `changed=0` — nothing changes because the tags
already exist.

### 7. Clean up

```powershell
cd tests
docker compose down
```

---

## What this proves

- The API key is never touched
- Existing tags from other services are preserved
- New Keycloak tags are added cleanly
- The playbook is fully idempotent

## Heads-up: `ansible.cfg` warning

You will see this warning when running inside the container:

```
[WARNING]: Ansible is being run in a world writable directory (/ansible),
ignoring it as an ansible.cfg source.
```

This is expected on a Windows bind-mount. Ansible ignores `ansible.cfg` in
world-writable directories, so `stdout_callback`, `become`, `roles_path`, etc. from
that file do **not** apply here. The playbook still works because `become: true` is
set in `playbook.yml` and the inventory is passed explicitly with `-i`.
