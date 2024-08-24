--- This is the interface provided to Courseplay
-- Wraps the CourseGenerator which does not depend on the CP or Giants code.
-- all course generator related code dependent on CP/Giants functions go here
CourseGeneratorInterface = {}
CourseGeneratorInterface.logger = Logger('CourseGeneratorInterface')

-- Generate into this global variable to be able to access the generated course for debug purposes
CourseGeneratorInterface.generatedCourse = nil

---@param fieldPolygon table [{x, z}]
---@param startPosition table {x, z}
---@param vehicle table
---@param settings CpCourseGeneratorSettings
function CourseGeneratorInterface.generate(fieldPolygon,
                                           startPosition,
                                           vehicle,
                                           settings
)
    CourseGenerator.clearDebugObjects()
    local field = CourseGenerator.Field('', 0, CpMathUtil.pointsFromGame(fieldPolygon))

    local context = CourseGenerator.FieldworkContext(field, settings.workWidth:getValue() * settings.multiTools:getValue(),
            settings.turningRadius:getValue(), settings.numberOfHeadlands:getValue())
    local rowPatternNumber = settings.centerMode:getValue()
    if rowPatternNumber == CourseGenerator.RowPattern.ALTERNATING and settings.rowsToSkip:getValue() == 0 then
        context:setRowPattern(CourseGenerator.RowPatternAlternating())
    elseif rowPatternNumber == CourseGenerator.RowPattern.ALTERNATING and settings.rowsToSkip:getValue() > 0 then
        context:setRowPattern(CourseGenerator.RowPatternSkip(settings.rowsToSkip:getValue(), false))
    elseif rowPatternNumber == CourseGenerator.RowPattern.SPIRAL then
        context:setRowPattern(CourseGenerator.RowPatternSpiral(settings.centerClockwise:getValue(), settings.spiralFromInside:getValue()))
    elseif rowPatternNumber == CourseGenerator.RowPattern.LANDS then
        -- TODO: auto fill clockwise from self:isPipeOnLeftSide(vehicle)?
        context:setRowPattern(CourseGenerator.RowPatternLands(settings.centerClockwise:getValue(), settings.rowsPerLand:getValue()))
    elseif rowPatternNumber == CourseGenerator.RowPattern.RACETRACK then
        context:setRowPattern(CourseGenerator.RowPatternRacetrack(settings.numberOfCircles:getValue()))
    end

    context:setStartLocation(startPosition.x, -startPosition.z)
    context:setBaselineEdge(startPosition.x, -startPosition.z)
    context:setUseBaselineEdge(settings.useBaseLineEdge:getValue())
    context:setFieldCornerRadius(settings.turningRadius:getValue())
    context:setHeadlandFirst(settings.startOnHeadland:getValue())
    context:setHeadlandClockwise(settings.headlandClockwise:getValue())
    context:setHeadlandOverlap(settings.headlandOverlapPercent:getValue())
    context:setSharpenCorners(settings.sharpenCorners:getValue())
    context:setHeadlandsWithRoundCorners(settings.headlandsWithRoundCorners:getValue())
    context:setAutoRowAngle(settings.autoRowAngle:getValue())
    -- the Course Generator UI uses the geographical direction angles (0 - North, 90 - East, etc), convert it to
    -- the mathematical angle (0 - x+, 90 - y+, etc)
    context:setRowAngle(math.rad(-(settings.manualRowAngleDeg:getValue() - 90)))
    context:setBypassIslands(settings.bypassIslands:getValue())
    context:setIslandHeadlands(settings.nIslandHeadlands:getValue())
    if settings.bypassIslands:getValue() then
        context.field:findIslands()
        context.field:setupIslands()
    end

    local status, numberOfHeadlands
    if settings.narrowField:getValue() then
        -- two sided must start on headland
        context:setHeadlandFirst(true)
        status, CourseGeneratorInterface.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourseTwoSided(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
        -- two sided always has the requested headlands
        numberOfHeadlands = settings.numberOfHeadlands:getValue()
    else
        status, CourseGeneratorInterface.generatedCourse = xpcall(
                function()
                    return CourseGenerator.FieldworkCourse(context)
                end,
                function(err)
                    printCallstack();
                    return err
                end
        )
        -- the actual number of headlands generated may be less than the requested
        numberOfHeadlands = #CourseGeneratorInterface.generatedCourse:getHeadlands()
    end

    -- return on exception or if the result is not usable
    if not status or CourseGeneratorInterface.generatedCourse == nil then
        return false
    end

    CourseGeneratorInterface.logger:debug('Generated course: %d/%d headland/center waypoints',
            #CourseGeneratorInterface.generatedCourse:getHeadlandPath(), #CourseGeneratorInterface.generatedCourse:getCenterPath())

    local course = Course.createFromGeneratedCourse(nil, CourseGeneratorInterface.generatedCourse,
            settings.workWidth:getValue(), numberOfHeadlands, settings.multiTools:getValue())
    course:setFieldPolygon(fieldPolygon)
    return true, course
end

--- Generates a vine course, where the fieldPolygon are the start/end of the vine node.
---@param fieldPolygon table
---@param workWidth number
---@param turningRadius number
---@param manualRowAngleDeg number
---@param rowsToSkip number
---@param multiTools number
function CourseGeneratorInterface.generateVineCourse(
        fieldPolygon,
        startPosition,
        workWidth,
        turningRadius,
        manualRowAngleDeg,
        rowsToSkip,
        multiTools
)
    CourseGenerator.clearDebugObjects()
    local field = CourseGenerator.Field('', 0, CpMathUtil.pointsFromGame(fieldPolygon))

    local context = CourseGenerator.FieldworkContext(field, workWidth * multiTools, turningRadius, 0)
    context:setRowPattern(CourseGenerator.RowPatternAlternating(rowsToSkip, true))
    context:setStartLocation(startPosition.x, -startPosition.z)
    context:setAutoRowAngle(false)
    -- the Course Generator UI uses the geographical direction angles (0 - North, 90 - East, etc), convert it to
    -- the mathematical angle (0 - x+, 90 - y+, etc)
    context:setRowAngle(CpMathUtil.angleFromGame(manualRowAngleDeg))
    context:setBypassIslands(false)
    local status
    status, CourseGeneratorInterface.generatedCourse = xpcall(
            function()
                return CourseGenerator.FieldworkCourse(context)
            end,
            function(err)
                printCallstack();
                return err
            end
    )
    -- return on exception or if the result is not usable
    if not status or CourseGeneratorInterface.generatedCourse == nil then
        return false
    end

    CourseGeneratorInterface.logger:debug('Generated vine course: %d center waypoints',
            #CourseGeneratorInterface.generatedCourse:getCenterPath())

    local course = Course.createFromGeneratedCourse(nil, CourseGeneratorInterface.generatedCourse,
            workWidth, 0, multiTools)
    course:setFieldPolygon(fieldPolygon)
    return true, course
end
