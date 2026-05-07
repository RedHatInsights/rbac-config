# Database Guidelines for rbac-config

## Overview

This repository contains no database code. It holds declarative JSON configurations for RBAC roles and permissions that the `insights-rbac` service seeds into each tenant/account database, plus KSL (Kessel Schema Language) schema files that compile into SpiceDB authorization schemas (`.zed`). Changes here propagate to databases indirectly through a ConfigMap deployment pipeline.

## Role Seeding and the Version Field

- Every role has an integer `version` field. The RBAC service uses this value to detect changes during seeding. **You must increment `version` when modifying any aspect of a role** (permissions, description, flags, display_name). If you do not increment it, the service will not pick up the change.
- For brand-new roles, set `version` to `2` (not `1`) to ensure initial seeding is triggered.
- The `version` is compared against the value stored in the database; only a higher version triggers an update.

## Role Deletion Is Not Automatic

- Removing a role JSON file or removing a role entry from a file does **not** delete it from the database. The seeding process is additive only.
- To delete a role from tenant databases, you must coordinate with the RBAC team for manual database removal.
- This means orphaned roles can persist indefinitely. Never assume that removing config equals removing from production.

## The `name` Field Is the Database Primary Key

- The `name` field in role configs is the stable identifier used to match config entries to database records during seeding. Never change a role's `name` to "rename" it -- this creates a new role and orphans the old one.
- To change what users see in the UI, set or update the `display_name` field instead. If `display_name` is absent, the RBAC service defaults to showing `name`.

## Permission Format and Database Storage

- Permissions follow the strict format `<application>:<resource>:<action>` and are stored in the RBAC Permission table.
- Valid actions are constrained by schema: `*`, `read`, `write`, `create`, `update`, `upload`, `delete`, `list`, `link`, `unlink`, `order`, `execute`, `view`, `grant`, `revoke`.
- The permission filename (e.g., `advisor.json`) determines the application name in the `app:resource:verb` triple.
- Permissions defined in role configs are auto-registered, but must also be explicitly declared in the `configs/<env>/permissions/` directory. Undeclared permissions will eventually be treated as candidates for removal.

## Permission Dependencies (`requires`)

- The `requires` field on a permission verb enforces a database-level constraint: when creating a custom role via the API, the required permission must also be included or the API returns a 400 error.
- `requires` values must reference verbs that exist for the same app/resource type within the same permissions file.

## Resource Definitions and Attribute Filters

- Roles can include `resourceDefinitions` with `attributeFilter` objects. These create fine-grained access entries in the database scoped by key/value pairs.
- Only `equal` and `in` operations are supported. These filters are stored alongside the permission in the database access table.

## Role Flags and Their Database Effects

| Flag | Default | Database behavior |
|------|---------|-------------------|
| `system` | required, always `true` | Marks the role as system-managed; cannot be modified via UI/API |
| `platform_default` | `false` | Role is auto-assigned to the platform default group for every tenant |
| `admin_default` | `false` | Role is auto-assigned to org admins (not RBAC admin role holders) |

- A role must have either `access` (with permissions) or `external` (with `id` and `tenant`), never both. This is enforced by the JSON schema's `oneOf` constraint.

## External Roles

- External roles (e.g., OCM roles) have no `access` array. Instead they carry an `external` object with `id` and `tenant` fields.
- These are seeded into the database as role records but the actual permission mapping is owned by the external tenant system (e.g., OCM maps `ClusterOwner` to its own authorization model).

## Environment Isolation: Stage vs. Prod

- Configurations are namespaced per environment under `configs/stage/` and `configs/prod/`.
- Stage and prod can have different role definitions, permission sets, KSL schemas, and migration lists. Always make changes in the correct environment directory.
- Stage deploys every Tuesday; prod deploys every Thursday. Changes must be merged to `master` before the deployment window.
- Stage is typically used to test changes before promoting them to prod. In many cases you will need matching changes in both directories.

## KSL Schema and the Kessel/SpiceDB Authorization Model

### Schema Structure

- KSL source files live in `configs/<env>/schemas/src/*.ksl` and compile to `configs/<env>/schemas/schema.zed` (SpiceDB format).
- Each KSL file declares a `namespace` and defines how V1 RBAC permissions map to the V2 relation-based authorization model.
- The compiled `.zed` schema is validated by `authzed/action-spicedb-validate` in CI.

### Key KSL Types Map to Database Entities

| KSL Type | Database/Auth Concept |
|----------|----------------------|
| `rbac/tenant` | An organization/account; the top-level isolation boundary |
| `rbac/platform` | Platform-wide bindings (platform_default roles) |
| `rbac/workspace` | A hierarchical container; workspaces parent to tenant or other workspaces |
| `rbac/role` | A seeded role with computed permission relations |
| `rbac/role_binding` | Links subjects (principals/groups) to roles at a scope |
| `rbac/principal` | A user identity |
| `rbac/group` | A group containing principals or nested group members |
| `hbi/host` | A host resource scoped to a workspace |

### Three Extension Patterns for Permissions

1. **`add_v1_based_permission`** -- Maps a V1 permission (`app:resource:verb`) to a V2 permission name. Use when the V2 permission name differs from the V1 format. Generates wildcard resolution chains (`app_resource_verb`, `app_resource_all`, `app_all_verb`, `app_all_all`, `all_all_all`).

2. **`add_unified_permission`** -- Use when the V1 and V2 permission share the same `app_resource_verb` naming. Adds a `[bool]` box expression making the relation directly writable in addition to derivable from wildcards. Used for RBAC's own permissions (e.g., `rbac:principal:read`).

3. **`add_v1only_permission`** -- Assigns a permission to the role only, without propagating it through workspaces. Used for migration-period permissions that will not exist in V2.

### Host-Centric Permissions Require Contingent Patterns

- Services that operate on hosts (advisor, patch, vulnerability, malware-detection, ros, compliance) use a two-step pattern:
  1. `add_v1_based_permission` to create an `_assigned` permission
  2. `add_contingent_permission` to intersect `inventory_host_view` with the `_assigned` permission
- This enforces that a user must have host visibility AND the service-specific permission. The `hbi.expose_host_permission` extension then makes the permission checkable on individual host objects.

### Migration Lists Control Schema Generation

- `migrated_apps.lst` -- Apps whose permissions are included in the compiled schema. Stage and prod can differ as apps migrate at different rates.
- `hostsonly_apps.lst` -- Apps that only have host-scoped permissions (currently empty in both environments).
- The `generate-v1-only-permissions` tool reads these lists plus the permission JSONs to produce `rbac_v1_permissions.json` (a build artifact, gitignored).

## Tenant/Account Isolation

- Isolation is structural: each tenant has its own `rbac/tenant` object in the authorization model with a dedicated `rbac/platform` for platform-default bindings.
- Workspaces form a hierarchy (`workspace -> parent workspace -> tenant`). Permissions inherit downward through the `parent` relation.
- Role bindings are scoped: a binding at the platform level applies globally for the tenant; a binding at a workspace level applies only within that workspace subtree.

## Deployment Pipeline and Database Updates

1. PR merged to `master` triggers the `master.yml` workflow.
2. The workflow generates ConfigMaps in `_private/configmaps/<env>/` and compiles KSL schemas.
3. An automated PR is created with the ConfigMap/schema changes.
4. After that PR merges, an MR must be filed against `app-interface` to bump the `ref` in the `resourceTemplate`, which triggers actual deployment.
5. The RBAC service reads the ConfigMap at startup/refresh and seeds roles/permissions into each tenant's database.

## CI Validation Rules

- All permission JSONs are validated against `schemas/permissions.schema`.
- All role JSONs are validated against `schemas/roles.schema`.
- Permission dependency chains (`requires` fields) are validated for consistency.
- KSL source files are compiled and the resulting `.zed` files are validated by SpiceDB.
- Schema generation is deterministic: changes to permissions or KSL sources must produce a valid, consistent `.zed` output.

## Common Pitfalls

- **Forgetting to increment `version`**: The most common cause of "my change didn't take effect." The database record will not be updated.
- **Deleting a role config and expecting removal**: It will remain in the database. Contact the RBAC team.
- **Changing `name` instead of `display_name`**: Creates a duplicate role in the database.
- **Adding permissions to roles but not to the permissions directory**: The permission works initially but is a candidate for future cleanup/removal.
- **Mismatched stage/prod**: Forgetting to propagate a change to the other environment when both need it.
- **KSL app name vs permission app name**: In KSL, hyphens in app names are replaced with underscores (e.g., `malware-detection` becomes `malware_detection` in KSL `app:` parameters). The resource names may also differ between the permission JSON keys and the KSL parameters.
