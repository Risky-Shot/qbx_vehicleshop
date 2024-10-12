local config = require 'config.client'
local sharedConfig = require 'config.shared'
local vehiclesMenu = require 'client.vehicles'
local VEHICLES = exports.qbx_core:GetVehiclesByName()
local VEHICLES_HASH = exports.qbx_core:GetVehiclesByHash()
local insideShop
local showroomPoints = {}

---@param data VehicleFinanceClient
local function financePayment(data)
    local dialog = lib.inputDialog(locale('menus.veh_finance'), {
        {
            type = 'number',
            label = locale('menus.veh_finance_payment'),
        }
    })

    if not dialog then return end

    local paymentAmount = tonumber(dialog[1])
    TriggerServerEvent('qbx_vehicleshop:server:financePayment', paymentAmount, data.vehId)
end

local function confirmationCheck()
    local alert = lib.alertDialog({
        header = 'Wait a minute!',
        content = 'Are you sure you wish to proceed?',
        centered = true,
        cancel = true,
        labels = {
            cancel = 'No',
            confirm = 'Yes',
        }
    })

    return alert
end

---@param data VehicleFinanceClient
local function showVehicleFinanceMenu(data)
    local vehLabel = ('%s %s'):format(data.brand, data.name)
    local vehFinance = {
        {
            title = 'Finance Information',
            icon = 'circle-info',
            description = ('Name: %s\nPlate: %s\nRemaining Balance: $%s\nRecurring Payment Amount: $%s\nPayments Left: %s'):format(vehLabel, data.vehiclePlate, lib.math.groupdigits(data.balance), lib.math.groupdigits(data.paymentAmount), data.paymentsLeft),
            readOnly = true,
        },
        {
            title = locale('menus.veh_finance_pay'),
            onSelect = function()
                financePayment(data)
            end,
        },
        {
            title = locale('menus.veh_finance_payoff'),
            onSelect = function()
                local check = confirmationCheck()

                if check == 'confirm' then
                    TriggerServerEvent('qbx_vehicleshop:server:financePaymentFull', data.vehId)
                else
                    lib.showContext('vehicleFinance')
                end
            end,
        },
    }

    lib.registerContext({
        id = 'vehicleFinance',
        title = locale('menus.financed_header'),
        menu = 'ownedVehicles',
        options = vehFinance
    })

    lib.showContext('vehicleFinance')
end

--- Gets the owned vehicles based on financing then opens a menu
local function showFinancedVehiclesMenu()
    local vehicles = lib.callback.await('qbx_vehicleshop:server:GetFinancedVehicles')
    local ownedVehicles = {}

    if not vehicles or #vehicles == 0 then
        return exports.qbx_core:Notify(locale('error.nofinanced'), 'error')
    end

    for _, v in pairs(vehicles) do
        local plate = v.props.plate
        local vehicle = VEHICLES[v.modelName]

        plate = plate and plate:upper()

        ownedVehicles[#ownedVehicles + 1] = {
            title = vehicle.name,
            description = locale('menus.veh_platetxt')..plate,
            icon = 'fa-solid fa-car-side',
            arrow = true,
            onSelect = function()
                showVehicleFinanceMenu({
                    vehId = v.id,
                    name = vehicle.name,
                    brand = vehicle.brand,
                    vehiclePlate = plate,
                    balance = v.balance,
                    paymentsLeft = v.paymentsleft,
                    paymentAmount = v.paymentamount
                })
            end
        }
    end

    if #ownedVehicles == 0 then
        return exports.qbx_core:Notify(locale('error.nofinanced'), 'error')
    end

    lib.registerContext({
        id = 'ownedVehicles',
        title = locale('menus.owned_vehicles_header'),
        options = ownedVehicles
    })

    lib.showContext('ownedVehicles')
end

---@param closestVehicle integer
---@return string
local function getVehName(closestVehicle)
    local vehicle = sharedConfig.shops[insideShop].showroomVehicles[closestVehicle].vehicle

    return VEHICLES[vehicle].name
end

---@param closestVehicle integer
---@return string
local function getVehPrice(closestVehicle)
    local vehicle = sharedConfig.shops[insideShop].showroomVehicles[closestVehicle].vehicle

    return lib.math.groupdigits(VEHICLES[vehicle].price)
end

---@param closestVehicle integer
---@return string
local function getVehBrand(closestVehicle)
    local vehicle = sharedConfig.shops[insideShop].showroomVehicles[closestVehicle].vehicle

    return VEHICLES[vehicle].brand
end

---@param targetShowroomVehicle integer Showroom position index
---@param buyVehicle string model
local function openFinance(targetShowroomVehicle, buyVehicle)
    local title = ('%s %s - $%s'):format(VEHICLES[buyVehicle].brand:upper(), VEHICLES[buyVehicle].name:upper(), getVehPrice(targetShowroomVehicle))
    local dialog = lib.inputDialog(title, {
        {
            type = 'number',
            label = locale('menus.financesubmit_downpayment')..sharedConfig.finance.minimumDown..'%',
            min = VEHICLES[buyVehicle].price * sharedConfig.finance.minimumDown / 100,
            max = VEHICLES[buyVehicle].price
        },
        {
            type = 'number',
            label = locale('menus.financesubmit_totalpayment')..sharedConfig.finance.maximumPayments,
            min = 2,
            max = sharedConfig.finance.maximumPayments
        }
    })

    if not dialog then return end

    local downPayment = tonumber(dialog[1])
    local paymentAmount = tonumber(dialog[2])

    if not downPayment or not paymentAmount then return end

    TriggerServerEvent('qbx_vehicleshop:server:financeVehicle', downPayment, paymentAmount, buyVehicle)
end

--- Opens a menu with list of vehicles based on given category
---@param category string
---@param targetVehicle number
local function openVehCatsMenu(category, targetVehicle)
    local categoryMenu = {}
    for i = 1, vehiclesMenu.count do
        local vehicle = vehiclesMenu.vehicles[i]
        if vehicle.category == category and vehicle.shopType == insideShop then
            vehicle.args.closestShop = insideShop
            vehicle.args.targetVehicle = targetVehicle
            vehicle.serverEvent = 'qbx_vehicleshop:server:swapVehicle'

            categoryMenu[#categoryMenu + 1] = vehicle
        end
    end

    table.sort(categoryMenu, function(a, b)
        return string.upper(a.title) < string.upper(b.title)
    end)

    lib.registerContext({
        id = 'openVehCats',
        title = sharedConfig.shops[insideShop].categories[category],
        menu = 'vehicleCategories',
        options = categoryMenu
    })

    lib.showContext('openVehCats')
end

--- Opens a menu with list of vehicle categories
---@param args {targetVehicle: integer}
local function openVehicleCategoryMenu(args)
    local categoryMenu = {}
    local sortedCategories = {}
    local categories = sharedConfig.shops[insideShop].categories

    for k, v in pairs(categories) do
        sortedCategories[#sortedCategories + 1] = {
            category = k,
            label = v
        }
    end

    table.sort(sortedCategories, function(a, b)
        return string.upper(a.label) < string.upper(b.label)
    end)

    for i = 1, #sortedCategories do
        categoryMenu[#categoryMenu + 1] = {
            title = sortedCategories[i].label,
            arrow = true,
            onSelect = function()
                openVehCatsMenu(sortedCategories[i].category, args.targetVehicle)
            end
        }
    end

    lib.registerContext({
        id = 'vehicleCategories',
        title = locale('menus.categories_header'),
        menu = 'vehicleMenu',
        options = categoryMenu
    })

    lib.showContext('vehicleCategories')
end

---@param targetVehicle integer Showroom position index
local function openCustomFinance(targetVehicle)
    local vehicle = sharedConfig.shops[insideShop].showroomVehicles[targetVehicle].vehicle
    local title = ('%s %s - $%s'):format(getVehBrand(targetVehicle):upper(), vehicle:upper(), getVehPrice(targetVehicle))
    local dialog = lib.inputDialog(title, {
        {
            type = 'number',
            label = locale('menus.financesubmit_downpayment')..sharedConfig.finance.minimumDown..'%',
        },
        {
            type = 'number',
            label = locale('menus.financesubmit_totalpayment')..sharedConfig.finance.maximumPayments,
        },
        {
            type = 'number',
            label = locale('menus.submit_ID'),
        }
    })

    if not dialog then return end

    local downPayment = tonumber(dialog[1])
    local paymentAmount = tonumber(dialog[2])
    local playerid = tonumber(dialog[3])

    if not downPayment or not paymentAmount or not playerid then return end

    TriggerServerEvent('qbx_vehicleshop:server:sellfinanceVehicle', downPayment, paymentAmount, vehicle, playerid)
end

---prompt client for playerId of another player
---@param vehModel string
---@return number? playerId
local function getPlayerIdInput(vehModel)
    local dialog = lib.inputDialog(VEHICLES[vehModel].name, {
        {
            type = 'number',
            label = locale('menus.submit_ID'),
            placeholder = 1
        }
    })

    if not dialog then return end
    if not dialog[1] then return end

    return tonumber(dialog[1])
end

---@param vehModel string
local function startTestDrive(vehModel)
    local playerId = getPlayerIdInput(vehModel)

    TriggerServerEvent('qbx_vehicleshop:server:customTestDrive', vehModel, playerId)
end

lib.onCache('vehicle', function(value)
    if value or not LocalPlayer.state.isInTestDrive then return end
    LocalPlayer.state:set('isInTestDrive', nil, true)
end)

---@param vehModel string
local function sellVehicle(vehModel)
    local playerId = getPlayerIdInput(vehModel)

    TriggerServerEvent('qbx_vehicleshop:server:sellShowroomVehicle', vehModel, playerId)
end

--- Opens the vehicle shop menu
---@param targetVehicle number
local function openVehicleSellMenu(targetVehicle)
    local options = {}
    local vehicle = sharedConfig.shops[insideShop].showroomVehicles[targetVehicle].vehicle
    local swapOption = {
        title = locale('menus.swap_header'),
        description = locale('menus.swap_txt'),
        onSelect = openVehicleCategoryMenu,
        args = {
            targetVehicle = targetVehicle
        },
        arrow = true
    }

    if sharedConfig.shops[insideShop].type == 'free-use' then
        if sharedConfig.enableTestDrive then
            options[#options + 1] = {
                title = locale('menus.test_header'),
                description = locale('menus.freeuse_test_txt'),
                serverEvent = 'qbx_vehicleshop:server:testDrive',
                args = {
                    vehicle = vehicle
                }
            }
        end

        if sharedConfig.enableFreeUseBuy then
            options[#options + 1] = {
                title = locale('menus.freeuse_buy_header'),
                description = locale('menus.freeuse_buy_txt'),
                serverEvent = 'qbx_vehicleshop:server:buyShowroomVehicle',
                args = {
                    buyVehicle = vehicle
                }
            }
        end

        if sharedConfig.finance.enable then
            options[#options + 1] = {
                title = locale('menus.finance_header'),
                description = locale('menus.freeuse_finance_txt'),
                onSelect = function()
                    openFinance(targetVehicle, vehicle)
                end
            }
        end

        options[#options + 1] = swapOption
    else
        options[1] = {
                title = locale('menus.managed_sell_header'),
                description = locale('menus.managed_sell_txt'),
                onSelect = function()
                    sellVehicle(vehicle)
                end,
        }

        if sharedConfig.enableTestDrive then
            options[#options + 1] = {
                title = locale('menus.test_header'),
                description = locale('menus.managed_test_txt'),
                onSelect = function()
                    startTestDrive(vehicle)
                end
            }
        end

        if sharedConfig.finance.enable then
            options[#options + 1] = {
                title = locale('menus.finance_header'),
                description = locale('menus.managed_finance_txt'),
                onSelect = function()
                    openCustomFinance(targetVehicle)
                end
            }
        end

        options[#options + 1] = swapOption
    end

    lib.registerContext({
        id = 'vehicleMenu',
        title = ('%s %s - $%s'):format(getVehBrand(targetVehicle):upper(), getVehName(targetVehicle):upper(), getVehPrice(targetVehicle)),
        options = options
    })

    lib.showContext('vehicleMenu')
end

---@param shopName string
---@param entity number vehicle
---@param targetVehicle number
local function createVehicleTarget(shopName, entity, targetVehicle)
    local shop = sharedConfig.shops[shopName]

    exports.ox_target:addLocalEntity(entity, {
        {
            name = 'vehicleshop:showVehicleOptions',
            icon = 'fas fa-car',
            label = locale('general.vehinteraction'),
            distance = shop.zone.targetDistance,
            groups = shop.job,
            onSelect = function()
                openVehicleSellMenu(targetVehicle)
            end
        }
    })
end

---@param shopName string
---@param coords vector4
---@param targetVehicle number
local function createVehicleZone(shopName, coords, targetVehicle)
    local shop = sharedConfig.shops[shopName]

    local boxZone = lib.zones.box({
        coords = coords.xyz,
        size = shop.zone.size,
        rotation = coords.w,
        debug = config.debugPoly,
        onEnter = function()
            if not insideShop then return end

            local job = sharedConfig.shops[insideShop].job
            if job and QBX.PlayerData.job.name ~= job then return end

            lib.showTextUI(locale('menus.keypress_vehicleViewMenu'))
        end,
        inside = function()
            if not insideShop then return end

            local job = sharedConfig.shops[insideShop].job
            if not IsControlJustPressed(0, 38) or job and QBX.PlayerData.job.name ~= job then return end

            openVehicleSellMenu(targetVehicle)
        end,
        onExit = function()
            lib.hideTextUI()
        end
    })
    return boxZone
end

--- Creates a shop
---@param shopShape vector3[]
---@param name string
local function createShop(shopShape, name)
    lib.zones.poly({
        name = name,
        points = shopShape,
        thickness = 5,
        debug = config.debugPoly,
        onEnter = function(self)
            insideShop = self.name
        end,
        onExit = function()
            insideShop = nil
        end,
    })
end

---@param model string
---@param coords vector4
---@return number vehicleEntity
local function createShowroomVehicle(model, coords)
    lib.requestModel(model, 10000)
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, false, true)
    SetModelAsNoLongerNeeded(model)
    SetVehicleOnGroundProperly(veh)
    SetEntityInvincible(veh, true)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleDoorsLocked(veh, 10)
    FreezeEntityPosition(veh, true)
    SetVehicleNumberPlateText(veh, 'BUY ME')

    return veh
end

local function createShowroomVehiclePoint(data)
    local vehPoint = lib.points.new({
        coords = data.coords,
        heading = data.coords.w,
        distance = 300,
        shopName = data.shopName,
        vehiclePos = data.vehiclePos,
        model = data.model,
        veh = nil,
        boxZone = nil
    })

    function vehPoint:onEnter()
        self.veh = createShowroomVehicle(self.model, vec4(self.coords.x, self.coords.y, self.coords.z, self.heading))
        if config.useTarget then
            createVehicleTarget(self.shopName, self.veh, self.vehiclePos)
        else
            self.boxZone = createVehicleZone(self.shopName, self.coords, self.vehiclePos)
        end
    end

    function vehPoint:onExit()
        if config.useTarget then
            exports.ox_target:removeLocalEntity(self.veh, 'vehicleshop:showVehicleOptions')
        else
            self.boxZone:remove()
        end
        if DoesEntityExist(self.veh) then
            DeleteEntity(self.veh)
        end
        self.veh = nil
        self.boxZone = nil
    end
    return vehPoint
end

--- Starts the test drive timer based on time and shop
---@param time integer
local function startTestDriveTimer(time)
    local gameTimer = GetGameTimer()

    CreateThread(function()
        local playerState = LocalPlayer.state
        while playerState.isInTestDrive do
            local currentGameTime = GetGameTimer()
            local secondsLeft = currentGameTime - gameTimer

            qbx.drawText2d({
                text = locale('general.testdrive_timer')..math.ceil(time - secondsLeft / 1000),
                coords = vec2(1.0, 1.38),
                scale = 0.5
            })

            Wait(0)
        end
        exports.qbx_core:Notify(locale('general.testdrive_complete'), 'success')
    end)
end

AddStateBagChangeHandler('isInTestDrive', ('player:%s'):format(cache.serverId), function(_, _, value)
    if not value then return end

    while not cache.vehicle do
        Wait(10)
    end

    exports.qbx_core:Notify(locale('general.testdrive_timenoti', value), 'inform')
    startTestDriveTimer(value * 60)
end)

--- Swaps the chosen vehicle with another one
---@param data {toVehicle: string, targetVehicle: integer, closestShop: string}
RegisterNetEvent('qbx_vehicleshop:client:swapVehicle', function(data)
    local shopName = data.closestShop
    local dataTargetVehicle = sharedConfig.shops[shopName].showroomVehicles[data.targetVehicle]
    local vehPoint = showroomPoints[shopName][data.targetVehicle]

    if not vehPoint or dataTargetVehicle.vehicle == data.toVehicle then return end

    if not IsModelInCdimage(data.toVehicle) then
        lib.print.error(('Failed to find model for "%s". Vehicle might not be streamed?'):format(data.toVehicle))
        return
    end

    dataTargetVehicle.vehicle = data.toVehicle
    vehPoint.model = data.toVehicle
    if vehPoint.currentDistance <= vehPoint.distance then
        vehPoint:onExit()
        vehPoint:onEnter()
    end
end)

local function confirmTrade(confirmationText)
    local accepted

    exports.npwd:createSystemNotification({
        uniqId = "vehicleShop:confirmTrade",
        content = confirmationText,
        secondary = "Confirm Trade",
        keepOpen = true,
        duration = 10000,
        controls = true,
        onConfirm = function()
            accepted = true
        end,
        onCancel = function()
            accepted = false
        end,
    })

    while not accepted do
        Wait(100)
    end

    return accepted
end

lib.callback.register('qbx_vehicleshop:client:confirmFinance', function(financeData)
    local alert = lib.alertDialog({
        header = locale('general.financed_vehicle_header'),
        content = locale('general.financed_vehicle_warning', lib.math.groupdigits(financeData.balance), lib.math.groupdigits(financeData.paymentamount), financeData.timer),
        centered = true,
        cancel = true,
        labels = {
            cancel = 'No',
            confirm = 'Yes',
        }
    })
    return alert
end)

lib.callback.register('qbx_vehicleshop:client:confirmTrade', function(vehicle, sellAmount)
    local confirmationText = locale('general.transfervehicle_confirm', VEHICLES_HASH[vehicle].brand, VEHICLES_HASH[vehicle].name, lib.math.groupdigits(sellAmount) or 0)

    if GetResourceState('npwd') ~= 'started' then
        local input = lib.inputDialog(confirmationText, {
            {
                type = 'checkbox',
                label = 'Confirm'
            },
        })
        return input?[1]
    end

    return confirmTrade(confirmationText)
end)

--- Thread to create blips
CreateThread(function()
    if sharedConfig.finance.enable then
        if config.useTarget then
            exports.ox_target:addBoxZone({
                coords = sharedConfig.finance.zone,
                size = vec3(2, 2, 4),
                rotation = 0,
                debug = config.debugPoly,
                options = {
                    {
                        name = 'vehicleshop:showFinanceMenu',
                        icon = 'fas fa-money-check',
                        label = locale('menus.finance_menu'),
                        onSelect = function()
                            showFinancedVehiclesMenu()
                        end
                    }
                }
            })
        else
            lib.zones.box({
                coords = sharedConfig.finance.zone,
                size = vec3(2, 2, 4),
                rotation = 0,
                debug = config.debugPoly,
                onEnter = function()
                    lib.showTextUI(locale('menus.keypress_showFinanceMenu'))
                end,
                inside = function()
                    if IsControlJustPressed(0, 38) then
                        showFinancedVehiclesMenu()
                    end
                end,
                onExit = function()
                    lib.hideTextUI()
                end
            })
        end
    end

    for _, v in pairs(sharedConfig.shops) do
        local blip = v.blip
        if blip.show then
            local dealer = AddBlipForCoord(blip.coords.x, blip.coords.y, blip.coords.z)
            SetBlipSprite(dealer, blip.sprite)
            SetBlipDisplay(dealer, 4)
            SetBlipScale(dealer, 0.70)
            SetBlipAsShortRange(dealer, true)
            SetBlipColour(dealer, blip.color)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(blip.label)
            EndTextCommandSetBlipName(dealer)
        end
    end

    for shopName, shop in pairs(sharedConfig.shops) do
        createShop(shop.zone.shape, shopName)
        showroomPoints[shopName] = {}

        local showroomVehicles = sharedConfig.shops[shopName].showroomVehicles
        for i = 1, #showroomVehicles do
            local showroomVehicle = showroomVehicles[i]
            showroomPoints[shopName][i] = createShowroomVehiclePoint({
                coords = showroomVehicle.coords,
                shopName = shopName,
                vehiclePos = i,
                model = showroomVehicle.vehicle
            })
        end
    end
end)

----------------------------------------------------
---------APL NATION---------------------------------

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    else
        return value
    end
end

local function lerp(a, b, t) return a * (1 - t) + b * t end

-- Heading Using Lerp
local function setEntityHeadingSmoothly(entity, targetHeading, duration)
    local initialHeading = GetEntityHeading(entity)
    local elapsedTime = 0
    local interval = 0.01 -- Update every 0.01 seconds

    while elapsedTime < duration do
        local t = elapsedTime / duration
        local currentHeading = lerp(initialHeading, targetHeading, t)
        SetEntityHeading(entity, currentHeading)

        Wait(interval * 1000)
        elapsedTime = elapsedTime + interval
    end

    -- Ensure the entity's heading is set to the target heading
    SetEntityHeading(entity, targetHeading)
end

function PreviewManager()
    local self = {}
    
    self.vehicle = nil -- Vehicle Id
    --self.coords = vec3(567.5121, -408.0889, -70.0132) -- Vehicle Coords
    self.coords = vec3(-147.2409, -595.2252, 166.5759) -- Vehicle Coords
    self.heading = nil -- Vehicle Heading
    self.lastCoords = nil -- Store Coords Where Player was before entering preview

    self.cam = nil -- Vehicle Cam

    self.createCam = function()
        -- if not self.vehicle then 
        --     lib.print.error('No Vehicle Found')
        --     return 
        -- end

        if self.cam then 
            lib.print.error('Already Cam Available')
            return 
        end

        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

        self.cam = cam

        SetCamCoord(cam, -143.8477, -596.6397, 167.5)
        SetCamFov(cam, 90)
        SetCamRot(cam, 0.0, 0.0, 65.0, 0)
        RenderScriptCams(true, true, 250, true, true)
    end

    -- Not Sure if need to spawn it server side
    self.spawnCar = function(model)
        if self.vehicle and DoesEntityExist(self.vehicle) then
            DeleteEntity(self.vehicle)
        end

        lib.requestModel(model, 10000)
        local veh = CreateVehicle(model, self.coords.x, self.coords.y, self.coords.z, 161.3717, false, true)
        SetModelAsNoLongerNeeded(model)
        SetVehicleOnGroundProperly(veh)
        SetEntityInvincible(veh, true)
        SetVehicleDirtLevel(veh, 0.0)
        SetVehicleDoorsLocked(veh, 10)
        FreezeEntityPosition(veh, true)
        SetVehicleNumberPlateText(veh, 'BUY ME')
        SetVehicleColours(veh, 0, 0)

        self.vehicle = veh
    end

    -- Rotate Car using SetEntityHeading
    self.rotateCar = function(heading)
        if not self.vehicle and not DoesEntityExist(self.vehicle) then return end

        -- My Way
        -- local currentHeading = GetEntityHeading(self.vehicle)
        -- setEntityHeadingSmoothly(self.vehicle, clamp(currentHeading + heading, 0.0, 360.0), 0.2)

        -- Raid Way
        local Rot = GetEntityHeading(self.vehicle)+heading
        setEntityHeadingSmoothly(self.vehicle, Rot % 360)
    end

    self.changePrimaryColor = function(color)
        if not self.vehicle and not DoesEntityExist(self.vehicle) then return end

        SetVehicleCustomPrimaryColour(self.vehicle, color.r, color.g, color.b)
    end

    self.changeSecondaryColor = function(color)
        if not self.vehicle and not DoesEntityExist(self.vehicle) then return end

        SetVehicleCustomSecondaryColour(self.vehicle, color.r, color.g, color.b)
    end

    self.enterPreview = function()
        DoScreenFadeOut(1000)
        while not IsScreenFadedOut() do
            print('Waiting for Screen FadeOut')
            Wait(0) 
        end

        self.lastCoords = GetEntityCoords(cache.ped)

        local curTime = GetGameTimer()

        SetEntityCoords(cache.ped, -141.0687, -604.4445, 167.5951)

        while not HasCollisionLoadedAroundEntity(cache.ped) do
            RequestCollisionAtCoord(-141.0687, -604.4445, 167.5951)
            print('Waiting for collision to load Around Entity')
            if GetGameTimer() - curTime > 1000 then
                break
            end
            Wait(0)
        end

        SetEntityCoords(cache.ped, -141.0687, -604.4445, 167.5951)

        FreezeEntityPosition(cache.ped, true)

        Wait(1000)

        self.createCam()

        Wait(500)

        DoScreenFadeIn(1000)
    end

    self.leavePreview = function()
        DoScreenFadeOut(1000)
        while not IsScreenFadedOut() do Wait(0) end
        -- Destroy Cam
        RenderScriptCams(false, true, 250, true, false)
        if self.cam then 
            DestroyCam(self.cam, true) 
            self.cam = nil
        end

        -- Delete Vehicle 
        if self.vehicle and DoesEntityExist(self.vehicle) then
            DeleteEntity(self.vehicle)
        end

        -- Teleport Back to Last Coords
        if not self.coords then
            lib.print.error("Failed To Find Last Coords. Please Relog.")
        end

        local curTime = GetGameTimer()

        SetEntityCoords(cache.ped, self.lastCoords.x, self.lastCoords.y, self.lastCoords.z)

        while not HasCollisionLoadedAroundEntity(cache.ped) do
            RequestCollisionAtCoord(self.lastCoords.x, self.lastCoords.y, self.lastCoords.z)
            if GetGameTimer() - curTime > 1000 then
                break
            end
            Wait(0)
        end

        SetEntityCoords(cache.ped, self.lastCoords.x, self.lastCoords.y, self.lastCoords.z)

        FreezeEntityPosition(cache.ped, false)

        DoScreenFadeIn(1000)
    end

    return self
end

local Preview = PreviewManager()

-----------------------------------------------------------------------
------------CATALOGUE DATA---------------------------------------------
-----------------------------------------------------------------------
-- Returns Speed / Braking / Handling / Acceleration Data (keep a clamp of 0-100 on all data as few models have stats above 100 somehow)
-- Not sure how accurate these are...seems promising to me
local function GetPerformanceStats(vehicle)
    local data = {}
    data.speed = math.ceil((GetVehicleModelEstimatedMaxSpeed(vehicle)*4.605936)/520*100)
    data.brakes = math.ceil(GetVehicleModelMaxBraking(vehicle)/2*100)
    local handling1 = GetVehicleModelMaxBraking(vehicle)
    local handling2 = GetVehicleModelMaxBrakingMaxMods(vehicle)
    local handling3 = GetVehicleModelMaxTraction(vehicle)
    data.handling = math.ceil(((handling1+handling2) * handling3)/10*100)
    data.acceleration = math.ceil(GetVehicleModelAcceleration(vehicle) * 200)
    return data
end

-- Return Vehicles Data for that shop
--[[
Vehicles -
    Compacts
        Vehicle1
            name
            price
            stats
        Vehicle2
        vehicle3
    Super
        Vehicle1
        Vehicle2
        Vehicle3

]]

local function VehiclesData(insideShop)
    local sortedCategories = {}
    local categories = sharedConfig.shops[insideShop].categories


    for k, v in pairs(categories) do
        sortedCategories[#sortedCategories + 1] = {
            category = k,
            label = v
        }
    end

    table.sort(sortedCategories, function(a, b)
        return string.upper(a.label) < string.upper(b.label)
    end)

    local vehicles = {}

    for j = 1, #sortedCategories do
        vehicles[sortedCategories[j].category] = {}
        for i = 1, vehiclesMenu.count do
            local vehicle = vehiclesMenu.vehicles[i]
            if vehicle.category == sortedCategories[j].category and vehicle.shopType == insideShop then
                local data = {}
                -- Add Data Here if neede to be sent to UI
                data.category = vehicle.category
                data.name = vehicle.name
                data.manufacturer = vehicle.manufacturer
                data.price = vehicle.description -- is in string
                data.closestShop = insideShop
                data.controls = GetPerformanceStats(vehicle.args.toVehicle)
                data.model = vehicle.args.toVehicle
                data.inStock = true -- in future change by calculation from database
                vehicles[sortedCategories[j].category][#vehicles[sortedCategories[j].category] + 1] = data
            end
        end
    end

    return vehicles
end

--------------------------------------------------------------------------------

RegisterNUICallback("spawnPreviewVehicle", function(model)
    Preview.spawnCar(model)
end)

-- This delete cam, vehicle and teleport back ped to it's last coords (if player crash and take last location then he will be teleported to showcase place.)
RegisterNUICallback("exitPreview", function()
    -- Close UI here
    Preview.leavePreview()
end)

RegisterNUICallback("rotateCar", function(degree)
    Preview.rotateCar(degree)
end)

-- color should be of color.r, color.g color.b format
RegisterNUICallback("changePrimaryVehicleColor", function(color)
    Preview.changePrimaryColor(color)
end)

-- color should be of color.r, color.g color.b format
RegisterNUICallback("changeSecondaryVehicleColor", function(color)
    Preview.changeSecondaryColor(color)
end)
-------------------------------------------------------

RegisterCommand("vehicleCatalogue", function(_, args)
    -- if not insideShop then 
    --     lib.print.error('You are not insideShop zone.')
    --     return 
    -- end

    -- --PreviewHandler()
    -- -- Function To Enter Preview (Add Your UI launch in this function of class of after this function)
    
    -- openVehicleCategoryMenuAPL(insideShop)

    -- Preview.enterPreview()
    local stats = GetPerformanceStats(args[1])
    print(json.encode(stats))

    --print(json.encode(VehiclesData('pdm'), {indent = true}))
end, false)

