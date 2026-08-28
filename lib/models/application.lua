local class = require("../core/class")
local User = require("./user")
local Team = require("./team").Team

local AppInstallParams = class("AppInstallParams")
function AppInstallParams.new(data)
    data = data or {}
    local self = { scopes = data.scopes or {}, permissions = data.permissions }
    setmetatable(self, { __index = AppInstallParams })
    return self
end

function AppInstallParams:to_dict()
    return { scopes = self.scopes, permissions = self.permissions }
end

local IntegrationTypesConfig = class("IntegrationTypesConfig")
function IntegrationTypesConfig.new(data)
    data = data or {}
    local self = {}
    setmetatable(self, { __index = IntegrationTypesConfig })
    for key, value in pairs(data) do
        self[key] = { oauth2_install_params = value.oauth2_install_params and AppInstallParams.new(value.oauth2_install_params) or nil }
    end
    return self
end

function IntegrationTypesConfig:to_dict()
    local result = {}
    for key, value in pairs(self) do
        if type(value) == "table" and value.oauth2_install_params then
            result[key] = { oauth2_install_params = value.oauth2_install_params:to_dict() }
        end
    end
    return result
end

local AppInfo = class("AppInfo")
function AppInfo.new(data, http)
    data = data or {}
    local self = {
        id = data.id,
        name = data.name,
        description = data.description,
        icon = data.icon,
        cover_image = data.cover_image,
        rpc_origins = data.rpc_origins,
        bot_public = data.bot_public ~= false,
        bot_require_code_grant = data.bot_require_code_grant or false,
        verify_key = data.verify_key,
        guild_id = data.guild_id,
        primary_sku_id = data.primary_sku_id,
        slug = data.slug,
        terms_of_service_url = data.terms_of_service_url,
        privacy_policy_url = data.privacy_policy_url,
        approximate_guild_count = data.approximate_guild_count,
        approximate_user_install_count = data.approximate_user_install_count,
        approximate_user_authorization_count = data.approximate_user_authorization_count,
        flags = data.flags,
        redirect_uris = data.redirect_uris,
        interactions_endpoint_url = data.interactions_endpoint_url,
        role_connections_verification_url = data.role_connections_verification_url,
        event_webhooks_url = data.event_webhooks_url,
        event_webhooks_status = data.event_webhooks_status,
        event_webhooks_types = data.event_webhooks_types,
        tags = data.tags,
        custom_install_url = data.custom_install_url,
        owner = data.owner and User.new(data.owner) or nil,
        bot = data.bot and User.new(data.bot) or nil,
        team = data.team and Team.new(data.team) or nil,
        install_params = data.install_params and AppInstallParams.new(data.install_params) or nil,
        integration_types_config = data.integration_types_config and IntegrationTypesConfig.new(data.integration_types_config) or nil,
        http = http,
    }
    setmetatable(self, { __index = AppInfo })
    return self
end

function AppInfo:edit(opts)
    if not self.http then error("AppInfo has no http client attached, cannot edit", 0) end
    local Route = require("../http/route")
    local data = Route.new(self.http):edit_current_application(opts or {})
    return AppInfo.new(data, self.http)
end

return {
    AppInfo = AppInfo,
    PartialAppInfo = AppInfo,
    AppInstallParams = AppInstallParams,
    IntegrationTypesConfig = IntegrationTypesConfig,
}
