#requires -Version 7.0
param([ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Name='host')
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$instance=Join-Path $project ('game-instances\'+$Name)
if(Get-Process -Name PBZ -ErrorAction SilentlyContinue){throw 'Close game before changing an isolated script.'}
if(!(Test-Path -LiteralPath (Join-Path $instance 'pb0-test-profile.json'))){throw 'Not an isolated test copy'}
$file=Join-Path $instance 'platform\steam\ue4ss\Mods\PBZCoop\Scripts\coop.lua'
$base=[IO.File]::ReadAllText((Join-Path $project 'tools\phantom-pact-release\platform\steam\ue4ss\Mods\PBZCoop\Scripts\coop.lua'))
$base=$base.Replace("`r`n","`n")
$patched=$base.Replace('local NET_SEND_MS = 50','local NET_SEND_MS = 33').Replace('local TICK_MS = 16','local TICK_MS = 8').Replace('local GHOST_STOP_CM = 60','local GHOST_STOP_CM = 12').Replace('local GHOST_MIN_SPEED = 100','local GHOST_MIN_SPEED = 60')
# Time-based dispatch avoids multiplying a frame-quantized timer by NET_EVERY.
$patched=$patched.Replace('    local function tick()','    local lastNetUpdate = -1e9'+[char]10+'    local function tick()')
$patched=$patched.Replace('        if ticks % NET_EVERY == 0 then','        local now = os.clock()'+[char]10+'        if now - lastNetUpdate >= NET_SEND_MS / 1000 then'+[char]10+'            lastNetUpdate = now')
$previousPatch=$patched
$patched=$patched.Replace('        local cur = net.ghost:K2_GetActorLocation()' + [char]10 + '        local t = net.target',
    '        if game.steerRemote and game.steerRemote(net) then return end' + [char]10 + '        local cur = net.ghost:K2_GetActorLocation()' + [char]10 + '        local t = net.target')
if(!$patched.Contains('if game.steerRemote and game.steerRemote(net)')){throw 'Remote walking hook anchor not found'}
$walkingHookPatch=$patched
$writeAnchor='        if isHost() then'+[char]10+'            for _, l in ipairs(enemySnapshotLines(loc)) do'
$gaitWrite='        pcall(function() lines[1] = lines[1] .. " " .. tostring(pawn.Mesh:GetAnimInstance().Gait) end)'+[char]10
$patched=$patched.Replace($writeAnchor,$gaitWrite+$writeAnchor)
$readAnchor="                    -- A position that doesn't parse (or is NaN) is dropped, not applied."
$gaitRead='                    local motionFields = {} for word in line:gmatch("%S+") do motionFields[#motionFields+1]=word end'+[char]10+'                    t.Gait = tonumber(motionFields[14])'+[char]10
$patched=$patched.Replace($readAnchor,$gaitRead+$readAnchor)
if(!$patched.Contains('t.Gait = tonumber(motionFields[14])') -or !$patched.Contains('lines[1] = lines[1]')){throw 'Gait metadata anchors missing'}

$gaitOnlyPatch=$patched
$patched=$patched.Replace('    local SNAPSHOT_S = math.max(1, math.floor(NET_SEND_MS / TICK_MS + 0.5)) * TICK_MS / 1000','    local SNAPSHOT_S = NET_SEND_MS / 1000 -- fallback for legacy peers without real source timestamps')
$patched=$patched.Replace($gaitWrite,'        pcall(function() local v=pawn:GetVelocity() lines[1] = lines[1] .. string.format(" %d %.6f %.3f %.3f", pawn.Mesh:GetAnimInstance().Gait, os.clock(), v.X, v.Y) end)'+[char]10)
$patched=$patched.Replace('                    t.Gait = tonumber(motionFields[14])','                    t.Gait = tonumber(motionFields[14])'+[char]10+'                    t.SourceTime, t.VelX, t.VelY = tonumber(motionFields[15]), tonumber(motionFields[16]), tonumber(motionFields[17])')
$patched=$patched.Replace('                    if t.X and t.Y and t.Z and t.Yaw then','                    if t.X and t.Y and t.Z and t.Yaw and (not game.acceptRemoteMotion or game.acceptRemoteMotion(t, seq)) then')
$patched=$patched.Replace('                            local dt = steps * SNAPSHOT_S','                            local dt = (t.SourceTime and prev.SourceTime and t.SourceTime > prev.SourceTime) and (t.SourceTime - prev.SourceTime) or steps * SNAPSHOT_S')
$patched=$patched.Replace('    local lastNetUpdate = -1e9','    local lastNetUpdate = -1e9')
$patched=$patched.Replace('        if now - lastNetUpdate >= NET_SEND_MS / 1000 then'+[char]10+'            lastNetUpdate = now','        if now >= lastNetUpdate then'+[char]10+'            lastNetUpdate = math.max(lastNetUpdate + NET_SEND_MS / 1000, now - NET_SEND_MS / 1000)')
if(!$patched.Contains('game.acceptRemoteMotion(t, seq)') -or !$patched.Contains('tonumber(motionFields[17])')){throw 'Timestamp motion patch anchors missing'}


$timestampPatch=$patched
$patched=$patched.Replace('local v=pawn:GetVelocity() lines[1] = lines[1] .. string.format(" %d %.6f %.3f %.3f", pawn.Mesh:GetAnimInstance().Gait, os.clock(), v.X, v.Y)',
 'local v=pawn:GetVelocity() local cm=pawn.CharacterMovement local i=pawn:GetLastMovementInputVector() lines[1] = lines[1] .. string.format(" %d %.6f %.3f %.3f %.3f %.3f %.5f %.5f %.0f", pawn.Mesh:GetAnimInstance().Gait, os.clock(), v.X, v.Y, cm.MaxWalkSpeed, cm.MaxAcceleration, i.X, i.Y, (game.motionUtcMs and game.motionUtcMs()) or 0)')
$patched=$patched.Replace('                    t.SourceTime, t.VelX, t.VelY = tonumber(motionFields[15]), tonumber(motionFields[16]), tonumber(motionFields[17])',
 '                    t.SourceTime, t.VelX, t.VelY = tonumber(motionFields[15]), tonumber(motionFields[16]), tonumber(motionFields[17])'+[char]10+'                    t.WalkMax,t.AccelMax,t.InputX,t.InputY,t.SourceUtcMs=tonumber(motionFields[18]),tonumber(motionFields[19]),tonumber(motionFields[20]),tonumber(motionFields[21]),tonumber(motionFields[22])')
if(!$patched.Contains('tonumber(motionFields[22])')){throw 'Native input metadata anchors missing'}


$inputScalePatch=$patched
$oldMotion='local v=pawn:GetVelocity() local cm=pawn.CharacterMovement local i=pawn:GetLastMovementInputVector() lines[1] = lines[1] .. string.format(" %d %.6f %.3f %.3f %.3f %.3f %.5f %.5f %.0f", pawn.Mesh:GetAnimInstance().Gait, os.clock(), v.X, v.Y, cm.MaxWalkSpeed, cm.MaxAcceleration, i.X, i.Y, (game.motionUtcMs and game.motionUtcMs()) or 0)'
$newMotion='local v=pawn:GetVelocity() local cm=pawn.CharacterMovement local m=game.motionInputState and game.motionInputState(pawn) local i=m and {X=m.ix,Y=m.iy} or pawn:GetLastMovementInputVector() lines[1] = lines[1] .. string.format(" %d %.6f %.3f %.3f %.3f %.3f %.5f %.5f %.3f %.3f %d %.3f", pawn.Mesh:GetAnimInstance().Gait, os.clock(), v.X, v.Y, m and m.max or cm.MaxWalkSpeed, m and m.accel or cm.MaxAcceleration, i.X, i.Y, (game.motionUtcMs and game.motionUtcMs()) or 0, v.Z, cm.MovementMode, (game.motionInputChangedMs and game.motionInputChangedMs()) or 0)'
$patched=$patched.Replace($oldMotion,$newMotion)
$patched=$patched.Replace('tonumber(motionFields[22])','tonumber(motionFields[22])'+[char]10+'                    t.VelZ,t.MoveMode,t.InputChangedMs=tonumber(motionFields[23]),tonumber(motionFields[24]),tonumber(motionFields[25])')
$patched=$patched.Replace('    local lastNetUpdate = -1e9','    local lastNetUpdate = -1e9'+[char]10+'    local lastInboxFrame = -1')
$patched=$patched.Replace('        ticks = ticks + 1','        ticks = ticks + 1'+[char]10+'        if game.publishMotionInput then runStage("publishMotionInput", game.publishMotionInput) end')
$patched=$patched.Replace('            runStage("readSnapshot", readSnapshot)'+[char]10,'').Replace('            runStage("processEvents", processEvents)'+[char]10,'')
$poll='        local inboxFrame = game.motionFrame and game.motionFrame() or ticks'+[char]10+'        if inboxFrame ~= lastInboxFrame then'+[char]10+'            lastInboxFrame = inboxFrame'+[char]10+'            runStage("readSnapshot", readSnapshot)'+[char]10+'            runStage("processEvents", processEvents)'+[char]10+'        end'+[char]10
$patched=$patched.Replace('        runStage("steerGhost", steerGhost)',$poll+'        runStage("steerGhost", steerGhost)')
if(!$patched.Contains('tonumber(motionFields[25])') -or !$patched.Contains('lastInboxFrame = inboxFrame')){throw 'Input simulation patch anchors missing'}


$inputIntentPatch=$patched
$patched=$patched.Replace('local v=pawn:GetVelocity() local cm=pawn.CharacterMovement local m=game.motionInputState','local v=pawn:GetVelocity() local cm=pawn.CharacterMovement local acceleration=cm:GetCurrentAcceleration() local m=game.motionInputState')
$patched=$patched.Replace('%.3f %.3f %d %.3f", pawn.Mesh','%.3f %.3f %d %.3f %.3f %.3f", pawn.Mesh')
$patched=$patched.Replace('(game.motionInputChangedMs and game.motionInputChangedMs()) or 0)','(game.motionInputChangedMs and game.motionInputChangedMs()) or 0, acceleration.X, acceleration.Y)')
$patched=$patched.Replace('tonumber(motionFields[25])','tonumber(motionFields[25])'+[char]10+'                    t.AccelX,t.AccelY=tonumber(motionFields[26]),tonumber(motionFields[27])')


$appliedAccelerationPatch=$patched
$patched=$patched.Replace('%d %.3f %.3f %.3f", pawn.Mesh','%d %.3f %.3f %.3f %.3f %.3f %d", pawn.Mesh')
$patched=$patched.Replace('acceleration.X, acceleration.Y)','acceleration.X, acceleration.Y, m and m.bx or 0, m and m.by or 0, m and m.root and 1 or 0)')
$patched=$patched.Replace('tonumber(motionFields[27])','tonumber(motionFields[27])'+[char]10+'                    t.PhysAccelX,t.PhysAccelY,t.SourceRootMotion=tonumber(motionFields[28]),tonumber(motionFields[29]),tonumber(motionFields[30])')

$old=[IO.File]::ReadAllText($file).Replace("`r`n","`n")
if($old -ne $base -and $old -ne $previousPatch -and $old -ne $walkingHookPatch -and $old -ne $gaitOnlyPatch -and $old -ne $timestampPatch -and $old -ne $inputScalePatch -and $old -ne $inputIntentPatch -and $old -ne $appliedAccelerationPatch -and $old -ne $patched){throw 'Unexpected changes in isolated coop.lua; refusing overwrite'}
$backup=Join-Path $project ('backups\presentation-sync-'+$Name+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $file -Destination (Join-Path $backup 'coop.lua')
[IO.File]::WriteAllText($file,$patched)
@{RequestedStateHz=30;GameLoopMs=8;TimeBasedDispatch=$true;SourceTimestampAndVelocity=$true;InterpolationDelayMs=0;InputEvents=$true;ReceiveEveryEngineFrame=$true;WalkingStopRadiusCm=12;Backup=$backup} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $instance 'pb0-presentation-sync.json')
Write-Output "PRESENTATION_SYNC_INSTALLED $Name (EasyTier unchanged)"