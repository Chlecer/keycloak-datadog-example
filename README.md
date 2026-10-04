# Keycloak + Datadog Tags — Ansible Example

A minimal, copy-paste-ready Ansible example that adds **service-specific Datadog tags**
to an existing Datadog Agent configuration:

- Never touches the API key
- Never removes tags belonging to other services
- Fully idempotent (2nd run → `changed=0`)
- Pure `lineinfile` — no YAML parsing, no extra collections
- Restarts the agent **only** when a tag actually changed
- Local Docker test lab + step-by-step Windows guide

> **Scope:** this repo is a focused example of *Datadog tag management*, not a full
> Keycloak installer. `roles/keycloak/tasks/main.yml` holds a placeholder where your
> real Keycloak install/config tasks go — everything after it is implemented and tested.

## Project structure

```
keycloak-datadog-example/
├── ansible.cfg
├── playbook.yml                  # Main playbook
├── inventory/
│   └── hosts.yml
├── group_vars/
│   └── all.yml                   # Optional global overrides
├── roles/
│   └── keycloak/
│       ├── defaults/main.yml     # keycloak_datadog_tags (edit me)
│       ├── handlers/main.yml     # Restart Datadog agent
│       ├── meta/main.yml
│       └── tasks/
│           ├── main.yml
│           └── datadog_tags.yml  # The actual tag logic
├── tests/
│   ├── docker-compose.yml        # Local test environment
│   └── setup-test-env.sh
├── HOW_TO_TEST_ON_WINDOWS.md
└── README.md
```

## How it works

1. `stat` checks whether `/etc/datadog-agent/datadog.yaml` exists.
2. Each entry in `keycloak_datadog_tags` is ensured by an `ansible.builtin.lineinfile`
   task that anchors on `^tags:` and on the existing line itself.
3. The Datadog Agent handler is notified **only if** a line was added or changed.

## Quick start (Windows + Docker Desktop)

### 1. Start the test container

```powershell
cd tests
docker compose up -d
```

### 2. Prepare the environment (fake Datadog config + Ansible)

```powershell
docker exec -w /ansible keycloak-dd-test bash /ansible/tests/setup-test-env.sh
```

> The project is mounted **read-only** (`:ro`), so the script is invoked through `bash`.
> Running `chmod +x /ansible/tests/setup-test-env.sh` first would fail with
> *"Read-only file system"*.

### 3. Run the playbook

```powershell
docker exec -w /ansible keycloak-dd-test ansible-playbook -i inventory/hosts.yml playbook.yml --connection=local
```

### 4. Verify the result

```powershell
docker exec keycloak-dd-test cat /etc/datadog-agent/datadog.yaml
```

Expected output — original tags preserved, Keycloak tags added:

```yaml
tags:
  - "component:keycloak"
  - "app:keycloak"
  - "service:keycloak"
  - "env:test"
  - "team:platform"
  - "os:linux"
```

> **About the ordering:** `lineinfile` inserts each loop item immediately *after* the
> `tags:` line, so the items appear in reverse order and land **before** the
> pre-existing tags. Datadog treats tags as an unordered set, so this has no functional
> impact — but the output is not in the order you might naively expect.

### 5. Idempotency check

Run step 3 again. You should get `ok` everywhere and `changed=0`.

### 6. Clean up

```powershell
cd tests
docker compose down
```

## Customizing the tags

Edit `roles/keycloak/defaults/main.yml`:

```yaml
keycloak_datadog_tags:
  - "service:keycloak"
  - "app:keycloak"
  - "component:keycloak"
  - "env:production"
  - "team:identity"
```

## Production usage

```yaml
- hosts: keycloak_servers
  roles:
    - role: keycloak
```

The Datadog tags are ensured at the very end of the role.

## Known limitations

Be aware of these before reusing this pattern in production:

| # | Limitation | Impact | Fix |
|---|------------|--------|-----|
| 1 | The `tags:` block must already exist | The `stat` task only checks that the *file* exists. If `tags:` is absent or commented out (as in a stock `datadog.yaml`), `lineinfile` falls back to appending at **EOF**, which corrupts the last key (e.g. `logs_enabled` becomes a string) while adding **no** tags — silently | Create the `tags:` block before inserting, e.g. with `blockinfile` |
| 2 | Detection regexp assumes double quotes | Existing unquoted tags (`- service:keycloak`) are not recognised, so a duplicate line is appended | Use a quote-tolerant regexp, e.g. `^\s*-\s*['"]?{{ item \| regex_escape }}['"]?\s*$` |
| 3 | `ignore_errors: true` on the handler | A failed agent restart is reported as success, so tags would never be reloaded | Move the flag to a test-only variable |
| 4 | `ansible.cfg` ignored inside the test container | Ansible warns about a *world-writable directory*; `stdout_callback`, `become`, `roles_path` from that file do not apply | Works anyway: `become: true` lives in `playbook.yml` and `-i` is passed explicitly |
| 5 | Role installation tasks are placeholders | The role does not actually install Keycloak | Add your real Keycloak tasks in `roles/keycloak/tasks/main.yml` |

None of these affect the documented happy path, which is what the test lab exercises.

## Why this approach?

| Approach | Simplicity | Risk of breaking other tags | Maintainability |
|----------|------------|-----------------------------|-----------------|
| Full template rewrite | Low | High | Poor |
| YAML parse + merge | Medium | Low | Medium |
| **`lineinfile` (this one)** | **Very high** | **Very low**¹ | **Excellent** |

¹ Existing tags are never removed or reordered — but see limitation #1 for the
separate case where no `tags:` block exists at all.

## License

MIT — see [LICENSE](LICENSE).
