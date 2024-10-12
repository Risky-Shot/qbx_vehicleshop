local vehicles = {}
local blocklist = {}
local VEHICLES = exports.qbx_core:GetVehiclesByName()
local sharedConfig = require 'config.shared'.vehicles
local groupdigits = lib.math.groupdigits
local count = 0

local function insertVehicle(vehicleData, shopType)
    count += 1
    vehicles[count] = {
        shopType = shopType,
        category = vehicleData.category,
        title = ('%s %s'):format(vehicleData.brand, vehicleData.name),
        manufacturer = vehicleData.brand,
        name = vehicleData.name,
        --description = ('%s%s'):format(locale('menus.veh_price'), groupdigits(vehicleData.price)),
        description = ('$ %s'):format(groupdigits(vehicleData.price)),
        args = {
            toVehicle = vehicleData.model
        }
    }
end

for i = 1, #sharedConfig.blocklist do
    local blockveh = sharedConfig.blocklist[i]
    blocklist[blockveh] = true
end

for k, vehicle in pairs(VEHICLES) do
    local vehicleShop = sharedConfig.models[k] or sharedConfig.categories[vehicle.category] or sharedConfig.default

    if blocklist[k] then
        lib.print.debug('Vehicle is blocked. Skipping: ' .. k)
    elseif not vehicleShop then
        lib.print.debug('Vehicle not found in config. Skipping: ' .. k)
    else
        if type(vehicleShop) == 'table' then
            for i = 1, #vehicleShop do
                insertVehicle(vehicle, vehicleShop[i])
            end
        else
            insertVehicle(vehicle, vehicleShop)
        end
    end
end

table.sort(vehicles, function(a, b)
    local _, aName = string.strsplit(' ', string.upper(a.title), 2)
    local _, bName = string.strsplit(' ', string.upper(b.title), 2)

    return aName < bName
end)

return {
    vehicles = vehicles,
    count = count,
}
