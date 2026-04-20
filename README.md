# When you can expect that your change will appear in stage and production

Stage: Every Tuesday
Prod: Every Thursday

Note: Reviews will be done same days but for all config PRs.

# Predefined roles and access for Insights Role Based Access Control README

About
=====

Repository for housing decoupled RBAC service roles and permissions configs, which will be seeded into each
tenant/account.

Platform default roles are the roles associated with the platform default group, which defines the default
permissions for a principal. These roles cannot be modified from the UI or the API.

RBAC service repo: https://github.com/RedHatInsights/insights-rbac

RBAC platform doc: https://consoledot.pages.redhat.com/docs/dev/services/rbac.html

Development
===========

After you clone the RBAC service repo, replace the contents in the `insights-rbac/rbac/management/role/(definitions|permissions)` folders
with the json files in the `configs` folders of `rbac-config`.


Contributing
=============
The RBAC config for permissions and roles are namespaced per environment in `/configs/(stage|prod)/`.
Make the appropriate changes you need, per environement, based on when you need them to be promoted.

Canned roles
-------------

Add new roles

Follow existing examples to add roles including name, description, `system` flag, access with permissions.
If you want the new role to be associated with platform default group (which defines the default permissions
for principals in a tenant), you have to add the `platform_default` flag and set it as true.
Set the version to 2 for the new role in order to trigger the seeding in the rbac service.

Format of permissions

The permission should have the format of `<application>:<resource>:<action>`. There are no restrictions on the
resource or action word, i.e. you could define any resource or action. It is up to the app team to determine how to use the
resource and action themselves.

~~~~~~~~~~
Attention:
The permission for the canned roles will also be supported automatically currently, but please add them in the configs/<env>/permissions folder. We will treat the ones not added there as permissions to be removed in the future.
See "Add new permissions" section below for more details.
~~~~~~~~~~

Update roles

When you update the role, please change the version number of the role for the service to pick up new features.
If you need to update the name of a role, add or update the `display_name` field in the role config, as this is the
the database value displayed in the UI. If you do not have this set, RBAC defaults `display_name` to the value
of the `name` field in your role config.

Delete roles

Currently, if you delete a role from the config, it will still exist. Please reach out to RBAC team to delete them from database.


Add new permissions
-------------------

In the permissions directory, the json files define the supported permissions for each app. The file name indicates the name of the app.
E.g. approval.json contains `"requests": [{"verb": "create"}]`, therefore, permission `"approval:requests:create"` is added to rbac Permission table.
When trying to create custom roles, this `"approval:requests:create"` could be added to the access of the role.
If you want the permission `"catalog:requests:*"` available for selection, catalog.json should contain `"requests": [{{"verb": "create"}, {"verb": "*"}]`.

Adding a description to the permission could be done by adding a field `"description"`, e.g.,
```json
{
  "requests": [
    {
      "verb": "create",
      "description": "Describing the permission"
    }
  ]
}
```

You may also explicitly define that one permission verb require another permission
verb for the same application and resource type. This is defined as an additional
field on the permission, similar to `"description"`, e.g.,
```json
{
  "requests": [
    {
      "verb": "create",
      "requires": [
        "read"
      ]
    },
    {
      "verb": "read"
    }
  ]
}
```
This will ensure that RBAC enforces a requirement so that whenever a custom role
is created with the `app:requests:create` permission via the API, the `app:requests:read`
permission must also be supplied in the request, otherwise the API will return a 400.

The `requires` field is expected to be an array, and is restricted to verbs which
exist for the current app/resource type.

Please check existing files for more samples.

Building the Kessel schema
--------------------------

Quickstart (recommended)

Use the helper script to install tools and build the schema:

 ```sh
  # From repo root
  scripts/build-schema.sh --install -e stage
  # Or for prod
  scripts/build-schema.sh -e prod
  # Build test schema into _private/test-schema/
  scripts/build-schema.sh -e stage --test
  ```
  
Prerequisites

1. A recent go version (1.22+) - The Makefile will automatically check if Go is installed

2. Install the required Go tools by running:

    ~~~sh
    make init
    ~~~

3. (Optional) Verify the tools are installed:

    ~~~sh
    make check-go-tools
    ~~~

**Note**: You don't need to add `$GOBIN` to your PATH. The Makefile automatically uses the correct Go binary path from `go env GOPATH`.

### Building test schemas

To build test schemas:

  ~~~sh
  make ksl-test-schema-stage  # for stage
  make ksl-test-schema-prod   # for prod
  ~~~

The test schemas are written to `_private/test-schema/stage-schema.zed` and `_private/test-schema/prod-schema.zed`

Admin Default Role
------------------
We added support for the new role flag `admin_default`, similar to `platform_default`, to allow for admin roles to automatically be assigned to org admins (not admins via the RBAC admin role). By default we will have the `admin_default` flag set to false. An example of what an admin role only assigned to admins by default may look like:

```json
{
  "roles": [
    {
      "name": "Service administrator",
      "description": "Perform any available operation against any Service resource.",
      "system": true,
      "platform_default": false,
      "admin_default": true,
      "version": 1,
      "access": [
        {
          "permission": "service:*:*"
        }
      ]
    }
  ]
}
```

External Roles
---------------------
We added support to define external roles. In the `roles` directory, an external role can be defined as a regular role but without access/permissions. An external should have an object `external` defined, which has external `id` and external `tenant` fields. An example ocm role is displayed below.
```json
{
  "roles": [
    {
      "name": "OCM Cluster Owner",
      "description": "This role provides cluster owner permission.",
      "system": true,
      "version": 2,
      "external": {
        "id": "ClusterOwner",
        "tenant": "ocm"
      }
    }
  ]
}
```
After the role is seeded into system, the role can be assigned to users through groups, and the external tenant team can use the external id of the RBAC role to identify it and map it to one of their roles.

Deployment
==========
Once your PR is merged, an automated PR will be created with your changes applied as
a ConfigMap in the templates within `/_private/configmaps/(stage|prod)/`
for roles and permissions.

Once this PR is merged, an MR will need to be created againts the corresponding
`resourceTemplate`(s) and namespace(s) in `app-interface`: https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/insights/rbac/deploy.yml
to bump the `ref` which will deploy your changes to the specified environment(s).

