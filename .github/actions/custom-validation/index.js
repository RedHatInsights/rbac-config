const core = require('@actions/core')
const github = require('@actions/github')
const fs = require("fs")
const glob = require("glob")

try {
  const permissionsPath = core.getInput('permissions_path_pattern')

  glob(permissionsPath, {}, function(er, files) {
    files.forEach(file => {
      let permissions = JSON.parse(fs.readFileSync(file, 'utf8'))
      let resourceDefinitions = Object.keys(permissions)

      resourceDefinitions.forEach(resourceDefinition => {
        let permissionDetails = permissions[resourceDefinition]
        let verbsForResource = permissionDetails.map(detail =>
          Object.keys(detail).filter(detailKey =>
            detailKey == 'verb'
          ).map(detailKey =>
            detail[detailKey]
          ).reduce((prev, curr) =>
            prev.concat(curr)
          )
        )

        permissionDetails.forEach(detail => {
          let currentVerb = detail.verb
          let requires = detail.requires
          let validVerbs = verbsForResource.filter(v => v !== currentVerb)
          if (requires) {
            requires.forEach(requiredVerb => {
              let valid = validVerbs.includes(requiredVerb)
              if (!valid) {
                let err = `The required verb "${requiredVerb}" is not one of ${JSON.stringify(validVerbs)}`
                core.setFailed(err)
              }
            })
          }
        })
      })
    })
  })
} catch (error) {
  core.setFailed(error.message)
}
