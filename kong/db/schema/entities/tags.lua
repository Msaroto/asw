local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "tags",
  primary_key  = { "tag" },
  endpoint_key = "tag",
  dao          = "kong.db.dao.tags",
  db_export = false,

  fields = {
    { tag          = typedefs.tag, },
    { entity_name  = { description = "The name of the Kong Gateway entity being tagged.", type = "string", required = true }, },
    { entity_id    = typedefs.uuid { required = true }, },
  }
}
