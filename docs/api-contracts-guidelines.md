# API Contracts Guidelines

## Repository Structure

Configurations are namespaced by environment under `configs/(stage|prod)/`, each containing three subdirectories:

- `permissions/` -- permission definitions per application (one JSON file per app)
- `roles/` -- role definitions per application (one JSON file per app)
- `schemas/` -- Kessel schema language (KSL) source files and generated SpiceDB schemas

The `schemas/` directory at the repo root contains the JSON Schema files (`permissions.schema`, `roles.schema`) used for CI validation. The `_private/configmaps/` directory contains auto-generated ConfigMap templates -- never edit these directly.

## Permission Files (`configs/*/permissions/<app>.json`)

### File naming
The filename (without `.json`) is the application name and becomes the first segment of the permission triple. Use lowercase with hyphens for multi-word app names (e.g., `cost-management.json`, `playbook-dispatcher.json`).

### Structure
Each file is a JSON object where keys are resource names and values are arrays of verb objects:

```json
{
  "<resource>": [
    { "verb": "<action>" }
  ]
}
```

This produces permissions in the format `<filename>:<resource>:<verb>`.

### Allowed verbs
The schema enforces an enum: `*`, `read`, `write`, `create`, `update`, `upload`, `delete`, `list`, `link`, `unlink`, `order`, `execute`, `view`, `grant`, `revoke`. No other verbs are valid.

### Wildcard resource
Use `"*"` as a resource key to define wildcard permissions (e.g., `app:*:read` or `app:*:*`). Most apps include at minimum `"*": [{"verb": "*"}]` for full-access roles.

### Resource naming conventions
- Simple lowercase nouns: `hosts`, `groups`, `policies`, `domains`
- Dot-separated hierarchical resources: `aws.account`, `openshift.cluster`, `cve.business_risk_and_status`, `system.opt_out`
- Hyphenated compound names: `chart-recommendations`, `disable-recommendations`
- Underscore compound names: `cost_model`, `activation_keys`

There is no enforced convention for separator choice within resource names -- follow the existing pattern for the application.

### Optional fields on verbs
- `description` (string) -- human-readable description of the permission. Rarely used in practice (only `ansible-wisdom-admin-dashboard.json` uses it currently).
- `requires` (array of verb strings) -- declares that selecting this verb in a custom role requires another verb for the same app and resource. RBAC returns 400 if the requirement is not met. Not currently used in any config but supported by the schema.

### Minimum content
Every permission file must define at least one resource with at least one verb. The schema enforces `minProperties: 1` at both levels. The file must not contain properties beyond `verb`, `description`, and `requires` on verb objects.

## Role Files (`configs/*/roles/<app>.json`)

### Structure
Each file contains a `roles` array. Every role object requires `name`, `description`, `system`, and `version`, plus either `access` or `external` (mutually exclusive via `oneOf`).

### Required fields
| Field | Type | Notes |
|-------|------|-------|
| `name` | string | Internal identifier, used as `display_name` fallback. Cannot be renamed -- use `display_name` instead. |
| `description` | string | Human-readable purpose of the role. |
| `system` | boolean | Always `true` for configs in this repo (these are system-managed roles). |
| `version` | integer | Must be incremented on any role change to trigger re-seeding. Set to 2+ for new roles. |

### Optional fields
| Field | Type | Notes |
|-------|------|-------|
| `display_name` | string | The name shown in the UI. Set this when the `name` value differs from the desired display. |
| `platform_default` | boolean | If `true`, role is added to the platform default group (all users get it). |
| `admin_default` | boolean | If `true`, role is automatically assigned to org admins. |

### Version bumping rules
- Increment `version` on every change to a role (new permissions, changed flags, updated description).
- New roles should start at version 2 or higher to trigger seeding.
- Forgetting to bump the version means the RBAC service will not pick up the change.

### Access entries
Each entry in the `access` array requires a `permission` string matching the pattern `<app>:<resource>:<action>` where action must be one of the allowed verbs or `*`. A role can reference permissions from other applications (cross-app permissions are common -- e.g., `compliance` roles include `remediations:remediation:read`).

### resourceDefinitions and attributeFilter
An access entry may optionally include `resourceDefinitions`, an array of objects each containing an `attributeFilter`:

```json
{
  "permission": "playbook-dispatcher:run:read",
  "resourceDefinitions": [
    {
      "attributeFilter": {
        "key": "service",
        "operation": "equal",
        "value": "remediations"
      }
    }
  ]
}
```

The `attributeFilter` requires all three fields:
- `key` (string) -- the attribute to filter on
- `operation` (string) -- only `"equal"` or `"in"` are valid
- `value` (string) -- the filter value

In practice, `resourceDefinitions` are used exclusively for scoping `playbook-dispatcher:run:read` to a specific service (e.g., `"value": "remediations"`, `"value": "tasks"`, `"value": "config_manager"`).

### External roles
Roles managed by an external system use `external` instead of `access`:

```json
{
  "name": "OCM Cluster Editor",
  "system": true,
  "version": 3,
  "external": {
    "id": "ClusterEditor",
    "tenant": "ocm"
  }
}
```

External roles have no permissions in this config -- the external tenant maps them to its own authorization model.

### Role naming pattern
Roles follow the pattern `<Service> <level>` where level is typically one of: `administrator`, `viewer`, `editor`, `user`, `operator`. The `display_name` uses sentence case (e.g., `"Cost Price List viewer"` not `"Cost Price List Viewer"`).

## Role deletion
Removing a role file does not delete it from the database. Contact the RBAC team to delete roles.

## Environment Parity
Stage and prod have the same directory structure and typically identical file lists. Changes should be made to both environments unless intentionally testing in stage first. The same permission and role schemas validate both environments.

## Kessel Schema (KSL) Files

Files in `configs/*/schemas/src/*.ksl` define the Kessel/SpiceDB authorization schema. Key patterns:

- Each service namespace imports `rbac` and uses extensions to map V1 permissions to V2 relations.
- `@rbac.add_v1_based_permission(app, resource, verb, v2_perm)` maps a V1 `app:resource:verb` permission to a V2 permission name, enabling workspace-scoped authorization.
- `@rbac.add_unified_permission(app, resource, verb)` is used when V1 and V2 share the same permission name format.
- `@rbac.add_v1only_permission(perm)` marks permissions that exist in V1 but have no V2 equivalent (deprecated permissions).
- `@rbac.add_contingent_permission(first, second, contingent)` creates a derived permission requiring two other permissions simultaneously.
- `configs/*/schemas/migrated_apps.lst` lists apps that have been migrated to the Kessel schema.
- `configs/*/schemas/hostsonly_apps.lst` lists apps that only need host-level permissions (currently empty in both stage and prod).
- `rbac_v1_permissions.json` is a generated build artifact (gitignored) -- never edit it manually.
- The generated `schema.zed` file is committed and validated by SpiceDB in CI.

## CI Validation Pipeline

The PR workflow (`.github/workflows/pr.yml`) enforces:

1. All `configs/*/permissions/*.json` files validate against `schemas/permissions.schema`.
2. All `configs/*/roles/*.json` files validate against `schemas/roles.schema`.
3. Permission dependency validation (ensures `requires` references exist).
4. KSL schema generation and SpiceDB validation for both stage and prod.

On merge to master, the master workflow auto-generates ConfigMaps and updated schemas, then opens an automated PR to the `configmaps-schema` branch.

## Common Patterns and Conventions

### Typical app permission set
Most applications define a wildcard entry plus specific resources with granular verbs:
```json
{
  "*": [{ "verb": "*" }],
  "resource1": [{ "verb": "read" }, { "verb": "write" }],
  "resource2": [{ "verb": "read" }]
}
```

### Administrator / viewer role pair
Most apps define at minimum an administrator role (with `app:*:*`) and a viewer role (with specific `read` permissions). Administrator roles typically set `admin_default: true`.

### Cross-app permission references
Roles frequently reference permissions from other apps. The most common cross-app pattern is `playbook-dispatcher` permissions scoped via `resourceDefinitions`, and `remediations:remediation:read/write` included in compliance and other roles.

### Permission files without matching role files
Some apps have a permissions file but no corresponding role file (e.g., `advisor.json`, `integrations.json`, `playbook-dispatcher.json`). Their permissions are referenced by roles defined in other app files. Conversely, some role files exist without a same-named permission file (e.g., `insights.json` roles reference `advisor` permissions).

### Adding a new application
1. Create `configs/stage/permissions/<app>.json` and `configs/prod/permissions/<app>.json`.
2. Create `configs/stage/roles/<app>.json` and `configs/prod/roles/<app>.json` (if the app needs its own roles).
3. If the app is migrating to Kessel, create a `.ksl` file in `configs/*/schemas/src/` and add the app name to `migrated_apps.lst`.
4. Ensure all permissions used in roles are declared in the permissions files.
