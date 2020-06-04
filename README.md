# Predefined roles and access for Insights Role Based Access Control README

About
=====

Repository for housing decoupled RBAC service roles and permissions configs, which will be seeded into each
tenant/account.

Platform default roles are the roles associated with the platform default group, which defines the default
permissions for a principal. These roles cannot be modified from the UI or the API.

RBAC service repo: https://github.com/RedHatInsights/insights-rbac

RBAC platform doc: https://platform-docs.cloud.paas.psi.redhat.com/backend/rbac.html

Development
===========

After you clone the RBAC service repo, replace the contents in the insights-rbac/rbac/management/role/definitions folder 
with the json files in the configs folder of rbac-config.


Contributing
=============

Canned roles
-------------

Add new roles

Follow existing examples to add roles including name, description, system flag, access with permissions.
If you want the new role to be associated with platform default group (which defines the default permissions
for principals in a tenant), you have to add the platform_default flag and set it as true.
Set the version to 2 for the new role in order to trigger the seeding in the rbac service.

Format of permissions

The permission should have the format of `<application>:<resource>:<action>`. There are no restrictions on the
resource or action word, i.e. you could define any resource or action. It is up to the app team to determine how to use the
resource and action themselves.

~~~~~~~~~~
Attention:
The permission for the canned roles will also be supported automatically currently, but please add them in the configs/permissions folder. We will treat the ones not added there as permissions to be removed in the future.
See "Add new permissions" section below for more details.
~~~~~~~~~~

Update roles

When you update the role, please change the version number of the role for the service to pick up new features.
If you update the name of the role, it will generate a new role but keep the old one. Please reach out to 
RBAC team to resolve this.

Delete roles

Currently, if you delete a role from the config, it will still exist. Please reach out to RBAC team to delete them from database.


Add new permissions
-------------------

In the permissions directory, the json files define the supported permissions for each app. The file name indicates the name of the app.
E.g. approval.json contains `"requests": ["create"]`, therefore, permission `"approval:requests:create"` is added to rbac Permission table.
When trying to create custom roles, this `"approval:requests:create"` could be added to the access of the role.
If you want the permission `"catalog:requests:*"` available for selection, catalog.json should contain `"requests": ["create", "*"]`.

Please check existing files for more samples.

Deployment
==========
When your PR is merged to master/qa/prod branch, it will take up to 1 day to seed new roles in CI/QA/PROD, as we have a daily task to update any new config. 
If you need the roles available faster, please reach out to RBAC team.
