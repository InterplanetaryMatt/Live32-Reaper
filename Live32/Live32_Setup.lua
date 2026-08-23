-- Live32 v1.2.0 setup engine
-- Can build a clean console or attach selected existing tracks as Live32 inputs.
-- Normally launched from Live32_Launcher.lua.

local VERSION="1.2.0"
local SETUP_MODE=_G.LIVE32_SETUP_MODE or "new" -- new | attach | repair
local ATTACH_TRACKS=_G.LIVE32_ATTACH_TRACKS or {}
local ATTACH_KEEP_FX=(_G.LIVE32_ATTACH_KEEP_FX ~= false)
local REPAIR=(SETUP_MODE=="repair")
local function msg(s) reaper.ShowMessageBox(s,"Live32 v"..VERSION,0) end
local function dirname(path) return path:match("^(.*)[/\\]") or "." end
local function copy_file(src,dst)
  local f=io.open(src,"rb"); if not f then return false,"Could not open "..src end
  local data=f:read("*all"); f:close()
  local o=io.open(dst,"wb"); if not o then return false,"Could not write "..dst end
  o:write(data); o:close(); return true
end

-- Never build a second Live32 infrastructure into the same project unless the
-- Launcher explicitly asked us to REPAIR an older/incomplete Live32 project.
if not REPAIR then
  for i=0,reaper.CountTracks(0)-1 do
    local tr=reaper.GetTrack(0,i)
    local _,role=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE","",false)
    if role~="" then
      msg("This project already contains Live32 tracks.\n\nOpen the console, or use the Launcher REPAIR option if it reports an incomplete project.")
      return
    end
  end
end

if SETUP_MODE=="new" and reaper.CountTracks(0)>0 then
  msg("NEW CONSOLE is intended for an empty project.\n\nFor an existing multitrack use Live32 Launcher → ATTACH or IMPORT.")
  return
end

local _,script_file=reaper.get_action_context()
local source_dir=dirname(script_file)
local sep=package.config:sub(1,1)
local fx_dir=reaper.GetResourcePath()..sep.."Effects"..sep.."Live32"
reaper.RecursiveCreateDirectory(fx_dir,0)
for _,f in ipairs({"Live32_Channel.jsfx","Live32_MeterTap.jsfx","Live32_PingPongDelay.jsfx","Live32_RTA.jsfx","Live32_PrecisionLimiter.jsfx","Live32_GEQ31.jsfx","Live32_FET76.jsfx","Live32_Opto2A.jsfx"}) do
  local ok,err=copy_file(source_dir..sep..f,fx_dir..sep..f)
  if not ok then msg("Could not install "..f..":\n"..err); return end
end
if reaper.APIExists and reaper.APIExists("EnumInstalledFX") then reaper.EnumInstalledFX(-1) end

local function set_role(tr,role,name)
  reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE",role,true)
  reaper.GetSetMediaTrackInfo_String(tr,"P_NAME",name,true)
end
local function insert_track(index,role,name)
  reaper.InsertTrackInProject(0,index,0)
  local tr=reaper.GetTrack(0,index)
  set_role(tr,role,name)
  reaper.SetMediaTrackInfo_Value(tr,"D_VOL",1.0)
  return tr
end
local function existing_role(role_name)
  for i=0,reaper.CountTracks(0)-1 do
    local tr=reaper.GetTrack(0,i)
    local _,r=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE","",false)
    if r==role_name then return tr end
  end
  return nil
end
local function find_fx(tr,needle)
  needle=needle:lower()
  for i=0,reaper.TrackFX_GetCount(tr)-1 do
    local _,name=reaper.TrackFX_GetFXName(tr,i,"")
    if name and name:lower():find(needle,1,true) then return i end
  end
  return -1
end
local function add_channel_fx(tr,neutral,output6,insert_first)
  local existing_count=reaper.TrackFX_GetCount(tr)
  local fx=find_fx(tr,"live32 channel strip")
  if fx<0 then fx=find_fx(tr,"live32_channel") end
  local existed=(fx>=0)
  if fx<0 then fx=reaper.TrackFX_AddByName(tr,"JS: Live32/Live32_Channel",false,1) end
  if fx<0 then fx=reaper.TrackFX_AddByName(tr,"Live32_Channel",false,1) end
  if fx>=0 and insert_first and fx>0 and reaper.TrackFX_CopyToTrack and not existed then
    reaper.TrackFX_CopyToTrack(tr,fx,tr,0,true)
    fx=0
  end
  if fx>=0 then
    -- Param 45 selects DSP topology: inputs/FX/matrices use four-band EQ;
    -- buses and MAIN LR use the six-band output EQ.
    reaper.TrackFX_SetParam(tr,fx,45,output6 and 1 or 0)
    if neutral and not existed then
      reaper.TrackFX_SetParam(tr,fx,0,0)
      reaper.TrackFX_SetParam(tr,fx,2,0)
      reaper.TrackFX_SetParam(tr,fx,4,0)
      reaper.TrackFX_SetParam(tr,fx,10,0)
      reaper.TrackFX_SetParam(tr,fx,23,0)
    end
    if insert_first and not ATTACH_KEEP_FX then
      for i=1,reaper.TrackFX_GetCount(tr)-1 do reaper.TrackFX_SetEnabled(tr,i,false) end
    end
  end
  return fx
end
local function add_meter_tap(tr)
  local fx=find_fx(tr,"live32 meter tap")
  if fx<0 then fx=find_fx(tr,"live32_metertap") end
  if fx>=0 then return fx end
  fx=reaper.TrackFX_AddByName(tr,"JS: Live32/Live32_MeterTap",false,1)
  if fx<0 then fx=reaper.TrackFX_AddByName(tr,"Live32 Meter Tap",false,1) end
  return fx
end
local function add_rta(tr)
  local fx=find_fx(tr,"live32 rta tap")
  if fx<0 then fx=find_fx(tr,"live32_rta") end
  if fx>=0 then return fx end
  fx=reaper.TrackFX_AddByName(tr,"JS: Live32/Live32_RTA",false,1)
  if fx<0 then fx=reaper.TrackFX_AddByName(tr,"Live32 RTA Tap",false,1) end
  if fx>=0 then reaper.TrackFX_SetParam(tr,fx,0,0) end
  return fx
end
local function has_send_to(src,dest)
  for s=0,reaper.GetTrackNumSends(src,0)-1 do
    if reaper.GetTrackSendInfo_Value(src,0,s,"P_DESTTRACK")==dest then return s end
  end
  return -1
end
local function ensure_send(src,dest,vol,mode,srcchan)
  local s=has_send_to(src,dest)
  local existed=(s>=0)
  if s<0 then s=reaper.CreateTrackSend(src,dest) end
  if s>=0 and (not REPAIR or not existed) then
    reaper.SetTrackSendInfo_Value(src,0,s,"D_VOL",vol or 0.0)
    reaper.SetTrackSendInfo_Value(src,0,s,"D_PAN",0.0)
    reaper.SetTrackSendInfo_Value(src,0,s,"I_SENDMODE",mode or 0)
    reaper.SetTrackSendInfo_Value(src,0,s,"I_SRCCHAN",srcchan or 0)
    reaper.SetTrackSendInfo_Value(src,0,s,"I_MIDIFLAGS",31)
  end
  return s
end
local function param_name(tr,fx,p)
  local ok,name=reaper.TrackFX_GetParamName(tr,fx,p)
  return ok and (name or ""):lower() or ""
end
local function set_param_match(tr,fx,patterns,value,exclude)
  exclude=exclude or {}
  if fx<0 then return false end
  for p=0,reaper.TrackFX_GetNumParams(tr,fx)-1 do
    local n=param_name(tr,fx,p)
    local bad=false
    for _,e in ipairs(exclude) do if n:find(e,1,true) then bad=true break end end
    if not bad then
      for _,pat in ipairs(patterns) do
        if n:find(pat,1,true) then reaper.TrackFX_SetParamNormalized(tr,fx,p,value); return true end
      end
    end
  end
  return false
end
local function add_fx_candidates(tr,candidates,needle)
  local existing=find_fx(tr,needle); if existing>=0 then return existing end
  for _,name in ipairs(candidates) do
    local fx=reaper.TrackFX_AddByName(tr,name,false,1)
    if fx>=0 then return fx end
  end
  return -1
end
local function find_stock_chorus_name()
  if reaper.APIExists and reaper.APIExists("EnumInstalledFX") then
    reaper.EnumInstalledFX(-1)
    for i=0,10000 do
      local ok,name,ident=reaper.EnumInstalledFX(i); if not ok then break end
      local both=((name or "").." "..(ident or "")):lower()
      if both:find("chorus",1,true) and both:find("js:",1,true) then return (ident and ident~="") and ident or name end
    end
  end
  return nil
end
local function configure_reverb(tr,fx,kind)
  set_param_match(tr,fx,{"dry"},0.0); set_param_match(tr,fx,{"wet"},1.0)
  if kind=="plate" then
    set_param_match(tr,fx,{"room"},0.34); set_param_match(tr,fx,{"damp"},0.38)
    set_param_match(tr,fx,{"width"},0.92); set_param_match(tr,fx,{"initial","pre-delay","predelay"},0.05)
  else
    set_param_match(tr,fx,{"room"},0.82); set_param_match(tr,fx,{"damp"},0.56)
    set_param_match(tr,fx,{"width"},1.0); set_param_match(tr,fx,{"initial","pre-delay","predelay"},0.12)
  end
end
local function configure_chorus(tr,fx)
  set_param_match(tr,fx,{"dry"},0.0); set_param_match(tr,fx,{"wet","mix"},1.0)
  set_param_match(tr,fx,{"depth"},0.42); set_param_match(tr,fx,{"rate","speed"},0.28)
end

-- Grouping helpers. FX stereo pairs use 25-28, Mute Groups 49-54, DCA 57-64.
local function group_bit(groupnum)
  local offset=math.floor((groupnum-1)/32)*32
  local bit=1 << ((groupnum-1)%32)
  return offset,bit
end
local function set_group_ex(tr,name,groupnum,on)
  local offset,bit=group_bit(groupnum)
  reaper.GetSetTrackGroupMembershipEx(tr,name,offset,bit,on and bit or 0)
end
local function configure_fx_pair_group(a,b,pair)
  local groupnum=24+pair
  for _,g in ipairs({"VOLUME_LEAD","VOLUME_FOLLOW","MUTE_LEAD","MUTE_FOLLOW","SOLO_LEAD","SOLO_FOLLOW"}) do
    local bit=2^(groupnum-1)
    reaper.GetSetTrackGroupMembership(a,g,bit,bit)
    reaper.GetSetTrackGroupMembership(b,g,bit,bit)
  end
end

local channels,fxreturns,buses,matrices,dcas,mutegroups={}, {}, {}, {}, {}, {}
local main,monitor
local warnings={}
local idx=reaper.CountTracks(0)

reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)

for i=1,32 do
  local tr=REPAIR and existing_role("CH"..i) or ATTACH_TRACKS[i]
  if tr then
    local _,oldname=reaper.GetTrackName(tr,"")
    oldname=(oldname and oldname~="") and oldname or string.format("INPUT %02d",i)
    -- Preserve existing Live32 scribble labels during repair; ATTACH inherits the REAPER name.
    reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE","CH"..i,true)
    local _,existing_label=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_LABEL","",false)
    if not REPAIR or existing_label=="" then reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_LABEL",oldname,true) end
    reaper.SetMediaTrackInfo_Value(tr,"I_NCHAN",8)
    add_channel_fx(tr,false,false,true)
  else
    tr=insert_track(idx,"CH"..i,string.format("Live32 CH %02d",i)); idx=idx+1
    reaper.SetMediaTrackInfo_Value(tr,"I_NCHAN",8); add_channel_fx(tr,false,false)
  end
  channels[i]=tr
end
for i=1,8 do
  local tr=REPAIR and existing_role("FXRTN"..i) or nil
  if not tr then tr=insert_track(idx,"FXRTN"..i,string.format("Live32 FX RTN %02d",i)); idx=idx+1 end
  fxreturns[i]=tr; reaper.SetMediaTrackInfo_Value(tr,"I_NCHAN",8); add_channel_fx(tr,false,false)
  reaper.SetMediaTrackInfo_Value(tr,"D_PAN",i%2==1 and -1.0 or 1.0)
end
for i=1,16 do
  local tr=REPAIR and existing_role("BUS"..i) or nil
  if not tr then tr=insert_track(idx,"BUS"..i,string.format("Live32 BUS %02d",i)); idx=idx+1 end
  buses[i]=tr; add_channel_fx(tr,true,true)
end
for i=1,8 do
  local tr=REPAIR and existing_role("MATRIX"..i) or nil
  if not tr then tr=insert_track(idx,"MATRIX"..i,string.format("Live32 MATRIX %02d",i)); idx=idx+1 end
  matrices[i]=tr; add_channel_fx(tr,true,false); reaper.SetMediaTrackInfo_Value(tr,"B_MAINSEND",0)
end
main=REPAIR and existing_role("MAIN") or nil
if not main then main=insert_track(idx,"MAIN","Live32 MAIN LR"); idx=idx+1 end
add_channel_fx(main,true,true)
reaper.SetMediaTrackInfo_Value(main,"B_MAINSEND",1)

-- Dedicated engineer monitor / solo bus. This never feeds MAIN LR; it is intended
-- to be patched to a separate hardware output pair from the ROUTING page.
monitor=REPAIR and existing_role("MONITOR") or nil
if not monitor then monitor=insert_track(idx,"MONITOR","Live32 MONITOR"); idx=idx+1 end
reaper.SetMediaTrackInfo_Value(monitor,"B_MAINSEND",0)
reaper.SetMediaTrackInfo_Value(monitor,"B_SHOWINTCP",0)
reaper.SetMediaTrackInfo_Value(monitor,"B_SHOWINMIXER",0)
local function ext_default(tr,key,value)
  local _,v=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:"..key,"",false)
  if not v or v=="" then reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:"..key,tostring(value),true) end
end
ext_default(monitor,"LIVE32_MON_CH_AFL","0")
ext_default(monitor,"LIVE32_MON_BUS_AFL","1")
ext_default(monitor,"LIVE32_MON_DCA_AFL","1")
ext_default(monitor,"LIVE32_MON_SELECT_FOLLOWS","0")
ext_default(monitor,"LIVE32_MON_SOLO_FOLLOWS_SELECT","0")
ext_default(monitor,"LIVE32_MON_DIM_PFL","0")
ext_default(monitor,"LIVE32_MON_MASTER_FADER","0")
ext_default(monitor,"LIVE32_MON_DIM_DB","-20")
ext_default(monitor,"LIVE32_MON_LEVEL_DB","0")
ext_default(monitor,"LIVE32_MON_SOURCE","MAIN")
ext_default(monitor,"LIVE32_HW_OUT","-1")

-- Hidden DCA/VCA lead tracks.
for d=1,8 do
  local tr=REPAIR and existing_role("DCA"..d) or nil
  if not tr then tr=insert_track(idx,"DCA"..d,string.format("Live32 DCA %02d",d)); idx=idx+1 end
  dcas[d]=tr
  reaper.SetMediaTrackInfo_Value(tr,"B_MAINSEND",0); reaper.SetMediaTrackInfo_Value(tr,"B_SHOWINTCP",0); reaper.SetMediaTrackInfo_Value(tr,"B_SHOWINMIXER",0)
  local groupnum=56+d
  for _,g in ipairs({"VOLUME_VCA_LEAD","MUTE_LEAD"}) do set_group_ex(tr,g,groupnum,true) end
end
-- Hidden mute-group lead tracks.
for g=1,6 do
  local tr=REPAIR and existing_role("MUTEGRP"..g) or nil
  if not tr then tr=insert_track(idx,"MUTEGRP"..g,string.format("Live32 Mute Group %d",g)); idx=idx+1 end
  mutegroups[g]=tr
  reaper.SetMediaTrackInfo_Value(tr,"B_MAINSEND",0); reaper.SetMediaTrackInfo_Value(tr,"B_SHOWINTCP",0); reaper.SetMediaTrackInfo_Value(tr,"B_SHOWINMIXER",0)
  set_group_ex(tr,"MUTE_LEAD",48+g,true)
end

-- Internal Main LR architecture. Every source is explicitly routed to Live32 MAIN LR;
-- REAPER's actual master is only the final output stage. This makes MAIN -> Matrix legal.
-- M32-style bus preconfiguration. Live32 exposes five useful tap modes:
-- PRE EQ = after LOW CUT/Gate, POST EQ = after EQ/before Dynamics,
-- PRE FADER = after Dynamics/before source fader, POST FADER = after fader,
-- SUB GROUP = post-fader unity assignment (send control becomes on/off).
local BUS_MODES={
  PRE_EQ={sendmode=3,srcchan=4},
  POST_EQ={sendmode=3,srcchan=6},
  PRE_FADER={sendmode=3,srcchan=0},
  POST_FADER={sendmode=0,srcchan=0},
  SUBGROUP={sendmode=0,srcchan=0}
}
for b=1,16 do
  local mode=(b>=13) and "POST_FADER" or "PRE_FADER"
  reaper.GetSetMediaTrackInfo_String(buses[b],"P_EXT:LIVE32_BUS_TAP",mode,true)
end
local function make_bus_send(src,b)
  local id=(b>=13) and "POST_FADER" or "PRE_FADER"
  local m=BUS_MODES[id]
  return ensure_send(src,buses[b],0.0,m.sendmode,m.srcchan)
end
for i=1,32 do
  reaper.SetMediaTrackInfo_Value(channels[i],"B_MAINSEND",0)
  ensure_send(channels[i],main,1.0,0)
  for b=1,16 do make_bus_send(channels[i],b) end
end
for i=1,8 do
  reaper.SetMediaTrackInfo_Value(fxreturns[i],"B_MAINSEND",0)
  ensure_send(fxreturns[i],main,1.0,0)
  for b=1,12 do make_bus_send(fxreturns[i],b) end
end
for b=1,16 do
  reaper.SetMediaTrackInfo_Value(buses[b],"B_MAINSEND",0)
  ensure_send(buses[b],main,0.0,0)
  for m=1,8 do ensure_send(buses[b],matrices[m],0.0,0) end
end
for m=1,8 do ensure_send(main,matrices[m],0.0,0) end

-- Monitor routing. MAIN is the normal monitor source; every source/output also
-- owns a muted send which Live32 opens only while that object is soloed.
local main_mon=ensure_send(main,monitor,1.0,3,0)
if main_mon>=0 then reaper.SetTrackSendInfo_Value(main,0,main_mon,"B_MUTE",0) end
local function ensure_monitor_send(src)
  local s=ensure_send(src,monitor,1.0,3,0)
  if s>=0 then reaper.SetTrackSendInfo_Value(src,0,s,"B_MUTE",1) end
  return s
end
for i=1,32 do ensure_monitor_send(channels[i]) end
for i=1,8 do ensure_monitor_send(fxreturns[i]) end
for i=1,16 do ensure_monitor_send(buses[i]) end
for i=1,8 do ensure_monitor_send(matrices[i]) end

-- Internal FX engines on Buses 13-16.
local specs={
  [13]={label="PLATE",kind="plate"}, [14]={label="HALL",kind="hall"},
  [15]={label="DELAY",kind="delay"}, [16]={label="CHORUS",kind="chorus"}
}
for b=13,16 do
  local tr=buses[b]; local spec=specs[b]
  reaper.GetSetMediaTrackInfo_String(tr,"P_NAME",string.format("Live32 BUS %02d - %s",b,spec.label),true)
  reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_FXENGINE",spec.kind,true)
  local fx=-1
  if spec.kind=="plate" or spec.kind=="hall" then
    fx=find_fx(tr,"reaverbate")
    if fx<0 then
      fx=add_fx_candidates(tr,{"ReaVerbate (Cockos)","VST: ReaVerbate (Cockos)","ReaVerbate"},"reaverbate")
      if fx>=0 then configure_reverb(tr,fx,spec.kind) end
    end
  elseif spec.kind=="delay" then
    fx=find_fx(tr,"pingpong")
    if fx<0 then
      fx=add_fx_candidates(tr,{"JS: Live32/Live32_PingPongDelay","Live32 One-Shot PingPong Delay"},"pingpong")
      if fx>=0 then
        reaper.TrackFX_SetParam(tr,fx,0,500); reaper.TrackFX_SetParam(tr,fx,1,-3); reaper.TrackFX_SetParam(tr,fx,2,-6); reaper.TrackFX_SetParam(tr,fx,3,0)
      end
    end
  else
    fx=find_fx(tr,"chorus")
    if fx<0 then
      local chorus=find_stock_chorus_name()
      if chorus then fx=reaper.TrackFX_AddByName(tr,chorus,false,1) end
      if fx<0 then
        for _,cand in ipairs({"JS: Chorus (Guitar chorus)","JS: Guitar/Chorus","JS: Guitar/chorus","JS: Chorus","JS: chorus"}) do
          fx=reaper.TrackFX_AddByName(tr,cand,false,1); if fx>=0 then break end
        end
      end
      if fx>=0 then configure_chorus(tr,fx) end
    end
  end
  if fx<0 then warnings[#warnings+1]=string.format("BUS %02d %s stock effect was not found",b,spec.label) end
end

local fxlabels={"PLATE","HALL","DELAY","CHORUS"}
for pair=1,4 do
  local l=fxreturns[(pair-1)*2+1]; local r=fxreturns[(pair-1)*2+2]; local bus=buses[12+pair]
  local li=(pair-1)*2+1; local ri=li+1; local label=fxlabels[pair]
  reaper.GetSetMediaTrackInfo_String(l,"P_NAME",string.format("Live32 FX RTN %02d - %s L",li,label),true)
  reaper.GetSetMediaTrackInfo_String(r,"P_NAME",string.format("Live32 FX RTN %02d - %s R",ri,label),true)
  reaper.GetSetMediaTrackInfo_String(l,"P_EXT:LIVE32_FXPAIR",tostring(pair),true)
  reaper.GetSetMediaTrackInfo_String(r,"P_EXT:LIVE32_FXPAIR",tostring(pair),true)
  reaper.SetMediaTrackInfo_Value(l,"D_PAN",-1.0); reaper.SetMediaTrackInfo_Value(r,"D_PAN",1.0)
  configure_fx_pair_group(l,r,pair)
  local sl=ensure_send(bus,l,1.0,0); if sl>=0 then reaper.SetTrackSendInfo_Value(bus,0,sl,"I_SRCCHAN",1024) end
  local sr=ensure_send(bus,r,1.0,0); if sr>=0 then reaper.SetTrackSendInfo_Value(bus,0,sr,"I_SRCCHAN",1025) end
end

-- Post-processing meter/RTA taps. RTA starts disabled; the console enables only
-- the currently selected signal, so the extra analyser instances are effectively idle.
local audio_tracks={}
for i=1,32 do audio_tracks[#audio_tracks+1]=channels[i] end
for i=1,8 do audio_tracks[#audio_tracks+1]=fxreturns[i] end
for i=1,16 do audio_tracks[#audio_tracks+1]=buses[i] end
for i=1,8 do audio_tracks[#audio_tracks+1]=matrices[i] end
audio_tracks[#audio_tracks+1]=main
for _,tr in ipairs(audio_tracks) do
  if add_meter_tap(tr)<0 then warnings[#warnings+1]="A Live32 Meter Tap could not be loaded" end
  if add_rta(tr)<0 then warnings[#warnings+1]="A Live32 RTA Tap could not be loaded" end
end

reaper.PreventUIRefresh(-1); reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange()
reaper.Undo_EndBlock(REPAIR and "Repair Live32 v1.2 console" or "Create Live32 v1.2 console",-1)

local out=(REPAIR and "Live32 project repaired and completed." or "Live32 v1.2 console is ready.").."\n\n32 inputs • 8 FX returns • 16 buses • 8 matrices • 8 DCAs • 6 mute groups • internal MAIN LR • dedicated MONITOR/SOLO bus.\nInputs/FX: 24 dB/oct LOW CUT + 4-band EQ. Buses/Main: 24 dB/oct LOW CUT + 6-band EQ.\nBus modes: PRE EQ • POST EQ • PRE FADER • POST FADER • SUB GROUP.\nBUS 13=Plate, 14=Hall, 15=Delay, 16=Chorus.\nInsert library: Precision Limiter • 31-band GEQ • FET 76 • Opto 2A.\nMAIN LR can feed Matrix 1-8. ROUTING can patch MAIN, MONITOR, buses and matrices to hardware outputs.\nMONITOR page provides Channel/MixBus/DCA PFL/AFL options without interrupting FOH.\n\nOpen Live32 from the Launcher."
if #warnings>0 then out=out.."\n\nPlease check:\n- "..table.concat(warnings,"\n- ") end
msg(out)
