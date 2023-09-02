--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2021 Peter Vaiko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Drive strategy for driving a field work course

]]--


--[[
 
 AI Drive Strategy for plows

]]

---@class AIDriveStrategyPlowCourse : AIDriveStrategyFieldWorkCourse
AIDriveStrategyPlowCourse = {}
local AIDriveStrategyPlowCourse_mt = Class(AIDriveStrategyPlowCourse, AIDriveStrategyFieldWorkCourse)

AIDriveStrategyPlowCourse.myStates = {
    ROTATING_PLOW = {},
    UNFOLDING_PLOW = {},
}

function AIDriveStrategyPlowCourse.new(customMt)
    if customMt == nil then
        customMt = AIDriveStrategyPlowCourse_mt
    end
    local self = AIDriveStrategyFieldWorkCourse.new(customMt)
    AIDriveStrategyFieldWorkCourse.initStates(self, AIDriveStrategyPlowCourse.myStates)
    self.debugChannel = CpDebug.DBG_FIELDWORK
    return self
end

function AIDriveStrategyPlowCourse:getDriveData(dt, vX, vY, vZ)
    if self.state == self.states.INITIAL then
        -- When starting work with a plow it first may need to be unfolded and then turned so it is facing to
        -- the unworked side, and then can we start working
        self:setMaxSpeed(0)
        self:updatePlowOffset()
        if self:isPlowTurning() then
            self:rotatePlows()
			self:debug("Needs to wait until the plow has finished rotating.")
			self.state = self.states.ROTATING_PLOW
		else 
            self:debug("Plows have to be unfolded first!")
			self.state = self.states.UNFOLDING_PLOW
		end
    elseif self.state == self.states.ROTATING_PLOW then
        self:setMaxSpeed(0)
        if not self:isPlowTurning() then
            self:updatePlowOffset()
            self:startWaitingForLower()
            self:lowerImplements()
            self:debug('Plow initial rotation finished')
        end
    elseif self.state == self.states.UNFOLDING_PLOW then
        self:setMaxSpeed(0)
        if self:isPlowRotationAllowed() then 
            self:rotatePlows()
            self:debug("Plow was unfolded and rotation can begin")
			self.state = self.states.ROTATING_PLOW
        end
    end
    return AIDriveStrategyFieldWorkCourse.getDriveData(self, dt, vX, vY, vZ)
end

function AIDriveStrategyPlowCourse:onWaypointPassed(ix, course)
    -- readjust the tool offset every now and then. This is necessary as the offset is calculated from the
    -- tractor's direction node which may need to result in incorrect values if the plow is not straight behind
    -- the tractor (which may be the case when starting). When passing waypoints we'll most likely be driving
    -- straight and thus calculating a proper tool offset
    if self.state == self.states.WORKING then
        self:updatePlowOffset()
    end
    AIDriveStrategyFieldWorkCourse.onWaypointPassed(self, ix, course)
end

--- Updates the X Offset based on the plows attached.
function AIDriveStrategyPlowCourse:updatePlowOffset()
    local xOffset = 0
    for _, controller in pairs(self.controllers) do 
        if controller.getAutomaticXOffset then 
            xOffset = xOffset + controller:getAutomaticXOffset()
        end
    end
    local oldOffset = self.aiOffsetX
    -- set to the average of old and new to smooth a little bit to avoid oscillations
    self.aiOffsetX = (0.5 * self.aiOffsetX + 1.5 * xOffset) / 2
    self:debug("Plow offset calculated was %.2f and it changed from %.2f to %.2f",
        xOffset, oldOffset, self.aiOffsetX)
end

--- Is a plow currently rotating?
---@return boolean
function AIDriveStrategyPlowCourse:isPlowTurning()
    for _, controller in pairs(self.controllers) do 
        if controller.isRotationActive and controller:isRotationActive() then 
            return true
        end
    end
    return false
end

function AIDriveStrategyPlowCourse:isPlowRotationAllowed()
    local allowed = true
    for _, controller in pairs(self.controllers) do 
        if controller.getIsPlowRotationAllowed and not controller:getIsPlowRotationAllowed() then 
            allowed = false
        end
    end
    return allowed
end

function AIDriveStrategyPlowCourse:rotatePlows()
    self:debug('Starting work: check if plow needs to be turned.')
    local ridgeMarker = self.course:getRidgeMarkerState(self.ppc:getCurrentWaypointIx())
    local plowShouldBeOnTheLeft = ridgeMarker == CourseGenerator.RIDGEMARKER_RIGHT
    self:debug('Ridge marker %d, plow should be on the left %s', ridgeMarker, tostring(plowShouldBeOnTheLeft))
    for _, controller in pairs(self.controllers) do 
        if controller.rotate then 
            controller:rotate(plowShouldBeOnTheLeft)
        end
    end
end

-----------------------------------------------------------------------------------------------------------------------
--- Dynamic parameters (may change while driving)
-----------------------------------------------------------------------------------------------------------------------
function AIDriveStrategyPlowCourse:getTurnEndSideOffset()
    if self:isWorking() then
        self:updatePlowOffset()
        -- need the double tool offset as the turn end still has the current offset, after the rotation it'll be
        -- on the other side, (one toolOffsetX would put it to 0 only)
        return 2 * self.aiOffsetX
    else
        return 0
    end
end

function AIDriveStrategyPlowCourse:updateFieldworkOffset(course)
	--- Ignore the tool offset setting.
	course:setOffset((self.aiOffsetX or 0), (self.aiOffsetZ or 0))
end