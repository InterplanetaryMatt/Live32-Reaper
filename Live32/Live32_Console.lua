-- Live32 v1.2.1 virtual live console for REAPER
-- Teaching-oriented M32-style workflow; not an exact visual or DSP clone.
-- v1.1 adds the launcher/attach/import workflow while retaining the v1.0.6 console feature set.
-- v1.2: dedicated monitor/solo bus, M32-style MONITOR page, PFL/AFL options and hardware output routing.

local W, H = 1440, 940
local selected = 1
local selected_kind = "CH" -- "CH" or "FX"
local source_layer = 1 -- 1=CH1-8, 2=CH9-16, 3=CH17-24, 4=CH25-32, 5=FX1-8
local bus_fader_layer = 1 -- 1=BUS1-8, 2=BUS9-16, 3=MATRIX1-8, 4=DCA1-8
local selected_band = 2 -- input/FX: 1=LOW, 2=LO MID, 3=HI MID, 4=HIGH
local selected_eq_target = 2 -- input/FX: 0=LOW CUT, 1..4=EQ bands
selected_output_band = 2 -- buses/Main: 1..6 output EQ bands
selected_output_eq_target = 2 -- buses/Main: 0=LOW CUT, 1..6=EQ bands
local dyn_page = 1 -- compressor LCD page: 1=main controls, 2=knee/key
local sof = false
local sof_focus = "bus" -- "bus" = source faders feed selected bus; "source" = bus faders show selected source sends
local meter_focus = "source" -- last explicitly selected source/FX return, bus, matrix, or DCA control object
local selected_bus = 1 -- bus used by Sends on Faders and bus processing
local selected_matrix = 1 -- selected/target matrix output
local selected_dca = 1 -- selected DCA control group
local bus_bank = 1 -- 1=BUS 1-4, 2=5-8, 3=9-12, 4=13-16
local matrix_bank = 1 -- 1=MATRIX 1-4, 2=MATRIX 5-8
local screen_page = "home" -- home, preamp, gate, dyn, eq, sends, meters, routing, monitor, setup, effects, scenes
effects_subpage = "engine" -- dedicated FX buses always open their engine; other sources use insert
route_page = 1 -- 1=MAIN/MONITOR, 2=BUS1-8, 3=BUS9-16, 4=MTX1-8
local last_delay_tap = nil
local prev_mouse = 0
local active_knob = nil
local setup_editing = false
local setup_buffer = ""
local setup_target = nil
local default_track_label
local track_display_label

local C = {
  bg={0.035,0.038,0.042}, shell={0.075,0.080,0.086}, panel={0.095,0.102,0.108},
  panel2={0.125,0.133,0.142}, edge={0.30,0.32,0.34}, edge2={0.18,0.19,0.20},
  text={0.90,0.91,0.91}, dim={0.55,0.58,0.60}, blue={0.43,0.66,0.98},
  blue2={0.20,0.45,0.82}, amber={1.00,0.71,0.16}, orange={1.00,0.55,0.34},
  green={0.18,0.82,0.38}, yellow={0.96,0.78,0.18}, red={0.94,0.20,0.20},
  black={0.015,0.017,0.019}, white={0.98,0.98,0.98}, purple={0.48,0.18,0.62}
}

local function setc(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,fill)
  setc(c)
  gfx.rect(x,y,w,h,fill == false and 0 or 1)
end
local function line(x1,y1,x2,y2,c,w)
  setc(c)
  gfx.line(x1,y1,x2,y2,w or 1)
end
local function circle(x,y,r,c,fill)
  setc(c)
  gfx.circle(x,y,r,fill == false and 0 or 1,true)
end
local function text(x,y,s,size,c)
  gfx.setfont(1,"Arial",size or 15)
  setc(c or C.text)
  gfx.x=x; gfx.y=y; gfx.drawstr(s)
end
local function centered(x,y,w,s,size,c)
  gfx.setfont(1,"Arial",size or 15)
  local tw=gfx.measurestr(s)
  text(x+(w-tw)/2,y,s,size,c)
end
local function inside(mx,my,x,y,w,h)
  return mx>=x and mx<=x+w and my>=y and my<=y+h
end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function db2lin(db) return 10^(db/20) end
local function lin2db(v)
  if v<=0.0000001 then return -150 end
  return 20*math.log(v,10)
end
local function fmt_db(db)
  if db <= -90 then return "-inf" end
  return string.format("%+.1f",db)
end
local function fmt_hz(v)
  if v >= 1000 then
    local k=v/1000
    if k >= 10 then return string.format("%.1fk",k) end
    return string.format("%.2fk",k)
  end
  return string.format("%.0f",v)
end
local function fmt_ms(v)
  if v >= 1000 then return string.format("%.2fs",v/1000) end
  if v < 10 then return string.format("%.1fms",v) end
  return string.format("%.0fms",v)
end
local function short_name(s)
  s=s or ""
  s=s:gsub("^Live32 CH %d+%s*%-?%s*","")
  s=s:gsub("^Live32 CH %d+","")
  s=s:gsub("^Live32 FX RTN %d+%s*%-?%s*","")
  s=s:gsub("^Live32 FX RTN %d+","")
  if s=="" then return "INPUT" end
  if #s>13 then return s:sub(1,13) end
  return s
end

-- Scribble-strip metadata is stored in the REAPER project so cosmetic changes
-- travel with the session without renaming or recolouring the underlying tracks.
local SCRIBBLE_COLORS={
  blue={0.08,0.23,0.48}, purple={0.43,0.13,0.57}, cyan={0.06,0.34,0.40},
  green={0.08,0.34,0.18}, yellow={0.42,0.34,0.05}, orange={0.46,0.23,0.05},
  red={0.42,0.08,0.08}, pink={0.43,0.10,0.28}
}
local function is_master_track(tr)
  if not tr then return false end
  local _,role=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE","",false)
  return role=="MAIN"
end
local function get_ext(tr,key)
  local _,v=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:"..key,"",false)
  return v or ""
end
local function set_ext(tr,key,v)
  reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:"..key,v or "",true)
end
local function track_role(tr) return get_ext(tr,"LIVE32_ROLE") end
local function custom_label(tr) return get_ext(tr,"LIVE32_LABEL") end
local function set_custom_label(tr,v) set_ext(tr,"LIVE32_LABEL",v or "") end
local function default_scribble_key(tr)
  local role=track_role(tr)
  if role=="MAIN" then return "orange" end
  if role:match("^FXRTN%d+$") then return "purple" end
  local b=tonumber(role:match("^BUS(%d+)$") or "")
  if b and b>=13 and b<=16 then return "purple" end
  if role:match("^DCA%d+$") then return "yellow" end
  return "blue"
end
local function scribble_key(tr)
  local k=get_ext(tr,"LIVE32_COLOR")
  if SCRIBBLE_COLORS[k] then return k end
  return default_scribble_key(tr)
end
local function scribble_color(tr) return SCRIBBLE_COLORS[scribble_key(tr)] or SCRIBBLE_COLORS.blue end
local function set_scribble_key(tr,k)
  if SCRIBBLE_COLORS[k] then set_ext(tr,"LIVE32_COLOR",k) else set_ext(tr,"LIVE32_COLOR","") end
end

local function panel(x,y,w,h,title)
  rect(x,y,w,h,C.panel,true)
  rect(x,y,w,h,C.edge,false)
  text(x+12,y+8,title,15,C.text)
  line(x+8,y+31,x+w-8,y+31,C.edge2,1)
end

local function find_roles()
  local ch, fxr, buses, matrices, dcas, mutegroups = {}, {}, {}, {}, {}, {}
  local main=nil
  local monitor=nil
  for i=0,reaper.CountTracks(0)-1 do
    local tr=reaper.GetTrack(0,i)
    local _,role=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE","",false)
    local n=role:match("^CH(%d+)$")
    local f=role:match("^FXRTN(%d+)$")
    local b=role:match("^BUS(%d+)$")
    local m=role:match("^MATRIX(%d+)$")
    local d=role:match("^DCA(%d+)$")
    local g=role:match("^MUTEGRP(%d+)$")
    if n then ch[tonumber(n)]=tr
    elseif f then fxr[tonumber(f)]=tr
    elseif b then buses[tonumber(b)]=tr
    elseif m then matrices[tonumber(m)]=tr
    elseif d then dcas[tonumber(d)]=tr
    elseif g then mutegroups[tonumber(g)]=tr
    elseif role=="MAIN" then main=tr
    elseif role=="MONITOR" then monitor=tr end
  end
  return ch,fxr,buses,matrices,dcas,mutegroups,main,monitor
end

local channels,fxreturns,buses,matrices,dcas,mutegroups,master,monitor=find_roles()
if not channels[1] or not buses[1] then
  reaper.ShowMessageBox("Live32 tracks were not found. Run Live32 Launcher first.","Live32 v1.2.1",0)
  return
end
for i=1,32 do
  if not channels[i] then
    reaper.ShowMessageBox("This project does not yet contain all 32 Live32 input channels.\n\nThis project is missing part of the Live32 console. Use Live32 Launcher to build or attach the console.","Live32 v1.2.1",0)
    return
  end
end
for i=1,8 do
  if not fxreturns[i] then
    reaper.ShowMessageBox("This project does not yet contain all 8 Live32 FX returns.\n\nThis project is missing part of the Live32 console. Use Live32 Launcher to build or attach the console.","Live32 v1.2.1",0)
    return
  end
end
for i=1,16 do
  if not buses[i] then
    reaper.ShowMessageBox("This project does not yet contain all 16 Live32 buses.\n\nThis project is missing part of the Live32 console. Use Live32 Launcher to build or attach the console.","Live32 v1.2.1",0)
    return
  end
end
for i=1,8 do
  if not matrices[i] then
    reaper.ShowMessageBox("This project does not yet contain all 8 Live32 matrix outputs.\n\nThis project is missing the Live32 matrix section. Use Live32 Launcher to build or attach the console.","Live32 v1.2.1",0)
    return
  end
end
for i=1,8 do
  if not dcas[i] then
    reaper.ShowMessageBox("This project does not yet contain all 8 Live32 DCA groups.\n\nThis project is missing the Live32 DCA section. Use Live32 Launcher to build or attach the console.","Live32 v1.2.1",0)
    return
  end
end
for i=1,6 do
  if not mutegroups[i] then
    reaper.ShowMessageBox("This project does not yet contain all 6 Live32 mute groups. Use Live32 Launcher to build or repair the console.","Live32 v1.2.1",0)
    return
  end
end
if not master then
  reaper.ShowMessageBox("Live32 MAIN LR was not found. Use Live32 Launcher to build or repair the console.","Live32 v1.2.1",0)
  return
end
if not monitor then
  reaper.ShowMessageBox("Live32 MONITOR/SOLO bus was not found.\n\nOpen Live32 Launcher and choose REPAIR / COMPLETE LIVE32 PROJECT once to add the v1.2 monitor architecture.","Live32 v1.2.1",0)
  return
end

-- Live32 reserves REAPER VCA groups 57-64 for DCA 1-8, keeping them away from
-- the low-numbered grouping slots users are most likely to use themselves.
local DCA_GROUP_BASE=56
local function dca_group_bit(dcan)
  local groupnum=DCA_GROUP_BASE+dcan
  local offset=math.floor((groupnum-1)/32)*32
  local bit=1 << ((groupnum-1)%32)
  return offset,bit
end
local function group_membership(tr,groupname,dcan)
  if not tr or not reaper.GetSetTrackGroupMembershipEx then return false end
  local offset,bit=dca_group_bit(dcan)
  local state=reaper.GetSetTrackGroupMembershipEx(tr,groupname,offset,0,0) or 0
  return (state & bit)~=0
end
local function set_group_membership(tr,groupname,dcan,on)
  if not tr or not reaper.GetSetTrackGroupMembershipEx then return end
  local offset,bit=dca_group_bit(dcan)
  reaper.GetSetTrackGroupMembershipEx(tr,groupname,offset,bit,on and bit or 0)
end
local function dca_member(tr,dcan)
  return group_membership(tr,"VOLUME_VCA_FOLLOW",dcan)
end
local function set_dca_member_one(tr,dcan,on)
  set_group_membership(tr,"VOLUME_VCA_FOLLOW",dcan,on)
  set_group_membership(tr,"MUTE_FOLLOW",dcan,on)
  if dcas[dcan] and get_ext(dcas[dcan],"LIVE32_DCA_SOLO")=="1" and update_monitor_solo_routing then update_monitor_solo_routing() end
end
local function dca_member_count(dcan)
  local n=0
  for i=1,32 do if channels[i] and dca_member(channels[i],dcan) then n=n+1 end end
  for i=1,8 do if fxreturns[i] and dca_member(fxreturns[i],dcan) then n=n+1 end end
  for i=1,16 do if buses[i] and dca_member(buses[i],dcan) then n=n+1 end end
  return n
end

-- DCA SOLO is intentionally handled by Live32 rather than REAPER's SOLO_LEAD
-- on the hidden DCA control track. The DCA track carries no audio; soloing it
-- can mute the downstream Live32 mix path. Instead we solo the DCA's real
-- member tracks directly and keep a project-persistent flag on the DCA control.
local function dca_solo_active(dcan)
  local tr=dcas[dcan]
  if not tr then return false end
  local _,v=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_DCA_SOLO","",false)
  return v=="1"
end

local function other_active_dca_solos_for_track(tr,except_dca)
  for d=1,8 do
    if d~=except_dca and dca_solo_active(d) and dca_member(tr,d) then return true end
  end
  return false
end

local function set_dca_member_solo_state(tr,dcan,on)
  if not tr then return end
  if on then
    -- Preserve the user's pre-existing manual solo state when the first active
    -- DCA solo takes ownership of this member.
    if not other_active_dca_solos_for_track(tr,dcan) then
      local current=math.floor(reaper.GetMediaTrackInfo_Value(tr,"I_SOLO") or 0)
      reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_DCA_SOLO_BASE",tostring(current),true)
    end
    reaper.SetMediaTrackInfo_Value(tr,"I_SOLO",2)
  else
    if other_active_dca_solos_for_track(tr,dcan) then
      reaper.SetMediaTrackInfo_Value(tr,"I_SOLO",2)
    else
      local _,base=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_DCA_SOLO_BASE","",false)
      reaper.SetMediaTrackInfo_Value(tr,"I_SOLO",tonumber(base) or 0)
      reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_DCA_SOLO_BASE","",true)
    end
  end
end

local function set_dca_solo_active(dcan,on)
  local tr=dcas[dcan]
  if not tr then return end
  reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_DCA_SOLO",on and "1" or "0",true)
  -- The DCA control track carries no audio and never enters REAPER's native solo.
  reaper.SetMediaTrackInfo_Value(tr,"I_SOLO",0)
  if update_monitor_solo_routing then update_monitor_solo_routing() end
  reaper.UpdateArrange()
end

-- Older Live32 builds used native SOLO_LEAD/SOLO_FOLLOW grouping for DCAs.
-- Remove those solo-group memberships on load; DCA VCA and mute grouping remain native.
local function normalise_dca_solo_groups()
  for d=1,8 do
    if dcas[d] then set_group_membership(dcas[d],"SOLO_LEAD",d,false) end
    for i=1,32 do if channels[i] then set_group_membership(channels[i],"SOLO_FOLLOW",d,false) end end
    for i=1,8 do if fxreturns[i] then set_group_membership(fxreturns[i],"SOLO_FOLLOW",d,false) end end
    for i=1,16 do if buses[i] then set_group_membership(buses[i],"SOLO_FOLLOW",d,false) end end
  end
end
normalise_dca_solo_groups()

-- Six M32-style Mute Groups use hidden REAPER MUTE_LEAD tracks in grouping slots 49-54.
MUTE_GROUP_BASE=48
function mute_group_bit(grp)
  local groupnum=MUTE_GROUP_BASE+grp
  local offset=math.floor((groupnum-1)/32)*32
  local bit=1 << ((groupnum-1)%32)
  return offset,bit
end
function mute_group_member(tr,grp)
  if not tr or not reaper.GetSetTrackGroupMembershipEx then return false end
  local offset,bit=mute_group_bit(grp)
  local state=reaper.GetSetTrackGroupMembershipEx(tr,"MUTE_FOLLOW",offset,0,0) or 0
  return (state & bit)~=0
end
function set_mute_group_member_one(tr,grp,on)
  if not tr or not reaper.GetSetTrackGroupMembershipEx then return end
  local offset,bit=mute_group_bit(grp)
  reaper.GetSetTrackGroupMembershipEx(tr,"MUTE_FOLLOW",offset,bit,on and bit or 0)
end
function mute_group_on(grp)
  local tr=mutegroups[grp]
  return tr and reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5 or false
end
function set_mute_group_on(grp,on)
  local tr=mutegroups[grp]
  if tr then reaper.SetTrackUIMute(tr,on and 1 or 0,0) end
end

local function selected_track()
  if selected_kind=="FX" then return fxreturns[selected] end
  return channels[selected]
end

local function selected_prefix()
  if selected_kind=="FX" then return string.format("FX %02d",selected) end
  return string.format("CH %02d",selected)
end

-- Explicit selection determines which object owns the processing surface.
-- Inputs, FX returns, buses and matrices can all use the same Live32 DSP section.
local function control_is_bus() return meter_focus=="bus" and buses[selected_bus]~=nil end
local function control_is_matrix() return meter_focus=="matrix" and matrices[selected_matrix]~=nil end
local function control_is_dca() return meter_focus=="dca" and dcas[selected_dca]~=nil end
local function control_is_master() return meter_focus=="master" end
local function control_track()
  if control_is_master() then return master end
  if control_is_dca() then return dcas[selected_dca] end
  if control_is_matrix() then return matrices[selected_matrix] end
  if control_is_bus() then return buses[selected_bus] end
  return selected_track()
end
local function control_prefix()
  if control_is_master() then return "MAIN LR" end
  if control_is_dca() then return string.format("DCA %02d",selected_dca) end
  if control_is_matrix() then return string.format("MTX %02d",selected_matrix) end
  if control_is_bus() then return string.format("BUS %02d",selected_bus) end
  return selected_prefix()
end
local function control_name()
  local tr=control_track()
  local custom=custom_label(tr)
  if custom~="" then return custom end
  if default_track_label then return default_track_label(tr) end
  local _,nm=reaper.GetTrackName(tr,"")
  return short_name(nm)
end

local function fx_pair_index(idx)
  if idx<1 or idx>8 then return nil,nil end
  local left=math.floor((idx-1)/2)*2+1
  return left,left+1
end

local function fx_partner(tr)
  for i=1,8 do
    if fxreturns[i]==tr then
      local a,b=fx_pair_index(i)
      if i==a then return fxreturns[b] else return fxreturns[a] end
    end
  end
  return nil
end

-- FX returns are fixed stereo pairs: odd return = Left, even return = Right.
-- Enforcing this while Live32 is open means accidental REAPER pan changes cannot
-- collapse the Plate/Hall/Delay/Chorus returns back toward mono.
local function enforce_fx_return_pans()
  for i=1,8 do
    local tr=fxreturns[i]
    if tr then
      local target=(i%2==1) and -1.0 or 1.0
      local pan=reaper.GetMediaTrackInfo_Value(tr,"D_PAN") or 0
      if math.abs(pan-target)>0.0001 then
        reaper.SetMediaTrackInfo_Value(tr,"D_PAN",target)
      end
    end
  end
end

local function selected_meter_track()
  -- PFL only exists when something is actually soloed. Prefer the currently
  -- selected processing object if it is soloed; otherwise show the first soloed
  -- Live32 source/output. With no solos the PFL meter is dark.
  local tr=control_track()
  if (not control_is_dca()) and tr and reaper.GetMediaTrackInfo_Value(tr,"I_SOLO")>0 then
    return tr,control_prefix()
  end
  for i=1,32 do
    tr=channels[i]
    if tr and reaper.GetMediaTrackInfo_Value(tr,"I_SOLO")>0 then return tr,string.format("CH %02d",i) end
  end
  for i=1,8 do
    tr=fxreturns[i]
    if tr and reaper.GetMediaTrackInfo_Value(tr,"I_SOLO")>0 then return tr,string.format("FX %02d",i) end
  end
  for i=1,16 do
    tr=buses[i]
    if tr and reaper.GetMediaTrackInfo_Value(tr,"I_SOLO")>0 then return tr,string.format("BUS %02d",i) end
  end
  for i=1,8 do
    tr=matrices[i]
    if tr and reaper.GetMediaTrackInfo_Value(tr,"I_SOLO")>0 then return tr,string.format("MTX %02d",i) end
  end
  return nil,"NO SOLO"
end

local function fx_return_name(idx)
  local names={"PLATE L","PLATE R","HALL L","HALL R","DELAY L","DELAY R","CHORUS L","CHORUS R"}
  return names[idx] or ("FX "..idx)
end

local function bus_role_name(busn)
  local names={[13]="PLATE",[14]="HALL",[15]="DELAY",[16]="CHORUS"}
  return names[busn]
end

default_track_label=function(tr)
  local role=track_role(tr)
  if role=="MAIN" then return "MASTER" end
  local n=tonumber(role:match("^CH(%d+)$") or "")
  if n then
    local _,nm=reaper.GetTrackName(tr,"")
    return short_name(nm)
  end
  local f=tonumber(role:match("^FXRTN(%d+)$") or "")
  if f then return fx_return_name(f) end
  local b=tonumber(role:match("^BUS(%d+)$") or "")
  if b then return bus_role_name(b) or "MIX BUS" end
  local m=tonumber(role:match("^MATRIX(%d+)$") or "")
  if m then return "MATRIX OUT" end
  local d=tonumber(role:match("^DCA(%d+)$") or "")
  if d then return "DCA GROUP" end
  local _,nm=reaper.GetTrackName(tr,"")
  return short_name(nm)
end
track_display_label=function(tr)
  local c=custom_label(tr)
  if c~="" then return c end
  return default_track_label(tr)
end

-- User-created stereo links mirror the M32 odd/even link convention.
-- Only input channels and mix buses are linkable: 1-2, 3-4 ... 31-32 / 15-16.
-- The state is stored on the REAPER tracks so it survives closing Live32 and reopening the project.
local function live32_role(tr)
  if not tr then return nil,nil end
  local _,role=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE","",false)
  local n=role:match("^CH(%d+)$")
  if n then return "CH",tonumber(n) end
  n=role:match("^BUS(%d+)$")
  if n then return "BUS",tonumber(n) end
  return nil,nil
end

local function stereo_link_pair(tr)
  local kind,n=live32_role(tr)
  if not kind or not n then return nil,nil,nil,nil,nil end
  local odd=(n%2==1) and n or (n-1)
  local even=odd+1
  local a,b
  if kind=="CH" then a,b=channels[odd],channels[even]
  elseif kind=="BUS" then a,b=buses[odd],buses[even] end
  if not a or not b then return nil,nil,nil,nil,nil end
  return a,b,kind,odd,even
end

local function stereo_link_on(tr)
  local a,b=stereo_link_pair(tr)
  if not a or not b then return false end
  local _,va=reaper.GetSetMediaTrackInfo_String(a,"P_EXT:LIVE32_STEREO_LINK","",false)
  local _,vb=reaper.GetSetMediaTrackInfo_String(b,"P_EXT:LIVE32_STEREO_LINK","",false)
  return va=="1" or vb=="1"
end

local function stereo_link_partner(tr)
  local a,b=stereo_link_pair(tr)
  if not a or not stereo_link_on(tr) then return nil end
  return tr==a and b or a
end

-- Return a stereo source pair in deterministic L/R order when the selected source
-- is either one of Live32's permanent stereo FX returns or a user-linked CH pair.
-- This helper is used by the send engine so linked sources keep their stereo image.
local function active_source_stereo_pair(tr)
  if not tr then return nil,nil end

  -- FX returns are permanently paired 1/2, 3/4, 5/6, 7/8. Always return the
  -- odd member first (Left) and the even member second (Right), regardless of
  -- which side the user currently has selected.
  for i=1,8 do
    if fxreturns[i]==tr then
      local odd=(i%2==1) and i or (i-1)
      local even=odd+1
      if fxreturns[odd] and fxreturns[even] then
        return fxreturns[odd],fxreturns[even]
      end
      return nil,nil
    end
  end

  -- User-created input-channel stereo links use the same odd=L / even=R rule.
  -- Bus pairs are destinations here, not source-channel pairs, so they are not
  -- returned by this helper when setting an input/FX -> bus send.
  local a,b,kind=stereo_link_pair(tr)
  if kind=="CH" and a and b and stereo_link_on(tr) then return a,b end
  return nil,nil
end

local function set_dca_member(tr,dcan,on)
  set_dca_member_one(tr,dcan,on)
  local partner=fx_partner(tr) or stereo_link_partner(tr)
  if partner then set_dca_member_one(partner,dcan,on) end
end
function set_mute_group_member(tr,grp,on)
  set_mute_group_member_one(tr,grp,on)
  local partner=fx_partner(tr) or stereo_link_partner(tr)
  if partner then set_mute_group_member_one(partner,grp,on) end
end

local sync_stereo_link_from_left

local function set_stereo_link(tr,on)
  local a,b=stereo_link_pair(tr)
  if not a or not b then return end
  local v=on and "1" or ""
  reaper.GetSetMediaTrackInfo_String(a,"P_EXT:LIVE32_STEREO_LINK",v,true)
  reaper.GetSetMediaTrackInfo_String(b,"P_EXT:LIVE32_STEREO_LINK",v,true)
  if on then
    -- The odd member is the master when the link is created. v0.9.3 copies the
    -- complete Live32 channel state and routing from odd -> even, then all Live32
    -- edits are mirrored in both directions while the pair remains linked.
    reaper.SetMediaTrackInfo_Value(a,"D_PAN",-1.0)
    reaper.SetMediaTrackInfo_Value(b,"D_PAN", 1.0)
    if sync_stereo_link_from_left then sync_stereo_link_from_left(tr) end
  end
end

local function enforce_stereo_link_pan(tr)
  if not stereo_link_on(tr) then return end
  local a,b=stereo_link_pair(tr)
  if not a or not b then return end
  if math.abs((reaper.GetMediaTrackInfo_Value(a,"D_PAN") or 0)+1)>0.0001 then
    reaper.SetMediaTrackInfo_Value(a,"D_PAN",-1.0)
  end
  if math.abs((reaper.GetMediaTrackInfo_Value(b,"D_PAN") or 0)-1)>0.0001 then
    reaper.SetMediaTrackInfo_Value(b,"D_PAN",1.0)
  end
end

local function source_track_for_slot(slot)
  if source_layer==5 then return fxreturns[slot],"FX",slot end
  local idx=(source_layer-1)*8+slot
  return channels[idx],"CH",idx
end

local function send_index(tr,busn)
  local dest=buses[busn]
  if not dest then return -1 end
  for s=0,reaper.GetTrackNumSends(tr,0)-1 do
    local d=reaper.GetTrackSendInfo_Value(tr,0,s,"P_DESTTRACK")
    if d==dest then return s end
  end
  return -1
end

local function matrix_send_index(tr,matrixn)
  local dest=matrices[matrixn]
  if not dest then return -1 end
  for s=0,reaper.GetTrackNumSends(tr,0)-1 do
    local d=reaper.GetTrackSendInfo_Value(tr,0,s,"P_DESTTRACK")
    if d==dest then return s end
  end
  return -1
end

local function find_fx_named(tr,needle)
  if not tr then return -1 end
  needle=needle:lower()
  for i=0,reaper.TrackFX_GetCount(tr)-1 do
    local _,name=reaper.TrackFX_GetFXName(tr,i,"")
    if name and name:lower():find(needle,1,true) then return i end
  end
  return -1
end

reaper.gmem_attach("Live32RTA")
rta_active_track=nil
function rta_fxidx(tr)
  local fx=find_fx_named(tr,"live32 rta tap")
  if fx<0 then fx=find_fx_named(tr,"live32_rta") end
  return fx
end
function update_rta_focus()
  local target=control_is_dca() and nil or control_track()
  if target==rta_active_track then return end
  if rta_active_track then
    local oldfx=rta_fxidx(rta_active_track)
    if oldfx>=0 then reaper.TrackFX_SetParam(rta_active_track,oldfx,0,0) end
  end
  for i=0,32 do reaper.gmem_write(i,-120) end
  rta_active_track=target
  if target then
    local fx=rta_fxidx(target)
    if fx>=0 then reaper.TrackFX_SetParam(target,fx,0,1) end
  end
end
function draw_rta_overlay(tr,x,y,w,h)
  if tr~=rta_active_track then return end
  local step=w/32
  local bw=math.max(2,step*0.58)
  local rc={0.08,0.52,0.95}
  local rh={0.12,0.76,1.00}
  for i=0,31 do
    local db=reaper.gmem_read(i) or -120
    db=clamp(db,-72,0)
    local n=(db+72)/72
    local bh=n*h
    local bx=x+i*step+(step-bw)/2
    local by=y+h-bh
    setc(rc,0.72)
    gfx.rect(bx,by,bw,bh,1)
    if bh>3 then
      setc(rh,0.92)
      gfx.rect(bx,by,bw,math.min(2,bh),1)
    end
  end
end

local function fxidx(tr)
  local fx=find_fx_named(tr,"live32 channel strip")
  if fx<0 then fx=find_fx_named(tr,"live32_channel") end
  if fx>=0 then return fx end
  -- Existing Live32 source tracks historically used FX slot 0 as a fallback,
  -- but MAIN LR must never accidentally control an unrelated mastering plug-in.
  if is_master_track(tr) then return -1 end
  return 0
end

-- Assignable insert library. These custom Live32 JSFX processors are available on
-- inputs, FX returns, BUS 1-12, matrices and MAIN. BUS 13-16 reserve that slot for
-- their dedicated Plate/Hall/Delay/Chorus engines.
INSERT_DEFS={
  limiter={label="PRECISION LIMITER", short="LIMITER", add="JS: Live32/Live32_PrecisionLimiter", fallback="Live32 Precision Limiter", needle="live32 precision limiter"},
  geq={label="31-BAND GRAPHIC EQ", short="GEQ 31", add="JS: Live32/Live32_GEQ31", fallback="Live32 31-Band Graphic EQ", needle="live32 31-band graphic eq"},
  fet={label="FET 76 COMPRESSOR", short="FET 76", add="JS: Live32/Live32_FET76", fallback="Live32 FET 76 Compressor", needle="live32 fet 76 compressor"},
  opto={label="OPTO 2A COMPRESSOR", short="OPTO 2A", add="JS: Live32/Live32_Opto2A", fallback="Live32 Opto 2A Compressor", needle="live32 opto 2a compressor"}
}

function dedicated_fx_bus_number(tr)
  if not tr then return nil end
  local role=track_role(tr)
  local n=tonumber((role or ""):match("^BUS(%d+)$") or "")
  if n and n>=13 and n<=16 then return n end
  return nil
end

function is_dedicated_fx_bus_track(tr)
  return dedicated_fx_bus_number(tr)~=nil
end

function insert_partner(tr)
  return fx_partner(tr) or stereo_link_partner(tr)
end

function insert_type(tr)
  if not tr then return "none" end
  if is_dedicated_fx_bus_track(tr) then return "none" end
  local key=get_ext(tr,"LIVE32_INSERT")
  if INSERT_DEFS[key] then return key end
  for k,d in pairs(INSERT_DEFS) do
    if find_fx_named(tr,d.needle)>=0 then set_ext(tr,"LIVE32_INSERT",k); return k end
  end
  return "none"
end

function insert_fxidx(tr,key)
  key=key or insert_type(tr)
  local d=INSERT_DEFS[key]
  return d and find_fx_named(tr,d.needle) or -1
end

function clear_insert_one(tr)
  if not tr then return end
  for i=reaper.TrackFX_GetCount(tr)-1,0,-1 do
    local _,nm=reaper.TrackFX_GetFXName(tr,i,"")
    local low=(nm or ""):lower()
    local ours=false
    for _,d in pairs(INSERT_DEFS) do if low:find(d.needle,1,true) then ours=true break end end
    if ours then reaper.TrackFX_Delete(tr,i) end
  end
  set_ext(tr,"LIVE32_INSERT","")
end

function add_insert_one(tr,key)
  clear_insert_one(tr)
  if is_dedicated_fx_bus_track(tr) then return -1 end
  if key=="none" or not INSERT_DEFS[key] then return -1 end
  local d=INSERT_DEFS[key]
  local chfx=fxidx(tr)
  local pos=chfx>=0 and (chfx+1) or 0
  local instantiate=-1000-pos
  local fx=reaper.TrackFX_AddByName(tr,d.add,false,instantiate)
  if fx<0 then fx=reaper.TrackFX_AddByName(tr,d.fallback,false,instantiate) end
  if fx>=0 then set_ext(tr,"LIVE32_INSERT",key) end
  return fx
end

function copy_insert_params(a,b)
  if not a or not b then return end
  local key=insert_type(a)
  if key=="none" then clear_insert_one(b); return end
  if insert_type(b)~=key then add_insert_one(b,key) end
  local afx=insert_fxidx(a,key); local bfx=insert_fxidx(b,key)
  if afx<0 or bfx<0 then return end
  local n=math.min(reaper.TrackFX_GetNumParams(a,afx),reaper.TrackFX_GetNumParams(b,bfx))
  for pi=0,n-1 do
    reaper.TrackFX_SetParamNormalized(b,bfx,pi,reaper.TrackFX_GetParamNormalized(a,afx,pi))
  end
  reaper.TrackFX_SetEnabled(b,bfx,reaper.TrackFX_GetEnabled(a,afx))
end

function set_insert_type(tr,key)
  if not tr then return end
  local role=track_role(tr)
  if role:match("^DCA%d+$") or role:match("^MUTEGRP%d+$") or is_dedicated_fx_bus_track(tr) then return end
  add_insert_one(tr,key)
  local partner=insert_partner(tr)
  if partner then
    add_insert_one(partner,key)
    if key~="none" then copy_insert_params(tr,partner) end
  end
end

function set_insert_enabled(tr,on)
  local key=insert_type(tr); if key=="none" then return end
  local targets={tr,insert_partner(tr)}; local seen={}
  for _,t in pairs(targets) do
    if t and not seen[t] then
      seen[t]=true; local fx=insert_fxidx(t,key); if fx>=0 then reaper.TrackFX_SetEnabled(t,fx,on) end
    end
  end
end

function set_insert_param_norm(tr,param,norm)
  local key=insert_type(tr); if key=="none" then return end
  norm=clamp(norm,0,1)
  local targets={tr,insert_partner(tr)}; local seen={}
  for _,t in pairs(targets) do
    if t and not seen[t] then
      seen[t]=true; local fx=insert_fxidx(t,key); if fx>=0 then reaper.TrackFX_SetParamNormalized(t,fx,param,norm) end
    end
  end
end

function set_insert_param_raw(tr,param,value)
  local key=insert_type(tr); if key=="none" then return end
  local targets={tr,insert_partner(tr)}; local seen={}
  for _,t in pairs(targets) do
    if t and not seen[t] then
      seen[t]=true; local fx=insert_fxidx(t,key); if fx>=0 then reaper.TrackFX_SetParam(t,fx,param,value) end
    end
  end
end

function sync_insert_from_left(a,b)
  if a and b then copy_insert_params(a,b) end
end

local function effect_fx_for_bus(busn)
  local tr=buses[busn]
  if not tr then return -1 end
  if busn==13 or busn==14 then return find_fx_named(tr,"reaverbate")
  elseif busn==15 then
    local fx=find_fx_named(tr,"live32 one-shot pingpong")
    if fx<0 then fx=find_fx_named(tr,"live32_pingpong") end
    return fx
  elseif busn==16 then return find_fx_named(tr,"chorus") end
  return -1
end

local function fx_param_by_names(tr,fx,patterns,exclude)
  if fx<0 then return -1 end
  exclude=exclude or {}
  for p=0,reaper.TrackFX_GetNumParams(tr,fx)-1 do
    local ok,nm=reaper.TrackFX_GetParamName(tr,fx,p)
    local n=(ok and nm or ""):lower()
    local bad=false
    for _,e in ipairs(exclude) do if n:find(e,1,true) then bad=true break end end
    if not bad then
      for _,pat in ipairs(patterns) do if n:find(pat,1,true) then return p end end
    end
  end
  return -1
end

local function fx_value_text(tr,fx,p)
  if p<0 then return "--" end
  local ok,v=reaper.TrackFX_GetFormattedParamValue(tr,fx,p)
  return ok and v or string.format("%.2f",reaper.TrackFX_GetParamNormalized(tr,fx,p))
end

local function find_meter_tap_fx(tr)
  if not tr then return -1 end
  for i=0,reaper.TrackFX_GetCount(tr)-1 do
    local _,name=reaper.TrackFX_GetFXName(tr,i,"")
    if name and name:lower():find("live32 meter tap",1,true) then return i end
  end
  return -1
end

local function pfl_peaks(tr)
  local fx=find_meter_tap_fx(tr)
  if fx>=0 then
    local l=select(1,reaper.TrackFX_GetParam(tr,fx,0)) or 0
    local r=select(1,reaper.TrackFX_GetParam(tr,fx,1)) or 0
    return l,r
  end
  -- Fallback keeps metering useful in projects not yet upgraded to the MeterTap JSFX.
  return reaper.Track_GetPeakInfo(tr,0),reaper.Track_GetPeakInfo(tr,1)
end

local function getp(tr,p)
  local fx=fxidx(tr)
  if fx<0 then return 0 end
  local v=select(1,reaper.TrackFX_GetParam(tr,fx,p))
  return v or 0
end
local function setp(tr,p,v)
  local fx=fxidx(tr)
  if fx>=0 then reaper.TrackFX_SetParam(tr,fx,p,v) end
  -- Factory FX-return pairs and user-created CH/BUS stereo links both share
  -- channel-strip parameters. Selecting either member therefore edits the pair.
  local partners={fx_partner(tr),stereo_link_partner(tr)}
  local seen={}
  for _,partner in pairs(partners) do
    if partner and not seen[partner] and reaper.TrackFX_GetCount(partner)>0 then
      seen[partner]=true
      local pfx=fxidx(partner)
      if pfx>=0 then reaper.TrackFX_SetParam(partner,pfx,p,v) end
    end
  end
end
local function track_db(tr) return lin2db(reaper.GetMediaTrackInfo_Value(tr,"D_VOL")) end
local function set_track_db(tr,db)
  local lin=db<=-90 and 0.0 or db2lin(db)
  reaper.SetMediaTrackInfo_Value(tr,"D_VOL",lin)
  local partner=fx_partner(tr)
  if partner then reaper.SetMediaTrackInfo_Value(partner,"D_VOL",lin) end
  local linked=stereo_link_partner(tr)
  if linked then reaper.SetMediaTrackInfo_Value(linked,"D_VOL",lin) end
end
local function set_track_mute(tr,on)
  local v=on and 1 or 0
  reaper.SetMediaTrackInfo_Value(tr,"B_MUTE",v)
  local partners={fx_partner(tr),stereo_link_partner(tr)}
  local seen={}
  for _,partner in pairs(partners) do
    if partner and not seen[partner] then seen[partner]=true; reaper.SetMediaTrackInfo_Value(partner,"B_MUTE",v) end
  end
end
local function set_track_solo(tr,on)
  if not tr then return end
  set_ext(tr,"LIVE32_SOLO",on and "1" or "0")
  -- Live32 SOLO is a monitor-bus/PFL-AFL function, never a REAPER solo-in-place.
  reaper.SetMediaTrackInfo_Value(tr,"I_SOLO",0)
  local partners={fx_partner(tr),stereo_link_partner(tr)}
  local seen={}
  for _,partner in pairs(partners) do
    if partner and not seen[partner] then
      seen[partner]=true
      set_ext(partner,"LIVE32_SOLO",on and "1" or "0")
      reaper.SetMediaTrackInfo_Value(partner,"I_SOLO",0)
    end
  end
  if on and monitor_get_bool and monitor_get_bool("LIVE32_MON_SELECT_FOLLOWS",false) and select_live32_track then select_live32_track(tr) end
  if update_monitor_solo_routing then update_monitor_solo_routing() end
end

-- v1.2 monitor / solo architecture -------------------------------------------------
-- Live32 never uses REAPER's native solo-in-place for normal operation. SOLO keys
-- feed this dedicated MONITOR track, allowing FOH MAIN LR to continue untouched.
function monitor_get(key,default)
  if not monitor then return tostring(default or "") end
  local v=get_ext(monitor,key)
  if v=="" then return tostring(default or "") end
  return v
end
function monitor_set(key,value) if monitor then set_ext(monitor,key,tostring(value)) end end
function monitor_get_bool(key,default)
  local v=monitor_get(key,default and "1" or "0")
  return v=="1"
end
function monitor_solo_on(tr) return tr and get_ext(tr,"LIVE32_SOLO")=="1" or false end
function select_live32_track(tr)
  if not tr then return end
  local role=track_role(tr)
  local n=tonumber(role:match("^CH(%d+)$") or "")
  if n then selected_kind="CH"; selected=n; source_layer=math.floor((n-1)/8)+1; meter_focus="source"; sof_focus="source"; return end
  n=tonumber(role:match("^FXRTN(%d+)$") or "")
  if n then selected_kind="FX"; selected=n; source_layer=5; meter_focus="source"; sof_focus="source"; return end
  n=tonumber(role:match("^BUS(%d+)$") or "")
  if n then selected_bus=n; bus_fader_layer=n<=8 and 1 or 2; meter_focus="bus"; sof_focus="bus"; return end
  n=tonumber(role:match("^MATRIX(%d+)$") or "")
  if n then selected_matrix=n; bus_fader_layer=3; meter_focus="matrix"; return end
end
function monitor_send_index(src)
  if not src or not monitor then return -1 end
  for si=0,reaper.GetTrackNumSends(src,0)-1 do
    if reaper.GetTrackSendInfo_Value(src,0,si,"P_DESTTRACK")==monitor then return si end
  end
  return -1
end
function monitor_active_dca_for_track(tr)
  for d=1,8 do if dca_solo_active(d) and dca_member(tr,d) then return true,d end end
  return false,nil
end
function monitor_source_afl(tr,via_dca)
  if via_dca then return monitor_get_bool("LIVE32_MON_DCA_AFL",true) end
  local role=track_role(tr)
  if role:match("^BUS%d+$") or role:match("^MATRIX%d+$") then
    return monitor_get_bool("LIVE32_MON_BUS_AFL",true)
  end
  return monitor_get_bool("LIVE32_MON_CH_AFL",false)
end
function monitor_pfl_pan(tr)
  if not tr then return 0 end
  if fx_partner(tr) or stereo_link_partner(tr) then return clamp(reaper.GetMediaTrackInfo_Value(tr,"D_PAN") or 0,-1,1) end
  return 0
end
function monitor_solo_summary()
  local count=0; local label="NO SOLO"; local any_afl=false; local any_pfl=false
  local function test(tr,lab)
    if not tr then return end
    local manual=monitor_solo_on(tr)
    local via=monitor_active_dca_for_track(tr)
    if manual or via then
      count=count+1; if count==1 then label=lab end
      if monitor_source_afl(tr,(not manual) and via) then any_afl=true else any_pfl=true end
    end
  end
  for i=1,32 do test(channels[i],string.format("CH %02d",i)) end
  for i=1,8 do test(fxreturns[i],string.format("FX %02d",i)) end
  for i=1,16 do test(buses[i],string.format("BUS %02d",i)) end
  for i=1,8 do test(matrices[i],string.format("MTX %02d",i)) end
  if count>1 then label=tostring(count).." SOLO SOURCES" end
  local mode=any_afl and any_pfl and "SOLO" or (any_afl and "AFL" or (any_pfl and "PFL" or "PFL"))
  return count,label,mode
end
function update_monitor_solo_routing()
  if not monitor then return end
  -- Clear any legacy REAPER solo-in-place states so the FOH path is never interrupted.
  local all={}
  for i=1,32 do all[#all+1]=channels[i] end
  for i=1,8 do all[#all+1]=fxreturns[i] end
  for i=1,16 do all[#all+1]=buses[i] end
  for i=1,8 do all[#all+1]=matrices[i] end
  for _,tr in ipairs(all) do if tr then reaper.SetMediaTrackInfo_Value(tr,"I_SOLO",0) end end
  for i=1,8 do if dcas[i] then reaper.SetMediaTrackInfo_Value(dcas[i],"I_SOLO",0) end end

  local solo_count=select(1,monitor_solo_summary())
  local source=monitor_get("LIVE32_MON_SOURCE","MAIN")
  local mainidx=monitor_send_index(master)
  if mainidx>=0 then
    reaper.SetTrackSendInfo_Value(master,0,mainidx,"B_MUTE",(solo_count>0 or source=="OFF") and 1 or 0)
    reaper.SetTrackSendInfo_Value(master,0,mainidx,"I_SENDMODE",monitor_get_bool("LIVE32_MON_MASTER_FADER",false) and 0 or 3)
    reaper.SetTrackSendInfo_Value(master,0,mainidx,"D_VOL",1.0)
    reaper.SetTrackSendInfo_Value(master,0,mainidx,"D_PAN",0.0)
  end
  local dimdb=tonumber(monitor_get("LIVE32_MON_DIM_DB","-20")) or -20
  local dimlin=db2lin(dimdb)
  local use_dim=monitor_get_bool("LIVE32_MON_DIM_PFL",false)
  for _,tr in ipairs(all) do
    if tr then
      local si=monitor_send_index(tr)
      if si>=0 then
        local manual=monitor_solo_on(tr)
        local via_dca=monitor_active_dca_for_track(tr)
        local active=manual or via_dca
        local afl=monitor_source_afl(tr,(not manual) and via_dca)
        reaper.SetTrackSendInfo_Value(tr,0,si,"B_MUTE",active and 0 or 1)
        reaper.SetTrackSendInfo_Value(tr,0,si,"I_SENDMODE",afl and 0 or 3)
        reaper.SetTrackSendInfo_Value(tr,0,si,"I_SRCCHAN",0)
        reaper.SetTrackSendInfo_Value(tr,0,si,"D_VOL",(active and (not afl) and use_dim) and dimlin or 1.0)
        reaper.SetTrackSendInfo_Value(tr,0,si,"D_PAN",afl and 0 or monitor_pfl_pan(tr))
      end
    end
  end
  local leveldb=tonumber(monitor_get("LIVE32_MON_LEVEL_DB","0")) or 0
  reaper.SetMediaTrackInfo_Value(monitor,"D_VOL",db2lin(leveldb))
  reaper.SetMediaTrackInfo_Value(monitor,"B_MUTE",0)
end

-- MAIN BUS controls. REAPER's D_PAN maps naturally to the M32 PAN/BAL encoder
-- for mono input channels and mix buses, while B_MAINSEND is the equivalent of
-- assigning/de-assigning that channel or bus to Main L/R. Linked FX returns keep
-- their hard L/R pan positions, so the PAN/BAL encoder is display-only for them.
local function track_pan(tr)
  return reaper.GetMediaTrackInfo_Value(tr,"D_PAN") or 0
end

local function set_track_pan(tr,v)
  v=clamp(v,-1,1)
  if fx_partner(tr) or stereo_link_partner(tr) then return end -- preserve linked stereo pairs
  reaper.SetMediaTrackInfo_Value(tr,"D_PAN",v)
end

function main_send_index(tr)
  if not tr or tr==master then return -1 end
  for sidx=0,reaper.GetTrackNumSends(tr,0)-1 do
    if reaper.GetTrackSendInfo_Value(tr,0,sidx,"P_DESTTRACK")==master then return sidx end
  end
  return -1
end
function main_send_on(tr)
  if tr==master then return true end
  local sidx=main_send_index(tr)
  return sidx>=0 and (reaper.GetTrackSendInfo_Value(tr,0,sidx,"D_VOL") or 0)>0.000001
end
function set_main_send_one(tr,on)
  if not tr or tr==master then return end
  local sidx=main_send_index(tr)
  if sidx<0 then sidx=reaper.CreateTrackSend(tr,master) end
  if sidx>=0 then
    reaper.SetTrackSendInfo_Value(tr,0,sidx,"D_VOL",on and 1.0 or 0.0)
    reaper.SetTrackSendInfo_Value(tr,0,sidx,"I_SENDMODE",0)
    reaper.SetTrackSendInfo_Value(tr,0,sidx,"I_MIDIFLAGS",31)
  end
end
function set_main_send(tr,on)
  set_main_send_one(tr,on)
  local partners={fx_partner(tr),stereo_link_partner(tr)}
  local seen={}
  for _,partner in pairs(partners) do
    if partner and not seen[partner] then seen[partner]=true; set_main_send_one(partner,on) end
  end
end

local function fmt_pan(v)
  if math.abs(v)<0.015 then return "C" end
  local pct=math.floor(math.abs(v)*100+0.5)
  return (v<0 and "L" or "R")..tostring(pct)
end
local function send_db(tr,busn)
  local s=send_index(tr,busn or selected_bus)
  if s<0 then return -150 end
  return lin2db(reaper.GetTrackSendInfo_Value(tr,0,s,"D_VOL"))
end
-- Bus preconfiguration. REAPER exposes pre-FX, post-FX/pre-fader and post-fader
-- taps natively. Live32 also publishes PRE-EQ and POST-EQ audio on hidden
-- channel pairs 5/6 and 7/8 from the custom channel-strip JSFX.
BUS_TAP_MODES={
  PRE_EQ={label="PRE EQ",short="PRE EQ",sendmode=3,srcchan=4},
  POST_EQ={label="POST EQ",short="POST EQ",sendmode=3,srcchan=6},
  PRE_FADER={label="PRE FADER",short="PRE FDR",sendmode=3,srcchan=0},
  POST_FADER={label="POST FADER",short="POST FDR",sendmode=0,srcchan=0},
  SUBGROUP={label="SUB GROUP",short="GROUP",sendmode=0,srcchan=0,subgroup=true}
}
function bus_tap_mode(busn)
  local b=buses[busn]
  if not b then return "PRE_FADER" end
  local id=get_ext(b,"LIVE32_BUS_TAP")
  if BUS_TAP_MODES[id] then return id end
  return busn>=13 and "POST_FADER" or "PRE_FADER"
end
function bus_tap_label(busn,short)
  local m=BUS_TAP_MODES[bus_tap_mode(busn)] or BUS_TAP_MODES.PRE_FADER
  return short and m.short or m.label
end
function bus_is_subgroup(busn) return bus_tap_mode(busn)=="SUBGROUP" end

function apply_bus_tap_to_send(src,busn)
  local si=send_index(src,busn)
  if si<0 then return end
  local m=BUS_TAP_MODES[bus_tap_mode(busn)]
  reaper.SetMediaTrackInfo_Value(src,"I_NCHAN",math.max(8,reaper.GetMediaTrackInfo_Value(src,"I_NCHAN") or 2))
  reaper.SetTrackSendInfo_Value(src,0,si,"I_SENDMODE",m.sendmode)
  reaper.SetTrackSendInfo_Value(src,0,si,"I_SRCCHAN",m.srcchan)
  reaper.SetTrackSendInfo_Value(src,0,si,"I_MIDIFLAGS",31)
  if m.subgroup then
    local vol=reaper.GetTrackSendInfo_Value(src,0,si,"D_VOL") or 0
    reaper.SetTrackSendInfo_Value(src,0,si,"D_VOL",vol>0.000001 and 1.0 or 0.0)
  end
end
function set_bus_tap_mode(busn,id)
  if not buses[busn] or not BUS_TAP_MODES[id] then return end
  local previous=bus_tap_mode(busn)
  set_ext(buses[busn],"LIVE32_BUS_TAP",id)
  for i=1,32 do if channels[i] then apply_bus_tap_to_send(channels[i],busn) end end
  for i=1,8 do if fxreturns[i] then apply_bus_tap_to_send(fxreturns[i],busn) end end
  if id=="SUBGROUP" and previous~="SUBGROUP" then
    for i=1,32 do
      local tr=channels[i]
      if tr then local si=send_index(tr,busn); if si>=0 then reaper.SetTrackSendInfo_Value(tr,0,si,"D_VOL",0.0) end end
    end
    for i=1,8 do
      local tr=fxreturns[i]
      if tr then local si=send_index(tr,busn); if si>=0 then reaper.SetTrackSendInfo_Value(tr,0,si,"D_VOL",0.0) end end
    end
  end
end
function apply_all_bus_tap_modes()
  for b=1,16 do
    for i=1,32 do if channels[i] then apply_bus_tap_to_send(channels[i],b) end end
    for i=1,8 do if fxreturns[i] then apply_bus_tap_to_send(fxreturns[i],b) end end
  end
end
-- Compatibility helpers retained for older UI paths. PRE now means PRE FADER.
function send_is_pre(tr,busn) return bus_tap_mode(busn or selected_bus)~="POST_FADER" and bus_tap_mode(busn or selected_bus)~="SUBGROUP" end
function set_send_pre(tr,busn,on) set_bus_tap_mode(busn,on and "PRE_FADER" or "POST_FADER") end

-- Stereo-link send behaviour: linked source pairs share send level but retain a
-- true L/R image. Odd source sends are hard-left and even source sends hard-right.
-- If the destination bus itself is linked, changing either member addresses the
-- whole stereo bus pair, which makes the two mono bus masters behave as L/R sides.
local function set_send_one(tr,busn,db,pan)
  local dest=buses[busn]
  if not tr or not dest then return end

  -- A repaired/attached project may be missing an individual source->bus send.
  -- Create it on demand rather than failing when the console first touches it.
  local s=send_index(tr,busn)
  if s<0 then
    s=reaper.CreateTrackSend(tr,dest)
    if not s or s<0 then return end
  end

  reaper.SetTrackSendInfo_Value(tr,0,s,"D_VOL",db<=-90 and 0.0 or db2lin(db))
  if pan~=nil then
    reaper.SetTrackSendInfo_Value(tr,0,s,"D_PAN",clamp(pan,-1,1))
  end
  reaper.SetTrackSendInfo_Value(tr,0,s,"I_MIDIFLAGS",31)

  -- Keep the send's PRE EQ / POST EQ / PRE FADER / POST FADER / SUBGROUP
  -- tap point consistent with the destination bus configuration.
  apply_bus_tap_to_send(tr,busn)
end

local function set_send_db(tr,busn,db)
  busn=busn or selected_bus
  local dest=buses[busn]
  if not dest then return end
  -- A subgroup has no variable aux-send level on the M32. Its membership is
  -- effectively post-fader at unity, so Live32 treats the send as ON/OFF.
  if bus_is_subgroup(busn) then db=(db<=-60) and -150 or 0 end

  local target_buses={busn}
  if stereo_link_on(dest) then
    local _,_,_,odd,even=stereo_link_pair(dest)
    if odd and even then target_buses={odd,even} end
  end

  local a,b=active_source_stereo_pair(tr)
  if a and b then
    for _,bn in ipairs(target_buses) do
      set_send_one(a,bn,db,-1.0)
      set_send_one(b,bn,db, 1.0)
    end
  else
    -- A mono source feeding a linked stereo bus is duplicated to both halves;
    -- its source pan supplies the stereo position until a dedicated send-pan UI exists.
    local sp=track_pan(tr)
    for _,bn in ipairs(target_buses) do set_send_one(tr,bn,db,sp) end
  end
end

function subgroup_member(tr,busn)
  if not tr or not bus_is_subgroup(busn) then return false end
  local si=send_index(tr,busn)
  if si<0 then return false end
  return (reaper.GetTrackSendInfo_Value(tr,0,si,"D_VOL") or 0)>0.000001
end

function set_subgroup_member(tr,busn,on)
  if not tr or not bus_is_subgroup(busn) then return end
  set_send_db(tr,busn,on and 0 or -150)
end

local function matrix_send_db(tr,matrixn)
  local s=matrix_send_index(tr,matrixn or selected_matrix)
  if s<0 then return -150 end
  return lin2db(reaper.GetTrackSendInfo_Value(tr,0,s,"D_VOL"))
end

local function set_matrix_send_one(tr,matrixn,db,pan)
  local s=matrix_send_index(tr,matrixn)
  if s<0 then return end
  reaper.SetTrackSendInfo_Value(tr,0,s,"D_VOL",db<=-90 and 0.0 or db2lin(db))
  if pan~=nil then reaper.SetTrackSendInfo_Value(tr,0,s,"D_PAN",clamp(pan,-1,1)) end
end

local function set_matrix_send_db(tr,matrixn,db)
  matrixn=matrixn or selected_matrix
  local a,b=stereo_link_pair(tr)
  if a and b and stereo_link_on(tr) then
    set_matrix_send_one(a,matrixn,db,-1.0)
    set_matrix_send_one(b,matrixn,db, 1.0)
  else
    set_matrix_send_one(tr,matrixn,db,track_pan(tr))
  end
end

function scene_safe(tr) return tr and get_ext(tr,"LIVE32_SCENE_SAFE")=="1" end
function set_scene_safe(tr,on) if tr then set_ext(tr,"LIVE32_SCENE_SAFE",on and "1" or "") end end

-- Compressor key source. SELF uses the channel's own post-EQ detector signal.
-- External keying uses a pre-FX send from one of Live32 CH 01-32 to channels 3/4.
local function key_ext_get(tr)
  return get_ext(tr,"LIVE32_KEY_SOURCE")
end
local function key_ext_set(tr,v)
  set_ext(tr,"LIVE32_KEY_SOURCE",v or "0")
end
local function key_source_index(tr)
  return clamp(tonumber(key_ext_get(tr)) or 0,0,32)
end
local function remove_key_sends_to(dest)
  if not dest then return end
  for i=1,32 do
    local src=channels[i]
    if src then
      for si=reaper.GetTrackNumSends(src,0)-1,0,-1 do
        local d=reaper.GetTrackSendInfo_Value(src,0,si,"P_DESTTRACK")
        local dc=math.floor(reaper.GetTrackSendInfo_Value(src,0,si,"I_DSTCHAN") or -1)
        local sm=math.floor(reaper.GetTrackSendInfo_Value(src,0,si,"I_SENDMODE") or -1)
        if d==dest and dc==2 and sm==1 then reaper.RemoveTrackSend(src,0,si) end
      end
    end
  end
end
local function set_key_source_one(dest,idx)
  if not dest then return false end
  remove_key_sends_to(dest)
  idx=clamp(math.floor(idx or 0),0,32)
  if idx==0 or channels[idx]==dest then
    key_ext_set(dest,"0");
    local fx=fxidx(dest); if fx>=0 then reaper.TrackFX_SetParam(dest,fx,36,0) end
    return true
  end
  local src=channels[idx]
  if not src then return false end
  reaper.SetMediaTrackInfo_Value(dest,"I_NCHAN",math.max(4,reaper.GetMediaTrackInfo_Value(dest,"I_NCHAN") or 2))
  local si=reaper.CreateTrackSend(src,dest)
  if si<0 then return false end
  reaper.SetTrackSendInfo_Value(src,0,si,"D_VOL",1.0)
  reaper.SetTrackSendInfo_Value(src,0,si,"D_PAN",0.0)
  reaper.SetTrackSendInfo_Value(src,0,si,"I_SENDMODE",1)
  reaper.SetTrackSendInfo_Value(src,0,si,"I_SRCCHAN",0)
  reaper.SetTrackSendInfo_Value(src,0,si,"I_DSTCHAN",2)
  reaper.SetTrackSendInfo_Value(src,0,si,"I_MIDIFLAGS",31)
  key_ext_set(dest,tostring(idx))
  local fx=fxidx(dest); if fx>=0 then reaper.TrackFX_SetParam(dest,fx,36,1) end
  return true
end
local function set_key_source(tr,idx)
  -- REAPER's master routing is deliberately left SELF-only; ordinary Live32
  -- channels, buses and matrices can be externally keyed from input channels.
  if is_master_track(tr) then set_key_source_one(tr,0); return false end
  local targets={tr}
  local fp=fx_partner(tr); local sp=stereo_link_partner(tr)
  if fp then targets[#targets+1]=fp end
  if sp and sp~=fp then targets[#targets+1]=sp end
  -- Choosing either member of the currently linked input pair means SELF for the
  -- pair, rather than creating an asymmetric sidechain on only one side.
  if idx and idx>0 then
    for _,d in ipairs(targets) do if channels[idx]==d then idx=0 break end end
  end
  local ok=true
  for _,d in ipairs(targets) do if not set_key_source_one(d,idx) then ok=false end end
  return ok
end
local function key_source_label(tr)
  local i=key_source_index(tr)
  return i==0 and "SELF" or string.format("CH %02d",i)
end

-- Copy the odd member's complete Live32 state to the even member when a stereo
-- link is created (and when an older linked project is first opened in v0.9.3).
-- Dedicated FX algorithms on buses 13-16 are intentionally not cloned; the linked
-- bus processing surface, routing, fader and assignment state are cloned.
sync_stereo_link_from_left=function(tr)
  local a,b,kind=stereo_link_pair(tr)
  if not a or not b or not stereo_link_on(tr) then return end

  local afx=fxidx(a); local bfx=fxidx(b)
  if afx>=0 and bfx>=0 then
    local n=math.min(reaper.TrackFX_GetNumParams(a,afx),reaper.TrackFX_GetNumParams(b,bfx))
    for p=0,n-1 do
      local v=select(1,reaper.TrackFX_GetParam(a,afx,p))
      if v~=nil then reaper.TrackFX_SetParam(b,bfx,p,v) end
    end
  end
  -- Insert assignment and every insert parameter are part of a stereo link too.
  sync_insert_from_left(a,b)

  for _,parm in ipairs({"D_VOL","B_MUTE"}) do
    reaper.SetMediaTrackInfo_Value(b,parm,reaper.GetMediaTrackInfo_Value(a,parm))
  end
  set_ext(b,"LIVE32_SOLO",monitor_solo_on(a) and "1" or "")
  reaper.SetMediaTrackInfo_Value(b,"I_SOLO",0)
  set_main_send_one(b,main_send_on(a))
  reaper.SetMediaTrackInfo_Value(a,"D_PAN",-1.0)
  reaper.SetMediaTrackInfo_Value(b,"D_PAN", 1.0)

  if kind=="CH" then
    for bn=1,16 do
      set_send_db(a,bn,send_db(a,bn))
    end
  elseif kind=="BUS" then
    local _,_,_,odd_bus,even_bus=stereo_link_pair(a)
    if odd_bus and even_bus then set_bus_tap_mode(even_bus,bus_tap_mode(odd_bus)) end
    -- Linking a bus pair also makes all existing channel/FX sends address it as a
    -- stereo destination. The odd bus's send level is the initial master value.
    if odd_bus then
      for i=1,32 do
        local src=channels[i]
        if src then set_send_db(src,odd_bus,send_db(src,odd_bus)) end
      end
      for i=1,8 do
        local src=fxreturns[i]
        if src then set_send_db(src,odd_bus,send_db(src,odd_bus)) end
      end
    end
    for mn=1,8 do set_matrix_send_db(a,mn,matrix_send_db(a,mn)) end
  end
  -- DCA / mute-group membership and compressor key source are part of the stereo-linked state.
  for d=1,8 do set_dca_member_one(b,d,dca_member(a,d)) end
  for g=1,6 do set_mute_group_member_one(b,g,mute_group_member(a,g)) end
  set_key_source_one(b,key_source_index(a))
end

local function sync_existing_stereo_links()
  for odd=1,31,2 do
    local tr=channels[odd]
    if tr and stereo_link_on(tr) then sync_stereo_link_from_left(tr) end
  end
  for odd=1,15,2 do
    local tr=buses[odd]
    if tr and stereo_link_on(tr) then sync_stereo_link_from_left(tr) end
  end
end

local function enforce_all_stereo_link_pans()
  for odd=1,31,2 do
    local tr=channels[odd]
    if tr and stereo_link_on(tr) then enforce_stereo_link_pan(tr) end
  end
  for odd=1,15,2 do
    local tr=buses[odd]
    if tr and stereo_link_on(tr) then enforce_stereo_link_pan(tr) end
  end
end

-- Scene/snapshot system. Eight project-persistent scenes capture the Live32 mix
-- without touching media items or the REAPER arrange view. Recall Safe skips the
-- selected source/output (and its stereo partner) during recalls.
scene_status=""
scene_status_time=0
function pct_escape(v)
  return tostring(v or ""):gsub("([^%w%-%._])",function(c)return string.format("%%%02X",string.byte(c)) end)
end
function pct_unescape(v)
  return (v or ""):gsub("%%(%x%x)",function(h)return string.char(tonumber(h,16)) end)
end
function split_plain(str,sep)
  local out={}; str=str or ""; local start=1
  while true do
    local a,b=string.find(str,sep,start,true)
    if not a then out[#out+1]=string.sub(str,start); break end
    out[#out+1]=string.sub(str,start,a-1); start=b+1
  end
  return out
end
function scene_section(slot) return "Live32Scene"..tostring(slot) end
function scene_exists(slot)
  local ok,v=reaper.GetProjExtState(0,scene_section(slot),"META")
  return ok>0 and v~=""
end
function scene_track_list()
  local out={}
  for i=1,32 do out[#out+1]=channels[i] end
  for i=1,8 do out[#out+1]=fxreturns[i] end
  for i=1,16 do out[#out+1]=buses[i] end
  for i=1,8 do out[#out+1]=matrices[i] end
  out[#out+1]=master
  for i=1,8 do out[#out+1]=dcas[i] end
  for i=1,6 do out[#out+1]=mutegroups[i] end
  return out
end
function role_lookup()
  local m={}
  for _,tr in ipairs(scene_track_list()) do if tr then m[track_role(tr)]=tr end end
  return m
end
function channel_fx_for_scene(tr)
  local fx=find_fx_named(tr,"live32 channel strip")
  if fx<0 then fx=find_fx_named(tr,"live32_channel") end
  return fx
end
function serialize_live32_sends(tr)
  local vals={}
  for si=0,reaper.GetTrackNumSends(tr,0)-1 do
    local dest=reaper.GetTrackSendInfo_Value(tr,0,si,"P_DESTTRACK")
    local role=dest and track_role(dest) or ""
    local dstchan=math.floor(reaper.GetTrackSendInfo_Value(tr,0,si,"I_DSTCHAN") or 0)
    if role~="" and role~="MONITOR" and dstchan==0 then
      vals[#vals+1]=table.concat({role,
        string.format("%.12g",reaper.GetTrackSendInfo_Value(tr,0,si,"D_VOL") or 0),
        string.format("%.8g",reaper.GetTrackSendInfo_Value(tr,0,si,"D_PAN") or 0),
        tostring(math.floor(reaper.GetTrackSendInfo_Value(tr,0,si,"I_SENDMODE") or 0))},":")
    end
  end
  return table.concat(vals,";")
end
function serialize_insert_params(tr)
  local key=insert_type(tr); if key=="none" then return "", "1" end
  local fx=insert_fxidx(tr,key); if fx<0 then return "", "1" end
  local pp={}
  for pi=0,reaper.TrackFX_GetNumParams(tr,fx)-1 do
    pp[#pp+1]=string.format("%.12g",reaper.TrackFX_GetParamNormalized(tr,fx,pi) or 0)
  end
  return table.concat(pp,","), reaper.TrackFX_GetEnabled(tr,fx) and "1" or "0"
end
function scene_serialize_track(tr)
  local fx=channel_fx_for_scene(tr); local params={}
  if fx>=0 then
    for pi=0,reaper.TrackFX_GetNumParams(tr,fx)-1 do
      params[#params+1]=string.format("%.12g",select(1,reaper.TrackFX_GetParam(tr,fx,pi)) or 0)
    end
  end
  local dca_bits={}; for d=1,8 do dca_bits[d]=dca_member(tr,d) and "1" or "0" end
  local mg_bits={}; for g=1,6 do mg_bits[g]=mute_group_member(tr,g) and "1" or "0" end
  local linked=stereo_link_pair(tr) and stereo_link_on(tr) and "1" or "0"
  local insparams, insenabled=serialize_insert_params(tr)
  return table.concat({
    string.format("%.12g",reaper.GetMediaTrackInfo_Value(tr,"D_VOL") or 1),
    string.format("%.8g",reaper.GetMediaTrackInfo_Value(tr,"D_PAN") or 0),
    tostring(math.floor(reaper.GetMediaTrackInfo_Value(tr,"B_MUTE") or 0)),
    monitor_solo_on(tr) and "1" or "0",
    pct_escape(custom_label(tr)), scribble_key(tr), linked, tostring(key_source_index(tr)),
    table.concat(params,","), table.concat(dca_bits,""), table.concat(mg_bits,""),
    serialize_live32_sends(tr),
    (track_role(tr):match("^BUS%d+$") and bus_tap_mode(tonumber(track_role(tr):match("^BUS(%d+)$"))) or ""),
    insert_type(tr), insparams, insenabled
  },"|")
end
function scene_save(slot)
  local sec=scene_section(slot)
  reaper.SetProjExtState(0,sec,"META",os.date("%Y-%m-%d %H:%M:%S"))
  for _,tr in ipairs(scene_track_list()) do
    if tr then reaper.SetProjExtState(0,sec,track_role(tr),scene_serialize_track(tr)) end
  end
  scene_status="SCENE "..slot.." SAVED"; scene_status_time=reaper.time_precise()
end
function scene_find_send(src,dest)
  for si=0,reaper.GetTrackNumSends(src,0)-1 do
    if reaper.GetTrackSendInfo_Value(src,0,si,"P_DESTTRACK")==dest and math.floor(reaper.GetTrackSendInfo_Value(src,0,si,"I_DSTCHAN") or 0)==0 then return si end
  end
  return -1
end
function scene_skip_track(tr)
  if scene_safe(tr) then return true end
  local partner=fx_partner(tr) or stereo_link_partner(tr)
  return partner and scene_safe(partner) or false
end
function scene_restore_track(tr,data,lookup)
  if not tr or not data or data=="" or scene_skip_track(tr) then return end
  local f=split_plain(data,"|")
  reaper.SetMediaTrackInfo_Value(tr,"D_VOL",tonumber(f[1]) or 1)
  reaper.SetMediaTrackInfo_Value(tr,"D_PAN",tonumber(f[2]) or 0)
  reaper.SetMediaTrackInfo_Value(tr,"B_MUTE",tonumber(f[3]) or 0)
  set_ext(tr,"LIVE32_SOLO",f[4]=="1" and "1" or ""); reaper.SetMediaTrackInfo_Value(tr,"I_SOLO",0)
  set_custom_label(tr,pct_unescape(f[5] or "")); set_scribble_key(tr,f[6] or "")
  local a,b=stereo_link_pair(tr)
  if a and b then set_ext(tr,"LIVE32_STEREO_LINK",f[7]=="1" and "1" or "") end
  local fx=channel_fx_for_scene(tr)
  if fx>=0 and f[9] and f[9]~="" then
    local pp=split_plain(f[9],",")
    local n=math.min(#pp,reaper.TrackFX_GetNumParams(tr,fx))
    for pi=1,n do reaper.TrackFX_SetParam(tr,fx,pi-1,tonumber(pp[pi]) or 0) end
  end
  if f[10] then for d=1,8 do set_dca_member_one(tr,d,f[10]:sub(d,d)=="1") end end
  if f[11] then for g=1,6 do set_mute_group_member_one(tr,g,f[11]:sub(g,g)=="1") end end
  if f[12] and f[12]~="" then
    for _,entry in ipairs(split_plain(f[12],";")) do
      local q=split_plain(entry,":"); local dest=lookup[q[1] or ""]
      if dest then
        local si=scene_find_send(tr,dest); if si<0 then si=reaper.CreateTrackSend(tr,dest) end
        if si>=0 then
          reaper.SetTrackSendInfo_Value(tr,0,si,"D_VOL",tonumber(q[2]) or 0)
          reaper.SetTrackSendInfo_Value(tr,0,si,"D_PAN",tonumber(q[3]) or 0)
          reaper.SetTrackSendInfo_Value(tr,0,si,"I_SENDMODE",tonumber(q[4]) or 0)
          reaper.SetTrackSendInfo_Value(tr,0,si,"I_MIDIFLAGS",31)
        end
      end
    end
  end
  if f[13] and f[13]~="" then
    local bn=tonumber(track_role(tr):match("^BUS(%d+)$") or "")
    if bn and BUS_TAP_MODES[f[13]] then set_ext(tr,"LIVE32_BUS_TAP",f[13]) end
  end
  local ikey=f[14] or "none"
  if ikey=="" then ikey="none" end
  if ikey=="none" or INSERT_DEFS[ikey] then
    set_insert_type(tr,ikey)
    local ifx=insert_fxidx(tr,ikey)
    if ifx>=0 and f[15] and f[15]~="" then
      local ip=split_plain(f[15],",")
      local nn=math.min(#ip,reaper.TrackFX_GetNumParams(tr,ifx))
      for pi=1,nn do reaper.TrackFX_SetParamNormalized(tr,ifx,pi-1,tonumber(ip[pi]) or 0) end
      reaper.TrackFX_SetEnabled(tr,ifx,(f[16] or "1")=="1")
    end
  end
  if fx>=0 then set_key_source(tr,tonumber(f[8]) or 0) end
end
function scene_recall(slot)
  if not scene_exists(slot) then scene_status="SCENE "..slot.." IS EMPTY"; scene_status_time=reaper.time_precise(); return end
  local sec=scene_section(slot); local lookup=role_lookup()
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  for role,tr in pairs(lookup) do
    local ok,data=reaper.GetProjExtState(0,sec,role)
    if ok>0 then scene_restore_track(tr,data,lookup) end
  end
  apply_all_bus_tap_modes(); sync_existing_stereo_links(); enforce_fx_return_pans(); enforce_all_stereo_link_pans(); update_monitor_solo_routing()
  reaper.PreventUIRefresh(-1); reaper.UpdateArrange(); reaper.Undo_EndBlock("Recall Live32 Scene "..slot,-1)
  scene_status="SCENE "..slot.." RECALLED"; scene_status_time=reaper.time_precise()
end

local function button(x,y,w,h,label,on,oncolor,offcolor)
  rect(x,y,w,h,on and (oncolor or C.orange) or (offcolor or C.panel2),true)
  rect(x,y,w,h,on and C.orange or C.edge,false)
  centered(x,y+math.floor((h-15)/2)-1,w,label,13,on and C.black or C.text)
  return inside(gfx.mouse_x,gfx.mouse_y,x,y,w,h)
end

local function round_button(cx,cy,r,label,on,oncolor)
  local fill=on and (oncolor or C.blue) or C.panel2
  circle(cx,cy,r+2,C.black,true)
  circle(cx,cy,r+2,on and (oncolor or C.blue) or C.edge,false)
  circle(cx,cy,r,fill,true)
  circle(cx,cy,r,on and C.white or C.edge2,false)
  gfx.setfont(1,"Arial",9)
  local tw,th=gfx.measurestr(label)
  text(cx-tw/2,cy-th/2-1,label,9,on and C.black or C.text)
  local dx=gfx.mouse_x-cx; local dy=gfx.mouse_y-cy
  return dx*dx+dy*dy <= (r+3)*(r+3)
end

local function value_to_norm(v,minv,maxv,islog)
  if islog then
    minv=math.max(minv,0.000001)
    v=math.max(v,minv)
    return clamp(math.log(v/minv)/math.log(maxv/minv),0,1)
  end
  return clamp((v-minv)/(maxv-minv),0,1)
end
local function norm_to_value(n,minv,maxv,islog)
  n=clamp(n,0,1)
  if islog then return minv*((maxv/minv)^n) end
  return minv+n*(maxv-minv)
end

local function draw_arc(cx,cy,r,a1,a2,c,width,segments)
  segments=segments or 36
  local px,py=nil,nil
  for i=0,segments do
    local a=a1+(a2-a1)*(i/segments)
    local x=cx+math.cos(a)*r
    local y=cy+math.sin(a)*r
    if px then line(px,py,x,y,c,width or 1) end
    px,py=x,y
  end
end

-- M32-style segmented LED encoder ring. Each short radial bar is either
-- illuminated or dark rather than drawing one continuous arc.
local function draw_encoder_leds(cx,cy,r,n,active_color,segments)
  segments=segments or 12
  active_color=active_color or C.amber
  n=clamp(n or 0,0,1)
  local a1=math.rad(135)
  local a2=math.rad(405)
  local lit=math.floor(n*(segments-1)+0.5)
  for i=0,segments-1 do
    local a=a1+(a2-a1)*(i/(segments-1))
    local ri=r+5
    local ro=r+12
    local c=(i<=lit) and active_color or {0.20,0.21,0.21}
    line(cx+math.cos(a)*ri,cy+math.sin(a)*ri,
         cx+math.cos(a)*ro,cy+math.sin(a)*ro,c,(i<=lit) and 3 or 2)
  end
end

local function knob(id,cx,cy,r,label,val,minv,maxv,fmt,param,tr,opts)
  opts=opts or {}
  local islog=opts.log or false
  local default=opts.default
  local sensitivity=opts.sensitivity or 170
  local n=value_to_norm(val,minv,maxv,islog)
  local a1=math.rad(135)
  local a2=math.rad(405)

  -- segmented amber encoder LEDs, like the physical M32 encoders
  draw_encoder_leds(cx,cy,r,n,C.amber,12)

  -- silver/black M32-style knob body
  circle(cx,cy,r,{0.76,0.77,0.79},true)
  circle(cx,cy,r,C.white,false)
  circle(cx,cy,r-3,{0.18,0.19,0.20},true)
  circle(cx,cy,r-4,{0.47,0.48,0.50},false)
  circle(cx,cy,r-8,{0.05,0.05,0.06},true)
  circle(cx,cy,r-9,{0.23,0.23,0.24},false)
  circle(cx,cy,r-14,{0.62,0.63,0.65},true)
  circle(cx,cy,r-15,{0.88,0.88,0.89},false)

  local pa=a1+(a2-a1)*n
  line(cx,cy,cx+math.cos(pa)*(r-14),cy+math.sin(pa)*(r-14),C.white,2)

  if not opts.hide_label then
    centered(cx-r-32,cy+r+13,(r+32)*2,label,opts.labelsize or 13,C.text)
  end
  if not opts.hide_value then
    centered(cx-r-42,cy+r+31,(r+42)*2,fmt(val),opts.valuesize or 12,C.amber)
  end

  local hit=inside(gfx.mouse_x,gfx.mouse_y,cx-r-12,cy-r-12,(r+12)*2,(r+12)*2)
  local left=(gfx.mouse_cap&1)==1
  local newleft=left and (prev_mouse&1)==0
  local shift=(gfx.mouse_cap&8)==8

  if newleft and hit and not active_knob then
    active_knob={id=id,start_y=gfx.mouse_y,start_n=n}
  end

  if active_knob and active_knob.id==id and left then
    local sens=shift and (sensitivity*5) or sensitivity
    local nn=clamp(active_knob.start_n+(active_knob.start_y-gfx.mouse_y)/sens,0,1)
    local nv=norm_to_value(nn,minv,maxv,islog)
    if opts.step then nv=math.floor(nv/opts.step+0.5)*opts.step end
    setp(tr,param,nv)
  end

  -- right-click resets to the supplied default
  local right=(gfx.mouse_cap&2)==2
  local newright=right and (prev_mouse&2)==0
  if newright and hit and default~=nil then setp(tr,param,default) end
end

local function bus_send_knob(id,cx,cy,r,busn,tr,opts)
  opts=opts or {}
  local val=send_db(tr,busn)
  local minv,maxv=-60,10
  local subgroup=bus_is_subgroup(busn)
  local n=subgroup and (val>-90 and 1 or 0) or clamp((val-minv)/(maxv-minv),0,1)
  local a1=math.rad(135); local a2=math.rad(405)
  draw_encoder_leds(cx,cy,r,n,C.amber,12)
  -- same silver/black encoder body used throughout the surface
  circle(cx,cy,r,{0.76,0.77,0.79},true); circle(cx,cy,r,C.white,false)
  circle(cx,cy,r-3,{0.18,0.19,0.20},true); circle(cx,cy,r-4,{0.47,0.48,0.50},false)
  circle(cx,cy,r-8,{0.05,0.05,0.06},true); circle(cx,cy,r-9,{0.23,0.23,0.24},false)
  circle(cx,cy,r-14,{0.62,0.63,0.65},true); circle(cx,cy,r-15,{0.88,0.88,0.89},false)
  local pa=a1+(a2-a1)*n
  line(cx,cy,cx+math.cos(pa)*(r-13),cy+math.sin(pa)*(r-13),C.white,2)
  text(cx+r+10,cy-9,tostring(busn),11,busn==selected_bus and C.amber or C.text)
  if subgroup then text(cx+r+10,cy+5,val>-90 and "ON" or "OFF",7,val>-90 and C.orange or C.dim) end

  local hit=inside(gfx.mouse_x,gfx.mouse_y,cx-r-12,cy-r-12,(r+12)*2,(r+12)*2)
  local left=(gfx.mouse_cap&1)==1
  local newleft=left and (prev_mouse&1)==0
  local shift=(gfx.mouse_cap&8)==8
  if newleft and hit and not active_knob then
    -- Choosing a send encoder changes the current send/SOF target, but must not
    -- promote that bus into the selected processing/PFL object.
    selected_bus=busn
    if subgroup then
      set_send_db(tr,busn,val>-90 and -150 or 0)
    else
      active_knob={id=id,start_y=gfx.mouse_y,start_n=n,bus=busn}
    end
  end
  if (not subgroup) and active_knob and active_knob.id==id and left then
    local sens=shift and 800 or 170
    local nn=clamp(active_knob.start_n+(active_knob.start_y-gfx.mouse_y)/sens,0,1)
    set_send_db(tr,busn,minv+nn*(maxv-minv))
  end
  local right=(gfx.mouse_cap&2)==2
  local newright=right and (prev_mouse&2)==0
  if newright and hit then
    selected_bus=busn
    set_send_db(tr,busn,-150)
  end
end

local function matrix_send_knob(id,cx,cy,r,matrixn,tr)
  local val=matrix_send_db(tr,matrixn)
  local minv,maxv=-60,10
  local n=clamp((val-minv)/(maxv-minv),0,1)
  local a1=math.rad(135); local a2=math.rad(405)
  draw_encoder_leds(cx,cy,r,n,C.amber,12)
  circle(cx,cy,r,{0.76,0.77,0.79},true); circle(cx,cy,r,C.white,false)
  circle(cx,cy,r-3,{0.18,0.19,0.20},true); circle(cx,cy,r-4,{0.47,0.48,0.50},false)
  circle(cx,cy,r-8,{0.05,0.05,0.06},true); circle(cx,cy,r-9,{0.23,0.23,0.24},false)
  circle(cx,cy,r-14,{0.62,0.63,0.65},true); circle(cx,cy,r-15,{0.88,0.88,0.89},false)
  local pa=a1+(a2-a1)*n
  line(cx,cy,cx+math.cos(pa)*(r-13),cy+math.sin(pa)*(r-13),C.white,2)
  text(cx+r+10,cy-7,tostring(matrixn),11,matrixn==selected_matrix and C.amber or C.text)

  local hit=inside(gfx.mouse_x,gfx.mouse_y,cx-r-12,cy-r-12,(r+12)*2,(r+12)*2)
  local left=(gfx.mouse_cap&1)==1; local newleft=left and (prev_mouse&1)==0
  local shift=(gfx.mouse_cap&8)==8
  if newleft and hit and not active_knob then
    selected_matrix=matrixn
    active_knob={id=id,start_y=gfx.mouse_y,start_n=n,matrix=matrixn}
  end
  if active_knob and active_knob.id==id and left then
    local sens=shift and 800 or 170
    local nn=clamp(active_knob.start_n+(active_knob.start_y-gfx.mouse_y)/sens,0,1)
    set_matrix_send_db(tr,matrixn,minv+nn*(maxv-minv))
  end
  local right=(gfx.mouse_cap&2)==2; local newright=right and (prev_mouse&2)==0
  if newright and hit then selected_matrix=matrixn; set_matrix_send_db(tr,matrixn,-150) end
end

local function meter(x,y,w,h,tr)
  rect(x,y,w,h,C.black,true)
  local peak=math.max(reaper.Track_GetPeakInfo(tr,0),reaper.Track_GetPeakInfo(tr,1))
  local pdb=lin2db(peak)
  local n=clamp((pdb+60)/60,0,1)
  local c=pdb>-3 and C.red or (pdb>-12 and C.yellow or C.green)
  rect(x,y+h*(1-n),w,h*n,c,true)
  for _,db in ipairs({-48,-36,-24,-18,-12,-6,-3}) do
    local yy=y+h*(1-clamp((db+60)/60,0,1))
    line(x-3,yy,x+w+3,yy,C.edge,1)
  end
  return pdb
end

local function led_meter_column(x,y,w,h,peak,label)
  local db=lin2db(math.max(peak,0.0000001))
  local segments=24
  local gap=2
  local seg_h=(h-gap*(segments-1))/segments
  rect(x-2,y-2,w+4,h+4,C.black,true)
  for i=1,segments do
    local frac=(i-1)/(segments-1)
    local threshold=-60+frac*63
    local yy=y+h-i*seg_h-(i-1)*gap
    local on=db>=threshold
    local c
    if threshold>=-3 then c=C.red elseif threshold>=-12 then c=C.yellow else c=C.green end
    if on then
      rect(x,yy,w,seg_h,c,true)
    else
      rect(x,yy,w,seg_h,{c[1]*0.14,c[2]*0.14,c[3]*0.14},true)
    end
  end
  centered(x-4,y+h+7,w+8,label,8,C.text)
  return db
end

local function clear_all_solos()
  -- Clear Live32 monitor-bus solos and any legacy REAPER solo states.
  for i=1,32 do if channels[i] then set_ext(channels[i],"LIVE32_SOLO",""); reaper.SetMediaTrackInfo_Value(channels[i],"I_SOLO",0) end end
  for i=1,8 do if fxreturns[i] then set_ext(fxreturns[i],"LIVE32_SOLO",""); reaper.SetMediaTrackInfo_Value(fxreturns[i],"I_SOLO",0) end end
  for i=1,16 do if buses[i] then set_ext(buses[i],"LIVE32_SOLO",""); reaper.SetMediaTrackInfo_Value(buses[i],"I_SOLO",0) end end
  for i=1,8 do if matrices[i] then set_ext(matrices[i],"LIVE32_SOLO",""); reaper.SetMediaTrackInfo_Value(matrices[i],"I_SOLO",0) end end
  for d=1,8 do
    if dcas[d] then
      reaper.GetSetMediaTrackInfo_String(dcas[d],"P_EXT:LIVE32_DCA_SOLO","0",true)
      reaper.SetMediaTrackInfo_Value(dcas[d],"I_SOLO",0)
    end
  end
  if update_monitor_solo_routing then update_monitor_solo_routing() end
  reaper.UpdateArrange()
end

local function draw_meter_bridge(x,y,w,h)
  rect(x,y,w,h,{0.045,0.050,0.054},true); rect(x,y,w,h,C.edge,false)
  centered(x,y+7,w,"METERS",10,C.text)
  local meter_y=y+38
  local meter_h=h-174
  local colw=13; local gap=7
  local total=colw*3+gap*2; local x0=x+(w-total)/2
  local ml=reaper.Track_GetPeakInfo(master,0); local mr=reaper.Track_GetPeakInfo(master,1)
  local solo_count,solo_label,solo_mode=monitor_solo_summary(); local solo_peak=0
  if solo_count>0 and monitor then
    solo_peak=math.max(reaper.Track_GetPeakInfo(monitor,0) or 0,reaper.Track_GetPeakInfo(monitor,1) or 0)
  end
  led_meter_column(x0,meter_y,colw,meter_h,ml,"L")
  led_meter_column(x0+colw+gap,meter_y,colw,meter_h,mr,"R")
  led_meter_column(x0+(colw+gap)*2,meter_y,colw,meter_h,solo_peak,solo_count>0 and solo_mode or "PFL")
  centered(x+3,y+h-127,w-6,solo_label,8,solo_count>0 and C.amber or C.dim)

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  centered(x+2,y+h-108,w-4,"MUTE GROUPS",7,C.dim)
  local bw=19; local bh=18; local gx=x+7; local gy=y+h-94
  for g=1,6 do
    local col=(g-1)%3; local row=(g-1)//3
    local bx=gx+col*(bw+3); local by=gy+row*(bh+4)
    local on=mute_group_on(g)
    rect(bx,by,bw,bh,on and C.red or C.panel2,true); rect(bx,by,bw,bh,on and C.white or C.edge,false)
    centered(bx,by+3,bw,tostring(g),9,on and C.white or C.dim)
    if click and inside(gfx.mouse_x,gfx.mouse_y,bx,by,bw,bh) then set_mute_group_on(g,not on) end
  end

end

local bands={
  {name="LOW",     freq=11,gain=12,q=13,minf=20,maxf=400,    df=100,dg=0,dq=0.8, modeparam=29, modeopts={{0,"LCUT"},{1,"LSHV"},{2,"PEQ"}}},
  {name="LO MID",  freq=14,gain=15,q=16,minf=80,maxf=2500,   df=500,dg=0,dq=1.2, modeparam=30, modeopts={{0,"VEQ"},{1,"PEQ"}}},
  {name="HI MID",  freq=17,gain=18,q=19,minf=300,maxf=10000, df=2500,dg=0,dq=1.2, modeparam=31, modeopts={{0,"VEQ"},{1,"PEQ"}}},
  {name="HIGH",    freq=20,gain=21,q=22,minf=1000,maxf=20000,df=8000,dg=0,dq=0.8, modeparam=32, modeopts={{0,"PEQ"},{1,"HSHV"},{2,"HCUT"}}}
}

-- Buses and MAIN LR use the same outer four filters plus two additional
-- parametric mid bands. The JSFX topology selector is param 45 (slider46).
output_bands={
  {name="LOW",     short="LOW",    freq=11,gain=12,q=13,minf=20,maxf=400,    df=100,dg=0,dq=0.8, modeparam=29, modeopts={{0,"LCUT"},{1,"LSHV"},{2,"PEQ"}}},
  {name="LOW MID", short="LO MID", freq=14,gain=15,q=16,minf=80,maxf=2500,   df=500,dg=0,dq=1.2, modeparam=30, modeopts={{0,"VEQ"},{1,"PEQ"}}},
  {name="MID 1",   short="MID 1",  freq=37,gain=38,q=39,minf=100,maxf=8000,  df=1000,dg=0,dq=1.2,modeparam=43, modeopts={{0,"VEQ"},{1,"PEQ"}}},
  {name="MID 2",   short="MID 2",  freq=40,gain=41,q=42,minf=300,maxf=16000, df=3500,dg=0,dq=1.2,modeparam=44, modeopts={{0,"VEQ"},{1,"PEQ"}}},
  {name="HIGH MID",short="HI MID", freq=17,gain=18,q=19,minf=300,maxf=10000, df=2500,dg=0,dq=1.2, modeparam=31, modeopts={{0,"VEQ"},{1,"PEQ"}}},
  {name="HIGH",    short="HIGH",   freq=20,gain=21,q=22,minf=1000,maxf=20000,df=8000,dg=0,dq=0.8, modeparam=32, modeopts={{0,"PEQ"},{1,"HSHV"},{2,"HCUT"}}}
}

function track_uses_six_band_eq(tr)
  local role=track_role(tr)
  return role=="MAIN" or role:match("^BUS%d+$")~=nil
end
local function band_mode_value(tr,b)
  return math.floor((getp(tr,b.modeparam) or 0)+0.5)
end
local function band_mode_label(tr,b)
  local v=band_mode_value(tr,b)
  for _,it in ipairs(b.modeopts) do if it[1]==v then return it[2] end end
  return "PEQ"
end
local function cycle_band_mode(tr,b)
  local opts=b.modeopts
  local v=band_mode_value(tr,b); local idx=1
  for i,it in ipairs(opts) do if it[1]==v then idx=i break end end
  idx=idx%#opts+1
  setp(tr,b.modeparam,opts[idx][1])
end
-- Compatibility wrappers used by the four-band input surface.
local function eq_mode_label(tr,band) return band_mode_label(tr,bands[band]) end
local function cycle_eq_mode(tr,band) cycle_band_mode(tr,bands[band]) end

local function view_button(cx,cy,r,page)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if round_button(cx,cy,r,"VIEW",screen_page==page,C.blue) and click then screen_page=page end
end

local function section_title(x,y,w,title,on)
  text(x+10,y+8,title,13,C.text)
  if on~=nil then
    circle(x+w-18,y+15,4,on and C.orange or C.edge2,true)
  end
end

-- The surface intentionally exposes only the controls that are immediately under
-- a user's fingers on a hardware desk. VIEW sends the detailed controls to the LCD.
local function draw_surface_preamp(tr,x,y,w,h)
  rect(x,y,w,h,C.panel,true); rect(x,y,w,h,C.edge,false)
  section_title(x,y,w,"CONFIG / PREAMP",getp(tr,2)>=0.5)

  local knob_y=y+52
  local leftx=x+47
  local rightx=x+w-47
  knob("surf_trim",leftx,knob_y,20,"",getp(tr,0),-18,18,function(v)return fmt_db(v) end,0,tr,{default=0,hide_label=true,hide_value=true})
  knob("surf_hpf",rightx,knob_y,20,"",getp(tr,3),20,400,function(v)return fmt_hz(v) end,3,tr,{log=true,default=80,hide_label=true,hide_value=true})

  centered(x+10,y+76,74,"GAIN",9,C.text)
  centered(x+w-84,y+76,74,"LOW CUT",9,C.text)
  centered(x+10,y+89,74,fmt_db(getp(tr,0)),10,C.amber)
  centered(x+w-84,y+89,74,fmt_hz(getp(tr,3)),10,C.amber)

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local phase=getp(tr,1)>=0.5; local hpf=getp(tr,2)>=0.5
  local by=y+h-27
  if button(x+8,by,40,21,"Ø",phase,C.blue) and click then setp(tr,1,phase and 0 or 1) end
  if button(x+53,by,70,21,"LOW CUT",hpf,C.orange) and click then setp(tr,2,hpf and 0 or 1) end
  view_button(x+w-24,y+h-17,14,"preamp")
end

local function draw_surface_gate(tr,x,y,w,h)
  rect(x,y,w,h,C.panel,true); rect(x,y,w,h,C.edge,false)
  section_title(x,y,w,"GATE",getp(tr,4)>=0.5)

  local ky=y+48
  knob("surf_gate_thr",x+w/2,ky,20,"",getp(tr,5),-80,0,function(v)return fmt_db(v) end,5,tr,{default=-45,hide_label=true,hide_value=true})
  centered(x+12,y+72,w-24,"THRESHOLD",9,C.text)
  centered(x+12,y+84,w-24,fmt_db(getp(tr,5)),10,C.amber)

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local on=getp(tr,4)>=0.5
  local by=y+h-27
  if button(x+12,by,52,21,"ON",on,C.orange) and click then setp(tr,4,on and 0 or 1) end
  view_button(x+w-24,y+h-17,14,"gate")
end

local function draw_surface_dyn(tr,x,y,w,h)
  rect(x,y,w,h,C.panel,true); rect(x,y,w,h,C.edge,false)
  section_title(x,y,w,"DYNAMICS",getp(tr,23)>=0.5)

  local ky=y+48
  knob("surf_comp_thr",x+w/2,ky,20,"",getp(tr,24),-60,0,function(v)return fmt_db(v) end,24,tr,{default=-18,hide_label=true,hide_value=true})
  centered(x+12,y+72,w-24,"THRESHOLD",9,C.text)
  centered(x+12,y+84,w-24,fmt_db(getp(tr,24)),10,C.amber)

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local on=getp(tr,23)>=0.5
  local by=y+h-27
  if button(x+12,by,52,21,"ON",on,C.orange) and click then setp(tr,23,on and 0 or 1) end
  view_button(x+w-24,y+h-17,14,"dyn")
end

local function draw_surface_eq(tr,x,y,w,h)
  -- M32-inspired shared EQ hardware. Inputs/FX use four bands; buses and MAIN LR
  -- use six bands. The two additional output mids are selected from the LCD VIEW,
  -- while the same WIDTH/FREQUENCY/GAIN encoders follow whichever band is active.
  local teal={0.055,0.105,0.115}
  local teal2={0.035,0.070,0.078}
  local soft={0.72,0.74,0.74}
  rect(x,y,w,h,teal,true); rect(x,y,w,h,C.edge,false)
  text(x+w-78,y+8,"EQUALISER",12,C.text)

  local six=track_uses_six_band_eq(tr)
  local active_band=six and selected_output_band or selected_band
  local b=six and output_bands[active_band] or bands[active_band]
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local eqon=getp(tr,10)>=0.5
  local mode=band_mode_label(tr,b)
  if six then text(x+8,y+8,"6 BAND",8,C.amber) end

  local lx=x+12
  text(lx,y+66,"HCUT",8,mode=="HCUT" and C.amber or soft); text(lx,y+77,"HSHV",8,mode=="HSHV" and C.amber or soft)
  line(lx+34,y+70,lx+43,y+70,soft,1); line(lx+43,y+70,lx+49,y+62,soft,1); line(lx+43,y+70,lx+49,y+78,soft,1)
  text(lx,y+118,"VEQ",8,mode=="VEQ" and C.amber or soft); text(lx,y+129,"PEQ",8,mode=="PEQ" and C.amber or soft)
  local gx=lx+43; local gy=y+127
  line(gx-9,gy+4,gx-5,gy+4,C.amber,2); line(gx-5,gy+4,gx-1,gy-4,C.amber,2); line(gx-1,gy-4,gx+3,gy-8,C.amber,2)
  line(gx+3,gy-8,gx+7,gy-4,C.amber,2); line(gx+7,gy-4,gx+11,gy+4,C.amber,2)
  text(lx,y+171,"LSHV",8,mode=="LSHV" and C.amber or soft); text(lx,y+182,"LCUT",8,mode=="LCUT" and C.amber or soft)
  line(lx+34,y+177,lx+43,y+177,soft,1); line(lx+43,y+177,lx+49,y+169,soft,1); line(lx+43,y+177,lx+49,y+185,soft,1)

  local kx=x+132
  local kid=(six and "out_" or "in_")..active_band
  knob("surf_eq_q_"..kid,kx,y+59,29,"WIDTH",getp(tr,b.q),0.3,10,function(v)return string.format("Q %.1f",v) end,b.q,tr,{log=true,default=b.dq,labelsize=11,hide_value=true})
  knob("surf_eq_f_"..kid,kx,y+153,29,"FREQUENCY",getp(tr,b.freq),b.minf,b.maxf,function(v)return fmt_hz(v) end,b.freq,tr,{log=true,default=b.df,labelsize=11,hide_value=true})
  knob("surf_eq_g_"..kid,kx,y+247,29,"GAIN",getp(tr,b.gain),-15,15,function(v)return fmt_db(v) end,b.gain,tr,{default=0,labelsize=11,hide_value=true})

  text(kx-49,y+139,"340",8,C.dim); text(kx+31,y+139,"1k",8,C.dim); text(kx-52,y+166,"120",8,C.dim)
  text(kx+34,y+166,"3k",8,C.dim); text(kx-43,y+181,"40",8,C.dim); text(kx+31,y+181,"10k",8,C.dim)

  local bx=x+w-68; local by=y+67
  local bandkeys=six and {{6,"HIGH"},{5,"HI MID"},{2,"LO MID"},{1,"LOW"}} or {{4,"HIGH"},{3,"HI MID"},{2,"LO MID"},{1,"LOW"}}
  for i,item in ipairs(bandkeys) do
    local bi=item[1]; local yy=by+(i-1)*52
    local selected_now=active_band==bi
    rect(bx,yy,56,31,teal2,true); rect(bx,yy,56,31,selected_now and C.orange or C.edge,false)
    rect(bx+3,yy+3,50,25,{0.065,0.070,0.072},true); rect(bx+3,yy+3,50,25,selected_now and C.amber or C.edge2,false)
    centered(bx,yy+8,56,item[2],10,selected_now and C.amber or C.text)
    if selected_now then circle(bx+47,yy+7,2.5,C.orange,true) end
    if inside(gfx.mouse_x,gfx.mouse_y,bx,yy,56,31) and click then
      if six then selected_output_band=bi; selected_output_eq_target=bi else selected_band=bi; selected_eq_target=bi end
    end
  end

  local brx=bx-10
  line(brx,by+14,brx,by+3*52+14,C.dim,1); for i=0,3 do line(brx,by+i*52+14,bx-3,by+i*52+14,C.dim,1) end
  text(brx-28,by+40,"HIGH 2",8,C.dim); text(brx-25,by+144,"LOW 2",8,C.dim)
  if six then centered(x+196,y+281,70,"MID 1/2",8,C.dim) end

  local by2=y+h-45
  if button(x+15,by2,58,28,"MODE",false,C.orange,teal2) and click then cycle_band_mode(tr,b) end
  centered(x+17,by2-14,54,mode,8,C.amber)
  if button(x+104,by2,58,28,"EQ",eqon,C.orange,teal2) and click then setp(tr,10,eqon and 0 or 1) end
  view_button(x+w-34,by2+14,15,"eq")
end

local function draw_surface_bus_sends(tr,x,y,w,h)
  local teal={0.055,0.105,0.115}
  local teal2={0.035,0.070,0.078}
  rect(x,y,w,h,teal,true); rect(x,y,w,h,C.edge,false)
  text(x+w-72,y+8,"BUS SENDS",11,C.text)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local first=(bus_bank-1)*4+1
  local knobx=x+38
  local ys={y+58,y+132,y+206,y+280}
  for i=1,4 do
    local busn=first+i-1
    bus_send_knob("surf_bus_"..busn,knobx,ys[i],20,busn,tr)
  end

  local bx=x+w-57
  local labels={{1,"BUS 1-4"},{2,"BUS 5-8"},{3,"BUS 9-12"},{4,"BUS 13-16"}}
  for i,item in ipairs(labels) do
    local yy=y+43+(i-1)*67
    local on=bus_bank==item[1]
    rect(bx,yy,49,32,teal2,true); rect(bx,yy,49,32,on and C.orange or C.edge,false)
    centered(bx,yy+6,49,item[2],7,on and C.amber or C.text)
    if inside(gfx.mouse_x,gfx.mouse_y,bx,yy,49,32) and click then bus_bank=item[1] end
  end
  view_button(x+w-27,y+h-28,15,"sends")
end

local function draw_surface_matrix_sends(tr,x,y,w,h)
  local teal={0.055,0.105,0.115}; local teal2={0.035,0.070,0.078}
  rect(x,y,w,h,teal,true); rect(x,y,w,h,C.edge,false)
  text(x+w-89,y+8,"MATRIX SENDS",10,C.text)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local first=(matrix_bank-1)*4+1
  local knobx=x+38; local ys={y+58,y+132,y+206,y+280}
  for i=1,4 do
    local mtx=first+i-1
    matrix_send_knob("surf_mtx_"..mtx,knobx,ys[i],20,mtx,tr)
  end
  local bx=x+w-57
  local labels={{1,"MTX 1-4"},{2,"MTX 5-8"}}
  for i,item in ipairs(labels) do
    local yy=(i==1) and (y+77) or (y+211)
    local on=matrix_bank==item[1]
    rect(bx,yy,49,32,teal2,true); rect(bx,yy,49,32,on and C.orange or C.edge,false)
    centered(bx,yy+6,49,item[2],7,on and C.amber or C.text)
    if inside(gfx.mouse_x,gfx.mouse_y,bx,yy,49,32) and click then matrix_bank=item[1] end
  end
  view_button(x+w-27,y+h-28,15,"sends")
end

-- Compact M32-style MAIN BUS hardware block: PAN/BAL plus assignment to Main L/R.
-- This intentionally omits Mono/Centre level and Mono/Centre assignment.
local function draw_surface_main_bus(tr,x,y,w,h)
  local teal={0.055,0.105,0.115}
  local teal2={0.035,0.070,0.078}
  rect(x,y,w,h,teal,true); rect(x,y,w,h,C.edge,false)
  centered(x,y+10,w,"MAIN BUS",11,C.text)

  -- Always show the selected member's actual pan on the encoder. A linked odd/even
  -- pair therefore reads hard L on the odd member and hard R on the even member,
  -- just like selecting each side of a stereo-linked channel on the desk.
  local pan=track_pan(tr)
  local linked=(fx_partner(tr)~=nil) or (stereo_link_partner(tr)~=nil)
  local cx=x+w/2; local cy=y+91
  local n=(pan+1)/2
  local a1=math.rad(135); local a2=math.rad(405)
  for i=0,10 do
    local a=a1+(a2-a1)*(i/10); local ro=35; local ri=29
    line(cx+math.cos(a)*ri,cy+math.sin(a)*ri,cx+math.cos(a)*ro,cy+math.sin(a)*ro,C.dim,1)
  end
  draw_arc(cx,cy,32,a1,a1+(a2-a1)*n,C.amber,2,22)
  circle(cx,cy,24,C.black,true); circle(cx,cy,24,C.edge,false)
  circle(cx,cy,19,C.shell,true); circle(cx,cy,18,C.blue,false)
  circle(cx,cy,13,C.black,true)
  local pa=a1+(a2-a1)*n
  line(cx,cy,cx+math.cos(pa)*10,cy+math.sin(pa)*10,C.amber,3)
  centered(x+3,y+124,w-6,"PAN/BAL",9,C.text)
  centered(x+3,y+141,w-6,fmt_pan(pan),10,C.amber)

  if not linked then
    local hit=inside(gfx.mouse_x,gfx.mouse_y,cx-36,cy-36,72,72)
    local left=(gfx.mouse_cap&1)==1
    local newleft=left and (prev_mouse&1)==0
    local shift=(gfx.mouse_cap&8)==8
    if newleft and hit and not active_knob then active_knob={id="main_pan",start_y=gfx.mouse_y,start_n=n} end
    if active_knob and active_knob.id=="main_pan" and left then
      local sens=shift and 700 or 160
      local nn=clamp(active_knob.start_n+(active_knob.start_y-gfx.mouse_y)/sens,0,1)
      set_track_pan(tr,nn*2-1)
    end
    local right=(gfx.mouse_cap&2)==2
    local newright=right and (prev_mouse&2)==0
    if newright and hit then set_track_pan(tr,0) end
  end

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local assigned=main_send_on(tr)
  local by=y+195
  if button(x+10,by,w-20,31,"MAIN ST",assigned,C.orange,teal2) and click then
    set_main_send(tr,not assigned)
  end
  centered(x+5,by+42,w-10,assigned and "IN L/R" or "OUT OF L/R",9,assigned and C.amber or C.dim)
end

local function screen_frame(x,y,w,h,title)
  rect(x,y,w,h,{0.045,0.065,0.072},true)
  rect(x,y,w,h,C.blue,false)
  rect(x+5,y+5,w-10,28,{0.10,0.15,0.18},true)
  text(x+13,y+11,title,13,C.white)
  local str=control_track()
  text(x+w-192,y+11,control_prefix().."  "..control_name(),12,C.amber)
end

local function screen_small_button(x,y,w,h,label,on,page)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if button(x,y,w,h,label,on,C.blue) and click then screen_page=page end
end

local function screen_tabs(x,y,w)
  local labels={{"HOME","home"},{"CONFIG","preamp"},{"GATE","gate"},{"DYN","dyn"},{"EQ","eq"},{"SENDS","sends"}}
  local gap=3
  local bw=math.floor((w-gap*(#labels-1))/#labels)
  for i,t in ipairs(labels) do screen_small_button(x+(i-1)*(bw+gap),y,bw,24,t[1],screen_page==t[2],t[2]) end
end

local function lcd_knob(id,cx,cy,r,label,val,minv,maxv,fmt,param,tr,opts)
  opts=opts or {}
  opts.labelsize=opts.labelsize or 10
  opts.valuesize=opts.valuesize or 10
  knob("lcd_"..id,cx,cy,r,label,val,minv,maxv,fmt,param,tr,opts)
end

local function draw_eq_graph(tr,x,y,w,h,compact)
  compact=compact or false
  local graphbg={0.030,0.050,0.065}; local grid={0.26,0.32,0.35}; local zero={0.62,0.67,0.69}
  local yellow={1.00,0.78,0.08}; local fill={0.95,0.68,0.02}
  local bandcols={
    [0]={0.18,0.80,0.92}, [1]={0.20,0.86,0.90}, [2]={0.96,0.82,0.16},
    [3]={0.22,0.86,0.42}, [4]={0.34,0.62,1.00}, [5]={0.92,0.30,0.78}, [6]={1.00,0.60,0.12}
  }
  rect(x,y,w,h,graphbg,true); rect(x,y,w,h,C.edge,false)
  local six=track_uses_six_band_eq(tr)
  local ebands=six and output_bands or bands
  local selected_target=six and selected_output_eq_target or selected_eq_target

  local function fxpos(f) return x+clamp(math.log(math.max(f,20)/20)/math.log(20000/20),0,1)*w end
  local function dbpos(db) return y+h/2-clamp(db,-15,15)/15*(h*0.43) end
  local eqon=getp(tr,10)>=0.5; local hpfon=getp(tr,2)>=0.5; local hpf_f=getp(tr,3)
  local pts={}
  for px=0,w,2 do
    local f=20*((20000/20)^(px/w)); local total=0
    if hpfon then
      -- 4th-order Butterworth HPF magnitude: 1/sqrt(1+(fc/f)^(2N)), N=4.
      local ratio=hpf_f/math.max(f,0.001)
      local mag=1/math.sqrt(1+ratio^8)
      total=total + 20*math.log(math.max(mag,0.000001),10)
    end
    if eqon then
      for bi,b in ipairs(ebands) do
        local bf=getp(tr,b.freq); local bg=getp(tr,b.gain); local bq=getp(tr,b.q)
        local mode=band_mode_label(tr,b); local oct=math.log(f/bf)/math.log(2)
        if mode=="PEQ" then
          local width=math.max(0.10,1.0/bq); total=total + bg*math.exp(-0.5*(oct/width)^2)
        elseif mode=="VEQ" then
          local width=math.max(0.18,1.7/math.max(bq,0.3)); total=total + bg*math.exp(-0.5*(oct/width)^2)
        elseif mode=="LSHV" then total=total + bg/(1+(f/math.max(bf,1))^2)
        elseif mode=="HSHV" then total=total + bg/(1+(math.max(bf,1)/math.max(f,1))^2)
        elseif mode=="LCUT" then
          local rr=math.max(f,0.001)/math.max(bf,0.001); local mag=(rr*rr)/math.sqrt((1-rr*rr)^2+2*rr*rr)
          total=total + 20*math.log(math.max(mag,0.000001),10)
        elseif mode=="HCUT" then
          local rr=math.max(f,0.001)/math.max(bf,0.001); local mag=1/math.sqrt((1-rr*rr)^2+2*rr*rr)
          total=total + 20*math.log(math.max(mag,0.000001),10)
        end
      end
    end
    total=clamp(total,-15,15); pts[#pts+1]={x+px,dbpos(total)}
  end

  setc(fill,compact and 0.22 or 0.34)
  for i=1,#pts do local px=pts[i][1]; local py=pts[i][2]; gfx.rect(px,py,2,math.max(0,y+h-py),1) end
  draw_rta_overlay(tr,x,y,w,h)

  local freqs={20,50,100,200,500,1000,2000,5000,10000,20000}
  for _,f in ipairs(freqs) do
    local xx=fxpos(f); line(xx,y,xx,y+h,grid,1)
    if not compact then
      local lab=f>=1000 and ((f%1000==0) and string.format("%dk",f/1000) or string.format("%.1fk",f/1000)) or tostring(f)
      text(xx+2,y+h-12,lab,8,C.dim)
    end
  end
  for _,db in ipairs({15,10,5,0,-5,-10,-15}) do
    local yy=dbpos(db); line(x,yy,x+w,yy,db==0 and zero or grid,db==0 and 1.4 or 1)
    if not compact then text(x+3,yy-9,string.format("%+d",db),8,db==0 and C.white or C.dim) end
  end
  for i=2,#pts do line(pts[i-1][1],pts[i-1][2],pts[i][1],pts[i][2],yellow,2) end

  local function marker(target,f,g,label,on)
    local xx=fxpos(f); local yy=dbpos(g or 0); local c=bandcols[target] or C.blue
    if not on then c=C.dim end
    local sz=compact and 6 or 9; rect(xx-sz/2,yy-sz/2,sz,sz,c,true)
    if selected_target==target and not compact then rect(xx-sz/2-2,yy-sz/2-2,sz+4,sz+4,C.white,false) end
    if not compact then centered(xx-9,yy-5,18,label,7,C.black) end
  end
  marker(0,hpf_f,-3,"0",hpfon)
  for bi,b in ipairs(ebands) do
    local mode=band_mode_label(tr,b); local g=(mode=="LCUT" or mode=="HCUT") and 0 or getp(tr,b.gain)
    marker(bi,getp(tr,b.freq),g,tostring(bi),eqon)
  end
end

local function draw_gate_mini(tr,x,y,w,h)
  rect(x,y,w,h,C.black,true); rect(x,y,w,h,C.edge,false)
  line(x+8,y+h-8,x+w-8,y+8,C.edge2,1)
  local thr=clamp((getp(tr,5)+80)/80,0,1)
  local tx=x+8+thr*(w-16)
  line(tx,y+6,tx,y+h-6,getp(tr,4)>=0.5 and C.orange or C.dim,2)
end

local function draw_dyn_mini(tr,x,y,w,h)
  rect(x,y,w,h,C.black,true); rect(x,y,w,h,C.edge,false)
  local x0=x+7; local y0=y+h-7; local x1=x+w-7; local y1=y+7
  line(x0,y0,x1,y1,C.edge2,1)
  local thr=clamp((getp(tr,24)+60)/60,0,1)
  local tx=x0+thr*(x1-x0); local ty=y0-thr*(y0-y1)
  local c=getp(tr,23)>=0.5 and C.orange or C.dim
  line(x0,y0,tx,ty,c,2)
  local ratio=math.max(getp(tr,25),1)
  local ex=x1
  local ey=ty-(ex-tx)/math.max(x1-x0,1)*(y0-y1)/ratio
  line(tx,ty,ex,ey,c,2)
end

local function home_block(x,y,w,h,title,on)
  rect(x,y,w,h,{0.105,0.125,0.135},true)
  rect(x,y,w,h,on and C.orange or C.edge,false)
  centered(x,y+5,w,title,10,on and C.orange or C.text)
  line(x+4,y+22,x+w-4,y+22,C.edge2,1)
end

local function draw_lcd_home(tr,x,y,w,h)
  screen_frame(x,y,w,h,"HOME")
  screen_tabs(x+8,y+38,w-16)

  local top=y+70; local bh=218; local gap=4
  local iw=58; local gw=68; local eqw=118; local dw=76; local ow=58
  local bw=w-16-iw-gw-eqw-dw-ow-gap*5
  local xx=x+8

  home_block(xx,top,iw,bh,"CONFIG",getp(tr,2)>=0.5)
  meter(xx+6,top+31,9,88,tr)
  text(xx+20,top+34,"Ø",8,getp(tr,1)>=0.5 and C.blue or C.dim)
  text(xx+20,top+50,"LC",8,getp(tr,2)>=0.5 and C.orange or C.dim)
  centered(xx+2,top+139,iw-4,"GAIN",8,C.dim)
  centered(xx+2,top+153,iw-4,fmt_db(getp(tr,0)),9,C.white)
  centered(xx+2,top+179,iw-4,"HPF",8,C.dim)
  centered(xx+2,top+193,iw-4,getp(tr,2)>=0.5 and fmt_hz(getp(tr,3)) or "OFF",9,getp(tr,2)>=0.5 and C.orange or C.dim)
  xx=xx+iw+gap

  home_block(xx,top,gw,bh,"GATE",getp(tr,4)>=0.5)
  draw_gate_mini(tr,xx+5,top+31,gw-10,82)
  centered(xx+2,top+126,gw-4,"THR",8,C.dim)
  centered(xx+2,top+141,gw-4,fmt_db(getp(tr,5)),9,C.white)
  centered(xx+2,top+173,gw-4,"RNG",8,C.dim)
  centered(xx+2,top+188,gw-4,string.format("%.0f",getp(tr,6)),9,C.white)
  xx=xx+gw+gap

  home_block(xx,top,eqw,bh,"EQ",getp(tr,10)>=0.5 or getp(tr,2)>=0.5)
  draw_eq_graph(tr,xx+5,top+31,eqw-10,96,true)
  local lc=getp(tr,2)>=0.5
  text(xx+6,top+137,"LC",8,lc and C.blue or C.dim)
  text(xx+22,top+137,lc and fmt_hz(getp(tr,3)) or "OFF",8,lc and C.white or C.dim)
  local b=track_uses_six_band_eq(tr) and output_bands[selected_output_band] or bands[selected_band]
  text(xx+6,top+158,b.name,8,C.orange)
  text(xx+6,top+173,fmt_hz(getp(tr,b.freq)),8,C.white)
  text(xx+6,top+190,fmt_db(getp(tr,b.gain)).."  Q"..string.format("%.1f",getp(tr,b.q)),8,C.dim)
  xx=xx+eqw+gap

  home_block(xx,top,dw,bh,"DYN",getp(tr,23)>=0.5)
  draw_dyn_mini(tr,xx+5,top+31,dw-10,82)
  centered(xx+2,top+126,dw-4,"THR",8,C.dim)
  centered(xx+2,top+141,dw-4,fmt_db(getp(tr,24)),9,C.white)
  centered(xx+2,top+173,dw-4,"RATIO",8,C.dim)
  centered(xx+2,top+188,dw-4,string.format("%.1f:1",getp(tr,25)),9,C.white)
  xx=xx+dw+gap

  home_block(xx,top,ow,bh,"OUT",true)
  meter(xx+6,top+31,9,88,tr)
  centered(xx+2,top+139,ow-4,"FADER",8,C.dim)
  centered(xx+2,top+153,ow-4,fmt_db(track_db(tr)),9,C.white)
  local hmute=reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5
  local hout=hmute and "MUTE" or (control_is_master() and "LR" or (main_send_on(tr) and "LR" or "NO LR"))
  centered(xx+2,top+184,ow-4,hout,9,hmute and C.red or (hout=="LR" and C.orange or C.dim))
  xx=xx+ow+gap

  if control_is_master() then
    home_block(xx,top,bw,bh,"MATRIX SENDS",true)
    for i=1,8 do
      local sy2=top+31+(i-1)*22
      local db=matrix_send_db(tr,i)
      text(xx+6,sy2,string.format("M%02d",i),7,i==selected_matrix and C.amber or C.dim)
      rect(xx+28,sy2+2,bw-36,7,C.black,true)
      local nn=clamp((db+60)/70,0,1)
      if nn>0 then rect(xx+28,sy2+2,(bw-36)*nn,7,i==selected_matrix and C.amber or C.green,true) end
    end
  elseif control_is_matrix() then
    home_block(xx,top,bw,bh,"MATRIX OUT",true)
    centered(xx+4,top+46,bw-8,string.format("MTX %02d",selected_matrix),13,C.green)
    centered(xx+4,top+76,bw-8,"OUTPUT",10,C.white)
    centered(xx+4,top+112,bw-8,"FADER",8,C.dim)
    centered(xx+4,top+128,bw-8,fmt_db(track_db(tr)),10,C.white)
    centered(xx+4,top+166,bw-8,"INDEPENDENT",8,C.dim)
    centered(xx+4,top+181,bw-8,"HARDWARE OUT",8,C.green)
  elseif control_is_bus() then
    home_block(xx,top,bw,bh,"MATRIX SENDS",true)
    centered(xx+3,top+24,bw-6,bus_tap_label(selected_bus,true),7,bus_is_subgroup(selected_bus) and C.orange or C.blue)
    for i=1,8 do
      local sy=top+41+(i-1)*21
      local db=matrix_send_db(tr,i)
      text(xx+6,sy,string.format("M%02d",i),7,i==selected_matrix and C.amber or C.dim)
      rect(xx+28,sy+2,bw-36,7,C.black,true)
      local nn=clamp((db+60)/70,0,1)
      if nn>0 then rect(xx+28,sy+2,(bw-36)*nn,7,i==selected_matrix and C.amber or C.green,true) end
    end
  else
    home_block(xx,top,bw,bh,"BUS SENDS",true)
    local colw=(bw-12)/2
    for i=1,16 do
      local col=(i-1)//8
      local row=(i-1)%8
      local sx=xx+5+col*(colw+2)
      local sy=top+29+row*22
      local db=send_db(tr,i)
      text(sx,sy,string.format("%02d",i),7,i==selected_bus and C.amber or C.dim)
      rect(sx+17,sy+2,colw-23,7,C.black,true)
      local nn=clamp((db+60)/70,0,1)
      if nn>0 then rect(sx+17,sy+2,(colw-23)*nn,7,i==selected_bus and C.amber or C.blue2,true) end
    end
  end

  local sy=top+bh+6
  rect(x+8,sy,w-16,32,{0.075,0.09,0.10},true); rect(x+8,sy,w-16,32,C.edge,false)
  local a,b,lk,odd,even=stereo_link_pair(tr)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if a and b then
    local linked=stereo_link_on(tr)
    if button(x+14,sy+4,44,24,"LINK",linked,C.orange,C.panel2) and click then set_stereo_link(tr,not linked) end
  else
    centered(x+14,sy+8,44,"--",8,C.edge)
  end
  local safe=scene_safe(tr)
  if button(x+62,sy+4,44,24,"SAFE",safe,C.yellow,C.panel2) and click then set_scene_safe(tr,not safe) end

  text(x+113,sy+9,"DCA",8,C.dim)
  local dca_ok=not control_is_matrix() and not control_is_master()
  for i=1,8 do
    local bx=x+139+(i-1)*19
    local on=dca_ok and dca_member(tr,i)
    rect(bx,sy+8,12,12,on and C.blue or C.black,true); rect(bx,sy+8,12,12,on and C.white or C.edge,false)
    centered(bx,sy+9,12,tostring(i),7,on and C.white or (dca_ok and C.dim or C.edge))
    if dca_ok and click and inside(gfx.mouse_x,gfx.mouse_y,bx-2,sy+6,16,16) then set_dca_member(tr,i,not on) end
  end

  text(x+296,sy+9,"MUTE",8,C.dim)
  local mg_ok=not control_is_matrix() and not control_is_master()
  for i=1,6 do
    local bx=x+335+(i-1)*20
    local on=mg_ok and mute_group_member(tr,i)
    rect(bx,sy+8,13,13,on and C.red or C.black,true); rect(bx,sy+8,13,13,on and C.white or C.edge,false)
    centered(bx,sy+9,13,tostring(i),7,on and C.white or (mg_ok and C.dim or C.edge))
    if mg_ok and click and inside(gfx.mouse_x,gfx.mouse_y,bx-2,sy+6,17,17) then set_mute_group_member(tr,i,not on) end
  end
end

function draw_config_insert_control(tr,x,y,w)
  if not tr or control_is_dca() then return end
  local fxbus=dedicated_fx_bus_number(tr)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if fxbus then
    local role=bus_role_name(fxbus) or "FX"
    text(x,y+5,"FX ENGINE",9,C.dim)
    if button(x+58,y,w-58,24,role,true,C.purple,C.panel2) and click then
      screen_page="effects"
      effects_subpage="engine"
    end
    return
  end
  local key=insert_type(tr)
  local def=INSERT_DEFS[key]
  local label=def and def.short or "INSERT OFF"
  local active=key~="none"
  text(x,y+5,"INSERT",9,C.dim)
  if button(x+48,y,w-48,24,label,active,C.purple,C.panel2) and click then
    screen_page="effects"
    effects_subpage="insert"
  end
end

local function draw_lcd_preamp(tr,x,y,w,h)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if control_is_bus() then
    screen_frame(x,y,w,h,"CONFIG / MIX BUS")
    screen_tabs(x+8,y+38,w-16)
    local bn=selected_bus
    text(x+18,y+78,string.format("BUS %02d PRECONFIGURATION",bn),13,C.blue)
    text(x+18,y+98,"Choose where every channel send to this bus is tapped.",9,C.dim)
    draw_config_insert_control(tr,x+w-150,y+75,132)
    local modes={
      {"PRE_EQ","PRE EQ","after LOW CUT / Gate, before channel EQ"},
      {"POST_EQ","POST EQ","after channel EQ, before Dynamics"},
      {"PRE_FADER","PRE FADER","after Dynamics, independent of channel fader"},
      {"POST_FADER","POST FADER","follows channel fader and pan"},
      {"SUBGROUP","SUB GROUP","post-fader unity assignment; send becomes ON/OFF"}
    }
    local current=bus_tap_mode(bn)
    for i,m in ipairs(modes) do
      local yy=y+120+(i-1)*42
      local on=current==m[1]
      if button(x+18,yy,112,29,m[2],on,on and C.orange or C.blue,C.panel2) and click then
        set_bus_tap_mode(bn,m[1]); current=m[1]
        local a,b,_,odd,even=stereo_link_pair(tr)
        if a and b and stereo_link_on(tr) and odd and even then
          local other=(bn==odd) and even or odd
          set_bus_tap_mode(other,m[1])
        end
        if m[1]=="SUBGROUP" then
          sof=true; sof_focus="bus"; selected_bus=bn; meter_focus="bus"
        end
      end
      text(x+143,yy+7,m[3],9,on and C.white or C.dim)
    end
    local yy=y+330
    centered(x+18,yy,w-36,"Current: "..bus_tap_label(bn,false),10,current=="SUBGROUP" and C.orange or C.amber)
    return
  end

  screen_frame(x,y,w,h,"CONFIG / PREAMP")
  screen_tabs(x+8,y+38,w-16)
  meter(x+22,y+82,18,h-105,tr)
  lcd_knob("trim",x+105,y+133,34,"GAIN",getp(tr,0),-18,18,function(v)return fmt_db(v).." dB" end,0,tr,{default=0})
  lcd_knob("hpf",x+218,y+133,34,"LOW CUT",getp(tr,3),20,400,function(v)return fmt_hz(v).." Hz" end,3,tr,{log=true,default=80})
  local phase=getp(tr,1)>=0.5; local hpf=getp(tr,2)>=0.5
  if button(x+70,y+215,92,32,"Ø PHASE",phase,C.blue) and click then setp(tr,1,phase and 0 or 1) end
  if button(x+176,y+215,100,32,"LOW CUT",hpf,C.orange) and click then setp(tr,2,hpf and 0 or 1) end
  rect(x+308,y+87,w-330,h-115,{0.065,0.085,0.10},true); rect(x+308,y+87,w-330,h-115,C.edge,false)
  text(x+324,y+101,"INPUT STAGE",13,C.blue)
  text(x+324,y+132,"Trim",11,C.dim); text(x+432,y+132,fmt_db(getp(tr,0)).." dB",11,C.white)
  text(x+324,y+157,"Polarity",11,C.dim); text(x+432,y+157,phase and "INVERTED" or "NORMAL",11,C.white)
  text(x+324,y+182,"Low Cut",11,C.dim); text(x+432,y+182,hpf and "ON" or "OFF",11,C.white)
  text(x+324,y+207,"Frequency",11,C.dim); text(x+432,y+207,fmt_hz(getp(tr,3)).." Hz",11,C.white)
  text(x+324,y+244,"INSERT PROCESSOR",10,C.blue)
  draw_config_insert_control(tr,x+324,y+265,w-346)
  text(x+324,y+304,"Insert assignment and status now live on CONFIG.",8,C.dim)
end

local function draw_lcd_gate(tr,x,y,w,h)
  screen_frame(x,y,w,h,"GATE")
  screen_tabs(x+8,y+38,w-16)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local on=getp(tr,4)>=0.5
  lcd_knob("gthr",x+48,y+133,28,"THRESHOLD",getp(tr,5),-80,0,function(v)return fmt_db(v).." dB" end,5,tr,{default=-45})
  lcd_knob("grange",x+140,y+133,28,"RANGE",getp(tr,6),0,80,function(v)return string.format("%.0f dB",v) end,6,tr,{default=50})
  lcd_knob("gatt",x+232,y+133,28,"ATTACK",getp(tr,7),0.1,100,fmt_ms,7,tr,{log=true,default=5})
  lcd_knob("ghold",x+324,y+133,28,"HOLD",getp(tr,8),0,500,fmt_ms,8,tr,{default=80})
  lcd_knob("grel",x+416,y+133,28,"RELEASE",getp(tr,9),5,2000,fmt_ms,9,tr,{log=true,default=180})
  if button(x+22,y+224,64,34,"ON",on,C.orange) and click then setp(tr,4,on and 0 or 1) end

  -- Transfer graph mirrors the visual language of the Dynamics page:
  -- input level on X, output level on Y. Below threshold the gate applies Range.
  local gx=x+112; local gy=y+218; local gw=150; local gh=112
  rect(gx,gy,gw,gh,C.black,true); rect(gx,gy,gw,gh,C.edge,false)
  for i=1,3 do
    line(gx+12+i*(gw-24)/4,gy+8,gx+12+i*(gw-24)/4,gy+gh-12,C.edge2,1)
    line(gx+12,gy+8+i*(gh-20)/4,gx+gw-12,gy+8+i*(gh-20)/4,C.edge2,1)
  end
  line(gx+12,gy+gh-12,gx+gw-12,gy+12,C.edge2,1)

  local thr=getp(tr,5)
  local range=getp(tr,6)
  local pts={}
  for i=0,64 do
    local input=-80+(80*i/64)
    local output
    if input >= thr then
      output=input
    else
      output=math.max(-80,input-range)
    end
    local px=gx+12+((input+80)/80)*(gw-24)
    local py=gy+gh-12-((output+80)/80)*(gh-24)
    pts[#pts+1]={px,py}
  end
  for i=2,#pts do line(pts[i-1][1],pts[i-1][2],pts[i][1],pts[i][2],on and C.amber or C.dim,2) end
  local tn=clamp((thr+80)/80,0,1)
  local tx=gx+12+tn*(gw-24)
  local ty=gy+gh-12-tn*(gh-24)
  circle(tx,ty,3,C.amber,true)
  line(tx,gy+8,tx,gy+gh-12,C.orange,1)

  text(x+286,y+232,"Gate transfer curve",11,C.dim)
  text(x+286,y+257,"Threshold  "..fmt_db(thr).." dB",11,C.white)
  text(x+286,y+280,string.format("Range      %.0f dB",range),11,C.white)
  text(x+286,y+303,"State      "..(on and "ACTIVE" or "BYPASSED"),11,on and C.orange or C.dim)
end

local function draw_lcd_dyn(tr,x,y,w,h)
  screen_frame(x,y,w,h,"DYNAMICS")
  screen_tabs(x+8,y+38,w-16)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local on=getp(tr,23)>=0.5

  -- M32-style two-page dynamics editor: main compressor controls on page 1,
  -- detector / knee controls on page 2.
  if button(x+w-88,y+69,34,22,"1",dyn_page==1,C.blue,C.panel2) and click then dyn_page=1 end
  if button(x+w-48,y+69,34,22,"2",dyn_page==2,C.blue,C.panel2) and click then dyn_page=2 end

  if dyn_page==1 then
    lcd_knob("cthr",x+48,y+133,28,"THRESHOLD",getp(tr,24),-60,0,function(v)return fmt_db(v).." dB" end,24,tr,{default=-18})
    lcd_knob("cratio",x+140,y+133,28,"RATIO",getp(tr,25),1,20,function(v)return string.format("%.1f:1",v) end,25,tr,{default=4})
    lcd_knob("catt",x+232,y+133,28,"ATTACK",getp(tr,26),0.1,200,fmt_ms,26,tr,{log=true,default=10})
    lcd_knob("crel",x+324,y+133,28,"RELEASE",getp(tr,27),5,2000,fmt_ms,27,tr,{log=true,default=120})
    lcd_knob("cmake",x+416,y+133,28,"MAKEUP",getp(tr,28),-12,18,function(v)return fmt_db(v).." dB" end,28,tr,{default=0})
    if button(x+22,y+224,64,34,"ON",on,C.orange) and click then setp(tr,23,on and 0 or 1) end
    local gx=x+154; local gy=y+218; local gw=150; local gh=112
    rect(gx,gy,gw,gh,C.black,true); rect(gx,gy,gw,gh,C.edge,false)
    line(gx+12,gy+gh-12,gx+gw-12,gy+12,C.edge2,1)
    local thr=clamp((getp(tr,24)+60)/60,0,1)
    local tx=gx+12+thr*(gw-24); local ty=gy+gh-12-thr*(gh-24)
    line(gx+12,gy+gh-12,tx,ty,C.amber,2)
    local ratio=math.max(getp(tr,25),1)
    line(tx,ty,gx+gw-12,ty-(gx+gw-12-tx)/ratio*(gh-24)/(gw-24),C.amber,2)
    text(x+330,y+232,"Compressor curve",11,C.dim)
    text(x+330,y+257,"Threshold  "..fmt_db(getp(tr,24)).." dB",11,C.white)
    text(x+330,y+280,string.format("Ratio      %.1f:1",getp(tr,25)),11,C.white)
    text(x+330,y+303,"Knee       "..string.format("%.0f",getp(tr,33)),11,C.white)
  else
    -- New JSFX parameters: 33=knee, 34=key-filter enable, 35=key HPF freq,
    -- 36=key source mode (SELF / external channels 3/4).
    lcd_knob("cknee",x+82,y+145,31,"KNEE",getp(tr,33),0,5,function(v)return string.format("%.0f",v) end,33,tr,{default=0,step=1})
    lcd_knob("ckeyf",x+205,y+145,31,"KEY FILTER",getp(tr,35),20,20000,function(v)return fmt_hz(v).." Hz" end,35,tr,{log=true,default=120})
    local keyon=getp(tr,34)>=0.5
    if button(x+278,y+125,82,29,"KEY HPF",keyon,C.orange,C.panel2) and click then setp(tr,34,keyon and 0 or 1) end
    if button(x+374,y+125,72,29,"COMP ON",on,C.orange,C.panel2) and click then setp(tr,23,on and 0 or 1) end

    local sy=y+218
    rect(x+22,sy,w-44,104,{0.065,0.085,0.10},true); rect(x+22,sy,w-44,104,C.edge,false)
    text(x+35,sy+12,"KEY SOURCE",11,C.blue)
    local ks=key_source_index(tr)
    if is_master_track(tr) then
      centered(x+130,sy+34,w-260,"SELF",18,C.amber)
      centered(x+45,sy+68,w-90,"MAIN LR detector remains self-keyed",9,C.dim)
    else
      if button(x+82,sy+31,44,30,"<",false,C.blue,C.panel2) and click then set_key_source(tr,(ks-1)%33) end
      centered(x+136,sy+34,180,key_source_label(tr),18,C.amber)
      if button(x+326,sy+31,44,30,">",false,C.blue,C.panel2) and click then set_key_source(tr,(ks+1)%33) end
      centered(x+45,sy+71,w-90,ks==0 and "Internal post-EQ detector" or "Pre-FX sidechain feed to inputs 3/4",9,C.dim)
    end
  end
end

local function draw_lcd_eq(tr,x,y,w,h)
  local six=track_uses_six_band_eq(tr)
  screen_frame(x,y,w,h,six and "EQUALISER / 6 BAND" or "EQUALISER")
  screen_tabs(x+8,y+38,w-16)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local eqon=getp(tr,10)>=0.5; local hpfon=getp(tr,2)>=0.5
  local ebands=six and output_bands or bands
  local target=six and selected_output_eq_target or selected_eq_target
  local bandcols={
    [0]={0.18,0.80,0.92}, [1]={0.20,0.86,0.90}, [2]={0.96,0.82,0.16},
    [3]={0.22,0.86,0.42}, [4]={0.34,0.62,1.00}, [5]={0.92,0.30,0.78}, [6]={1.00,0.60,0.12}
  }

  draw_eq_graph(tr,x+18,y+70,w-36,132,false)

  -- M32-style parameter cards. Inputs expose LOW CUT + four bands; buses and
  -- MAIN LR expose LOW CUT + all six output EQ bands.
  local count=#ebands+1; local cardx=x+18; local cardy=y+207; local gap=3
  local cardw=math.floor((w-36-gap*(count-1))/count); local cardh=67
  for ci=0,#ebands do
    local xx=cardx+ci*(cardw+gap); local active=target==ci; local cc=bandcols[ci] or C.blue
    rect(xx,cardy,cardw,cardh,{0.075,0.095,0.105},true); rect(xx,cardy,cardw,cardh,active and cc or C.edge,false)
    rect(xx,cardy,cardw,16,active and cc or {0.13,0.16,0.17},true)
    local name=ci==0 and "LOW CUT" or (ebands[ci].short or ebands[ci].name)
    centered(xx,cardy+3,cardw,name,six and 7 or 8,active and C.black or C.text)
    if ci==0 then
      centered(xx+2,cardy+21,cardw-4,fmt_hz(getp(tr,3)).." Hz",8,C.white)
      centered(xx+2,cardy+36,cardw-4,hpfon and "ON" or "OFF",8,hpfon and C.amber or C.dim)
      centered(xx+2,cardy+51,cardw-4,"24 dB/OCT",7,C.dim)
    else
      local b=ebands[ci]; local mode=band_mode_label(tr,b)
      centered(xx+2,cardy+18,cardw-4,fmt_hz(getp(tr,b.freq)),8,C.white)
      centered(xx+2,cardy+31,cardw-4,fmt_db(getp(tr,b.gain)),8,C.white)
      centered(xx+2,cardy+44,cardw-4,"Q "..string.format("%.2f",getp(tr,b.q)),7,C.dim)
      centered(xx+2,cardy+55,cardw-4,mode,7,C.amber)
    end
    if inside(gfx.mouse_x,gfx.mouse_y,xx,cardy,cardw,cardh) and click then
      if six then selected_output_eq_target=ci; if ci>0 then selected_output_band=ci end
      else selected_eq_target=ci; if ci>0 then selected_band=ci end end
    end
  end

  local cy=y+307
  if target==0 then
    lcd_knob("hpf_eq",x+86,cy,20,"LOW CUT",getp(tr,3),20,400,function(v)return fmt_hz(v) end,3,tr,{log=true,default=80,hide_value=true,labelsize=9})
    centered(x+38,y+333,96,fmt_hz(getp(tr,3)).." Hz",8,C.amber)
    if button(x+160,y+291,72,28,"ON",hpfon,C.orange,C.panel2) and click then setp(tr,2,hpfon and 0 or 1) end
    text(x+251,y+293,"24 dB/oct 4th-order Butterworth LOW CUT",9,C.dim)
  else
    local bi=six and selected_output_band or selected_band; local b=ebands[bi]; local mode=band_mode_label(tr,b)
    local prefix=six and "out" or "in"
    lcd_knob(prefix.."_eqf"..bi,x+76,cy,20,"FREQ",getp(tr,b.freq),b.minf,b.maxf,function(v)return fmt_hz(v) end,b.freq,tr,{log=true,default=b.df,hide_value=true,labelsize=9})
    if mode~="LCUT" and mode~="HCUT" then
      lcd_knob(prefix.."_eqg"..bi,x+174,cy,20,"GAIN",getp(tr,b.gain),-15,15,function(v)return fmt_db(v) end,b.gain,tr,{default=0,hide_value=true,labelsize=9})
      lcd_knob(prefix.."_eqq"..bi,x+272,cy,20,"Q",getp(tr,b.q),0.3,10,function(v)return string.format("%.2f",v) end,b.q,tr,{log=true,default=b.dq,hide_value=true,labelsize=9})
    else
      centered(x+134,y+299,235,mode.." FILTER",10,C.blue)
    end
    if button(x+374,y+291,76,28,"MODE",false,C.orange,C.panel2) and click then cycle_band_mode(tr,b) end
    centered(x+374,y+323,76,mode,8,C.amber)
    if button(x+w-96,y+291,78,28,"EQ IN",eqon,C.orange,C.panel2) and click then setp(tr,10,eqon and 0 or 1) end
  end
end

local function draw_lcd_sends(tr,x,y,w,h)
  screen_frame(x,y,w,h,"SENDS")
  screen_tabs(x+8,y+38,w-16)
  if control_is_matrix() then
    centered(x+20,y+135,w-40,"MATRIX OUTPUT",15,C.blue)
    centered(x+20,y+170,w-40,"Matrix outputs are destination mixes.",11,C.dim)
    centered(x+20,y+198,w-40,"Select a BUS to adjust its Matrix sends.",11,C.white)
    return
  end
  if control_is_bus() or control_is_master() then
    text(x+18,y+76,control_is_master() and "MAIN LR → 8 MATRIX SENDS" or "8 MATRIX SENDS",12,control_is_master() and C.orange or C.blue)
    text(x+170,y+76,"Selected MTX "..string.format("%02d",selected_matrix),11,C.amber)
    local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
    local left=(gfx.mouse_cap&1)==1
    local colw=w-36
    for i=1,8 do
      local rx=x+18; local ry=y+103+(i-1)*28
      local db=matrix_send_db(tr,i); local chosen=i==selected_matrix
      rect(rx,ry,colw,22,chosen and {0.11,0.15,0.17} or {0.07,0.085,0.095},true)
      rect(rx,ry,colw,22,chosen and C.orange or C.edge,false)
      text(rx+5,ry+6,string.format("MTX %02d",i),9,chosen and C.amber or C.text)
      local bx=rx+58; local bw2=colw-112
      rect(bx,ry+7,bw2,8,C.black,true)
      local nn=clamp((db+60)/70,0,1)
      if nn>0 then rect(bx,ry+7,bw2*nn,8,chosen and C.amber or C.blue,true) end
      text(rx+colw-42,ry+5,fmt_db(db),8,C.dim)
      if inside(gfx.mouse_x,gfx.mouse_y,rx,ry,colw,22) and click then selected_matrix=i; matrix_bank=math.floor((i-1)/4)+1 end
      if left and inside(gfx.mouse_x,gfx.mouse_y,bx,ry+2,bw2,18) and not active_knob then
        selected_matrix=i; matrix_bank=math.floor((i-1)/4)+1
        local nv=clamp((gfx.mouse_x-bx)/bw2,0,1)
        set_matrix_send_db(tr,i,-60+nv*70)
      end
    end
    text(x+18,y+h-25,control_is_master() and "MAIN LR selected: hardware sends become MATRIX SENDS." or "Bus selected: hardware BUS SENDS becomes MATRIX SENDS.",9,C.dim)
    return
  end
  text(x+18,y+76,"16 MIX BUS SENDS",12,C.blue)
  text(x+170,y+76,"Selected BUS "..string.format("%02d",selected_bus),11,C.amber)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local left=(gfx.mouse_cap&1)==1
  local colw=(w-42)/2
  for i=1,16 do
    local col=(i-1)//8; local row=(i-1)%8
    local rx=x+16+col*(colw+10); local ry=y+103+row*28
    local db=send_db(tr,i)
    local chosen=i==selected_bus
    rect(rx,ry,colw,22,chosen and {0.11,0.15,0.17} or {0.07,0.085,0.095},true)
    rect(rx,ry,colw,22,chosen and C.orange or C.edge,false)
    text(rx+5,ry+6,string.format("%02d",i),9,chosen and C.amber or C.text)
    local bx=rx+27; local bw2=colw-110
    rect(bx,ry+7,bw2,8,C.black,true)
    local nn=clamp((db+60)/70,0,1)
    if nn>0 then rect(bx,ry+7,bw2*nn,8,chosen and C.amber or C.blue,true) end
    local mode=bus_tap_mode(i); local mx=rx+colw-83
    local mcol=mode=="SUBGROUP" and C.orange or (mode=="POST_FADER" and C.panel2 or C.blue2)
    rect(mx,ry+3,42,16,mcol,true); rect(mx,ry+3,42,16,mode=="SUBGROUP" and C.orange or C.edge,false)
    centered(mx,ry+5,42,BUS_TAP_MODES[mode].short,6,mode=="SUBGROUP" and C.black or C.white)
    text(rx+colw-38,ry+5,bus_is_subgroup(i) and (db>-90 and "ON" or "OFF") or fmt_db(db),8,C.dim)
    if inside(gfx.mouse_x,gfx.mouse_y,rx,ry,colw,22) and click then
      selected_bus=i; bus_bank=math.floor((i-1)/4)+1
    end
    if left and inside(gfx.mouse_x,gfx.mouse_y,bx,ry+2,bw2,18) and not active_knob then
      selected_bus=i; bus_bank=math.floor((i-1)/4)+1
      local nv=clamp((gfx.mouse_x-bx)/bw2,0,1)
      set_send_db(tr,i,-60+nv*70)
    end
  end
  text(x+18,y+h-25,"Bus tap mode is configured by selecting the BUS and opening CONFIG.",9,C.dim)
end

function fx_vertical_slider(tr,fx,param,x,y,w,h,label,accent)
  accent=accent or C.amber
  local active=param and param>=0
  local n=active and reaper.TrackFX_GetParamNormalized(tr,fx,param) or 0.5
  centered(x,y-22,w,label,9,active and C.text or C.dim)
  rect(x+w/2-2,y,4,h,C.black,true)
  for i=0,8 do
    local yy=y+i*h/8
    line(x+8,yy,x+w-8,yy,C.edge2,1)
  end
  local ky=y+h-(n*h)
  rect(x+5,ky-6,w-10,12,active and C.white or C.edge,true)
  rect(x+5,ky-6,w-10,12,C.edge,false)
  centered(x,y+h+8,w,active and fx_value_text(tr,fx,param) or "N/A",8,active and accent or C.dim)
  if active and (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,x,y-6,w,h+12) and not active_knob then
    local nn=clamp((y+h-gfx.mouse_y)/h,0,1)
    reaper.TrackFX_SetParamNormalized(tr,fx,param,nn)
  end
end

function insert_vertical_slider(tr,fx,param,x,y,w,h,label,accent)
  accent=accent or C.amber
  if fx<0 then return end
  local n=reaper.TrackFX_GetParamNormalized(tr,fx,param) or 0
  centered(x,y-21,w,label,8,C.text)
  rect(x+w/2-2,y,4,h,C.black,true)
  for i=0,8 do local yy=y+i*h/8; line(x+7,yy,x+w-7,yy,C.edge2,1) end
  local ky=y+h-n*h
  rect(x+4,ky-6,w-8,12,C.white,true); rect(x+4,ky-6,w-8,12,C.edge,false)
  centered(x,y+h+6,w,fx_value_text(tr,fx,param),7,accent)
  if (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,x,y-5,w,h+10) and not active_knob then
    set_insert_param_norm(tr,param,clamp((y+h-gfx.mouse_y)/h,0,1))
  end
end

function insert_knob(tr,fx,param,id,cx,cy,r,label,accent,default_norm)
  if fx<0 then return end
  accent=accent or C.amber
  local n=reaper.TrackFX_GetParamNormalized(tr,fx,param) or 0
  local a1=math.rad(135); local a2=math.rad(405)
  draw_encoder_leds(cx,cy,r,n,accent,12)
  circle(cx,cy,r,{0.76,0.77,0.79},true)
  circle(cx,cy,r,C.white,false)
  circle(cx,cy,r-3,{0.18,0.19,0.20},true)
  circle(cx,cy,r-4,{0.47,0.48,0.50},false)
  circle(cx,cy,r-8,{0.05,0.05,0.06},true)
  circle(cx,cy,r-9,{0.23,0.23,0.24},false)
  circle(cx,cy,r-13,{0.62,0.63,0.65},true)
  circle(cx,cy,r-14,{0.88,0.88,0.89},false)
  local pa=a1+(a2-a1)*n
  line(cx,cy,cx+math.cos(pa)*(r-10),cy+math.sin(pa)*(r-10),C.white,2)
  centered(cx-r-22,cy+r+12,(r+22)*2,label,9,C.text)
  centered(cx-r-32,cy+r+28,(r+32)*2,fx_value_text(tr,fx,param),8,accent)
  local hit=inside(gfx.mouse_x,gfx.mouse_y,cx-r-11,cy-r-11,(r+11)*2,(r+11)*2)
  local left=(gfx.mouse_cap&1)==1; local newleft=left and (prev_mouse&1)==0
  local shift=(gfx.mouse_cap&8)==8
  if newleft and hit and not active_knob then active_knob={id=id,start_y=gfx.mouse_y,start_n=n} end
  if active_knob and active_knob.id==id and left then
    local sens=shift and 800 or 180
    local nn=clamp(active_knob.start_n+(active_knob.start_y-gfx.mouse_y)/sens,0,1)
    set_insert_param_norm(tr,param,nn)
  end
  local right=(gfx.mouse_cap&2)==2; local newright=right and (prev_mouse&2)==0
  if newright and hit and default_norm~=nil then set_insert_param_norm(tr,param,default_norm) end
end

function draw_insert_vu(x,y,w,h,gr,title)
  local face={0.73,0.68,0.53}; local ink={0.16,0.11,0.07}
  rect(x,y,w,h,face,true); rect(x,y,w,h,C.edge,false)
  centered(x,y+5,w,title or "GR",9,ink)
  local cx=x+w/2; local cy=y+h-9; local r=math.min(w*0.42,h*0.80)
  draw_arc(cx,cy,r,math.rad(205),math.rad(335),ink,1,20)
  for i=0,5 do
    local a=math.rad(205)+(math.rad(130))*i/5
    line(cx+math.cos(a)*(r-5),cy+math.sin(a)*(r-5),cx+math.cos(a)*(r+1),cy+math.sin(a)*(r+1),ink,1)
  end
  local amt=clamp((-gr)/20,0,1)
  local a=math.rad(205)+math.rad(130)*(1-amt)
  line(cx,cy,cx+math.cos(a)*(r-9),cy+math.sin(a)*(r-9),C.red,2)
end

function draw_insert_choice_bar(tr,x,y,w)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local cur=insert_type(tr)
  local choices={{"NONE","none"},{"LIMITER","limiter"},{"GEQ 31","geq"},{"FET 76","fet"},{"OPTO 2A","opto"}}
  local gap=4; local bw=(w-gap*4)/5
  for i,c in ipairs(choices) do
    local bx=x+(i-1)*(bw+gap)
    if button(bx,y,bw,25,c[1],cur==c[2],c[2]=="none" and C.dim or C.orange,C.panel2) and click then
      set_insert_type(tr,c[2]); cur=insert_type(tr)
    end
  end
end

function draw_limiter_insert(tr,fx,x,y,w,h)
  local metal={0.72,0.73,0.71}; local dark={0.09,0.10,0.10}
  rect(x+10,y+89,w-20,h-101,metal,true); rect(x+10,y+89,w-20,h-101,C.edge,false)
  centered(x+18,y+100,w-36,"STEREO PRECISION LIMITER",11,dark)
  local labels={"INPUT","CEILING","SQUEEZE","KNEE","ATTACK","RELEASE"}
  local sw=(w-48)/6
  for i=1,6 do insert_vertical_slider(tr,fx,i-1,x+18+(i-1)*sw,y+145,sw-8,105,labels[i],C.blue) end
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local auto=select(1,reaper.TrackFX_GetParam(tr,fx,6))>=0.5
  if button(x+20,y+288,78,25,"AUTO GAIN",auto,C.green,C.panel2) and click then set_insert_param_raw(tr,6,auto and 0 or 1) end
  insert_knob(tr,fx,7,"ins_lim_out",x+155,y+285,18,"OUTPUT",C.blue,0.75)
  local gr=select(1,reaper.TrackFX_GetParam(tr,fx,8)) or 0
  draw_insert_vu(x+w-151,y+264,128,58,gr,"GAIN REDUCTION")
end

GEQ_LABELS={"20","25","31","40","50","63","80","100","125","160","200","250","315","400","500","630","800","1k","1.25k","1.6k","2k","2.5k","3.15k","4k","5k","6.3k","8k","10k","12.5k","16k","20k"}
function draw_geq_insert(tr,fx,x,y,w,h)
  local dark={0.055,0.060,0.066}; rect(x+10,y+89,w-20,h-101,dark,true); rect(x+10,y+89,w-20,h-101,C.edge,false)
  centered(x+14,y+98,w-28,"STEREO 31-BAND GRAPHIC EQ   •   1/3 OCTAVE",10,C.text)
  local gx=x+18; local gy=y+133; local gh=143; local gap=2; local fw=(w-48-gap*30)/31
  fw=math.max(12,fw)
  for i=1,31 do
    local px=gx+(i-1)*(fw+gap)
    local n=reaper.TrackFX_GetParamNormalized(tr,fx,i-1) or 0.5
    rect(px+fw/2-1,gy,2,gh,C.black,true)
    local zero=gy+gh/2; line(px,zero,px+fw,zero,C.orange,1)
    local ky=gy+gh-n*gh
    rect(px,ky-4,fw,8,C.white,true); rect(px,ky-4,fw,8,C.edge,false)
    if (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,px-1,gy-5,fw+2,gh+10) and not active_knob then
      set_insert_param_norm(tr,i-1,clamp((gy+gh-gfx.mouse_y)/gh,0,1))
    end
    if i%2==1 then centered(px-3,gy+gh+6,fw+6,GEQ_LABELS[i],6,C.dim) end
  end
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if button(x+20,y+h-42,72,27,"RESET",false,C.orange,C.panel2) and click then
    for i=0,30 do set_insert_param_raw(tr,i,0) end
  end
  insert_knob(tr,fx,31,"ins_geq_out",x+w-62,y+h-69,18,"OUTPUT",C.blue,0.5)
end

function draw_fet_insert(tr,fx,x,y,w,h)
  local face={0.075,0.075,0.070}
  rect(x+10,y+89,w-20,h-101,face,true); rect(x+10,y+89,w-20,h-101,C.edge,false)
  text(x+24,y+102,"FET 76",14,C.red); text(x+91,y+107,"LIMITING AMPLIFIER",8,C.dim)

  -- Compact layout sized to the 485 px Live32 LCD. Nothing extends into the hard-key column.
  insert_knob(tr,fx,0,"ins_fet_in",x+92,y+190,34,"INPUT",C.orange,0.333)
  insert_knob(tr,fx,1,"ins_fet_out",x+202,y+190,34,"OUTPUT",C.orange,0.5)
  insert_knob(tr,fx,2,"ins_fet_att",x+292,y+158,19,"ATTACK",C.amber,0.333)
  insert_knob(tr,fx,3,"ins_fet_rel",x+292,y+236,19,"RELEASE",C.amber,0.5)

  local gr=select(1,reaper.TrackFX_GetParam(tr,fx,6)) or 0
  draw_insert_vu(x+338,y+124,125,69,gr,"GAIN REDUCTION")

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local ratio=math.floor((select(1,reaper.TrackFX_GetParam(tr,fx,4)) or 0)+0.5)
  local rs={{0,"4"},{1,"8"},{2,"12"},{3,"20"},{4,"ALL"}}
  local rb=x+336
  for i,r in ipairs(rs) do
    local bx=rb+(i-1)*26
    if button(bx,y+245,24,25,r[2],ratio==r[1],C.orange,C.panel2) and click then set_insert_param_raw(tr,4,r[1]) end
  end
  centered(x+334,y+278,132,"RATIO",8,C.dim)
end

function draw_opto_insert(tr,fx,x,y,w,h)
  local face={0.80,0.78,0.70}; local ink={0.12,0.10,0.08}
  rect(x+10,y+89,w-20,h-101,face,true); rect(x+10,y+89,w-20,h-101,C.edge,false)
  text(x+24,y+102,"OPTO 2A",14,C.red); text(x+99,y+107,"LEVELING AMPLIFIER",8,ink)

  -- Two large optical controls with the meter and mode switch fully contained in the LCD.
  insert_knob(tr,fx,1,"ins_opto_gain",x+98,y+205,39,"GAIN",C.orange,0)
  insert_knob(tr,fx,0,"ins_opto_pr",x+236,y+205,39,"PEAK REDUCTION",C.orange,0.35)
  local gr=select(1,reaper.TrackFX_GetParam(tr,fx,3)) or 0
  draw_insert_vu(x+330,y+125,132,76,gr,"GAIN REDUCTION")

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local lim=select(1,reaper.TrackFX_GetParam(tr,fx,2))>=0.5
  if button(x+340,y+238,112,29,lim and "LIMIT" or "COMPRESS",lim,C.orange,C.panel2) and click then set_insert_param_raw(tr,2,lim and 0 or 1) end
  centered(x+316,y+286,154,"OPTICAL • PROGRAM RELEASE",7,ink)
end

function draw_lcd_insert(tr,x,y,w,h)
  screen_frame(x,y,w,h,"EFFECTS / INSERT")
  if control_is_dca() or not tr then
    centered(x+20,y+145,w-40,"Select an audio channel, bus, matrix or Main LR",13,C.amber)
    centered(x+20,y+171,w-40,"to assign an insert processor.",10,C.dim)
    return
  end
  draw_insert_choice_bar(tr,x+14,y+50,w-28)
  local key=insert_type(tr)
  if key=="none" then
    centered(x+20,y+150,w-40,"NO INSERT ASSIGNED",15,C.dim)
    centered(x+20,y+184,w-40,"Choose Limiter, GEQ 31, FET 76 or Opto 2A above.",10,C.white)
    centered(x+20,y+213,w-40,"The insert is post channel/output DSP and pre meter / dedicated FX engine.",9,C.dim)
    return
  end
  local fx=insert_fxidx(tr,key)
  if fx<0 then
    centered(x+20,y+155,w-40,"INSERT PROCESSOR COULD NOT BE LOADED",12,C.red)
    centered(x+20,y+183,w-40,"Run the v1.0.6 clean Setup so the Live32 JSFX library is installed.",9,C.dim)
    return
  end
  local enabled=reaper.TrackFX_GetEnabled(tr,fx)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if button(x+w-89,y+10,70,22,enabled and "IN" or "BYPASS",enabled,C.green,C.panel2) and click then set_insert_enabled(tr,not enabled) end
  if key=="limiter" then draw_limiter_insert(tr,fx,x,y,w,h)
  elseif key=="geq" then draw_geq_insert(tr,fx,x,y,w,h)
  elseif key=="fet" then draw_fet_insert(tr,fx,x,y,w,h)
  else draw_opto_insert(tr,fx,x,y,w,h) end
end

function draw_reverb_effect_page(busn,tr,fx,x,y,w,h)
  screen_frame(x,y,w,h,busn==13 and "EFFECTS / PLATE REVERB" or "EFFECTS / HALL REVERB")
  local cream={0.74,0.71,0.63}; local cream2={0.58,0.55,0.48}; local led={0.95,0.12,0.08}
  rect(x+14,y+53,w-28,h-66,cream,true); rect(x+14,y+53,w-28,h-66,C.edge,false)
  rect(x+24,y+64,w-48,42,{0.035,0.025,0.022},true); rect(x+24,y+64,w-48,42,cream2,false)

  local defs={
    {"PRE DEL",{"initial","pre-delay","predelay"},{}},
    {"DECAY",{"decay","room size","room"},{}},
    {"SIZE",{"size","stereo width","width"},{"room"}},
    {"DAMP",{"damp"},{}},
    {"DIFF",{"diff","lowpass","highpass"},{}},
    {"LEVEL",{"wet"},{"dry"}}
  }
  local params={}
  for i,d in ipairs(defs) do params[i]=fx_param_by_names(tr,fx,d[2],d[3]) end
  local sw=(w-60)/6
  for i,d in ipairs(defs) do
    local sx=x+28+(i-1)*sw
    centered(sx,y+77,sw,d[1],10,led)
    fx_vertical_slider(tr,fx,params[i],sx+5,y+132,sw-10,125,"",C.amber)
  end
  local presets={"HALL","AMBIENCE","PLATE","ROOM","CHAMBER","CONCERT"}
  local pw=(w-42)/6
  for i,nm in ipairs(presets) do
    local px=x+21+(i-1)*pw
    local on=(busn==13 and nm=="PLATE") or (busn==14 and nm=="HALL")
    rect(px,y+h-45,pw-2,30,on and {0.35,0.31,0.24} or cream2,true); rect(px,y+h-45,pw-2,30,C.edge,false)
    centered(px,y+h-36,pw-2,nm,8,on and C.white or C.dim)
  end
end

function draw_delay_effect_page(tr,fx,x,y,w,h)
  screen_frame(x,y,w,h,"EFFECTS / ONE-SHOT PING PONG DELAY")
  if fx<0 then centered(x,y+170,w,"The Live32 delay engine is not installed. Run Live32 Launcher once so the Live32 FX library is installed.",11,C.red); return end
  local tm=select(1,reaper.TrackFX_GetParam(tr,fx,0))
  local e1=select(1,reaper.TrackFX_GetParam(tr,fx,1))
  local e2=select(1,reaper.TrackFX_GetParam(tr,fx,2))
  local lvl=select(1,reaper.TrackFX_GetParam(tr,fx,3))
  fx_vertical_slider(tr,fx,0,x+74,y+104,82,142,"TIME",C.orange)
  fx_vertical_slider(tr,fx,1,x+170,y+104,70,142,"PING",C.orange)
  fx_vertical_slider(tr,fx,2,x+252,y+104,70,142,"PONG",C.orange)
  fx_vertical_slider(tr,fx,3,x+334,y+104,70,142,"LEVEL",C.orange)

  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local tcx=x+470; local tcy=y+154
  circle(tcx,tcy,34,C.black,true); circle(tcx,tcy,34,C.orange,false); circle(tcx,tcy,28,{0.12,0.08,0.05},true)
  centered(tcx-34,tcy-8,68,"TAP",14,C.orange)
  if inside(gfx.mouse_x,gfx.mouse_y,tcx-36,tcy-36,72,72) and click then
    local now=reaper.time_precise()
    if last_delay_tap then
      local dt=now-last_delay_tap
      if dt>=0.08 and dt<=1.5 then reaper.TrackFX_SetParam(tr,fx,0,dt*1000) end
    end
    last_delay_tap=now
  end
  tm=select(1,reaper.TrackFX_GetParam(tr,fx,0))
  centered(x+20,y+278,w-40,string.format("%.0f ms   •   %.1f BPM   •   PING → PONG → STOP",tm,60000/math.max(tm,1)),11,C.amber)
  centered(x+20,y+306,w-40,"No feedback: one echo on the first side, one on the opposite side, then silence.",9,C.dim)
end

function draw_chorus_effect_page(tr,fx,x,y,w,h)
  screen_frame(x,y,w,h,"EFFECTS / CHORUS")
  if fx<0 then centered(x,y+170,w,"Stock chorus effect was not found on BUS 16.",11,C.red); return end
  local defs={{"RATE",{"rate","speed"}},{"DEPTH",{"depth"}},{"MIX",{"wet","mix"}},{"LEVEL",{"output","level"}}}
  local sw=(w-70)/4
  for i,d in ipairs(defs) do
    local p=fx_param_by_names(tr,fx,d[2],{})
    fx_vertical_slider(tr,fx,p,x+28+(i-1)*sw,y+112,sw-12,150,d[1],C.blue)
  end
  centered(x+20,y+300,w-40,"BUS 16 • CHORUS • stereo return FX 7/8",11,C.blue)
end

function draw_lcd_effects(x,y,w,h)
  local tr=control_track()
  if control_is_dca() then
    draw_lcd_insert(nil,x,y,w,h)
    return
  end
  local dedicated=control_is_bus() and selected_bus>=13 and selected_bus<=16
  if not dedicated then
    draw_lcd_insert(tr,x,y,w,h)
    return
  end

  -- BUS 13-16 are the four dedicated Live32 FX engines. On the M32-style
  -- workflow their processing slot is already occupied, so there is no second
  -- generic INSERT choice here: EFFECTS opens the engine directly.
  effects_subpage="engine"
  local busn=selected_bus
  local btr=buses[busn]
  local fx=effect_fx_for_bus(busn)
  if busn==13 or busn==14 then draw_reverb_effect_page(busn,btr,fx,x,y,w,h)
  elseif busn==15 then draw_delay_effect_page(btr,fx,x,y,w,h)
  else draw_chorus_effect_page(btr,fx,x,y,w,h) end
end


function draw_lcd_meters(tr,x,y,w,h)
  screen_frame(x,y,w,h,"METERS")
  local mx=x+18; local my=y+60
  for i=1,8 do
    local str,kind,idx=source_track_for_slot(i)
    local xx=mx+(i-1)*46
    meter(xx,my,13,h-95,str)
    local lab=kind=="FX" and ("F"..idx) or string.format("%02d",idx)
    local on=(meter_focus=="source" and selected_kind==kind and selected==idx)
    centered(xx-10,my+h-80,34,lab,9,on and C.blue or C.dim)
  end
  local otr,olab
  if meter_focus=="master" then otr=master; olab="MAIN"
  elseif meter_focus=="matrix" then otr=matrices[selected_matrix]; olab=string.format("M%02d",selected_matrix)
  elseif meter_focus=="bus" then otr=buses[selected_bus]; olab=string.format("B%02d",selected_bus)
  else otr=selected_track(); olab=selected_prefix() end
  meter(x+w-48,my,15,h-95,otr); centered(x+w-62,my+h-80,44,olab,9,C.blue)
end

function monitor_knob(id,cx,cy,r,label,key,minv,maxv,default,fmt)
  local val=tonumber(monitor_get(key,tostring(default))) or default
  val=clamp(val,minv,maxv)
  local n=(val-minv)/(maxv-minv)
  local a1=math.rad(135); local a2=math.rad(405)
  for i=0,10 do
    local a=a1+(a2-a1)*(i/10)
    local active=i/10<=n+0.001
    local c=active and C.amber or {0.22,0.20,0.12}
    line(cx+math.cos(a)*(r+5),cy+math.sin(a)*(r+5),cx+math.cos(a)*(r+11),cy+math.sin(a)*(r+11),c,active and 3 or 1)
  end
  circle(cx,cy,r,{0.76,0.77,0.79},true); circle(cx,cy,r,C.white,false)
  circle(cx,cy,r-3,{0.17,0.18,0.19},true); circle(cx,cy,r-4,{0.48,0.49,0.51},false)
  circle(cx,cy,r-9,C.black,true)
  local pa=a1+(a2-a1)*n
  line(cx,cy,cx+math.cos(pa)*(r-12),cy+math.sin(pa)*(r-12),C.white,2)
  centered(cx-r-36,cy+r+13,(r+36)*2,label,9,C.text)
  centered(cx-r-42,cy+r+29,(r+42)*2,fmt(val),9,C.amber)
  local hit=inside(gfx.mouse_x,gfx.mouse_y,cx-r-12,cy-r-12,(r+12)*2,(r+12)*2)
  local left=(gfx.mouse_cap&1)==1; local newleft=left and (prev_mouse&1)==0
  local shift=(gfx.mouse_cap&8)==8
  if newleft and hit and not active_knob then active_knob={id=id,start_y=gfx.mouse_y,start_n=n} end
  if active_knob and active_knob.id==id and left then
    local sens=shift and 800 or 180
    local nn=clamp(active_knob.start_n+(active_knob.start_y-gfx.mouse_y)/sens,0,1)
    local nv=minv+nn*(maxv-minv)
    monitor_set(key,string.format('%.4f',nv)); update_monitor_solo_routing()
  end
end

function monitor_checkbox(x,y,label,key,default)
  local on=monitor_get_bool(key,default)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  rect(x,y,13,13,on and C.orange or C.panel2,true); rect(x,y,13,13,on and C.white or C.edge,false)
  if on then line(x+3,y+7,x+6,y+10,C.black,2); line(x+6,y+10,x+11,y+3,C.black,2) end
  text(x+20,y-1,label,9,on and C.white or C.dim)
  if click and inside(gfx.mouse_x,gfx.mouse_y,x,y,160,16) then
    monitor_set(key,on and '0' or '1'); update_monitor_solo_routing()
  end
end

function draw_lcd_monitor(tr,x,y,w,h)
  screen_frame(x,y,w,h,'MONITOR')
  local solo_count,solo_label,solo_mode=monitor_solo_summary()
  -- Monitor meter on the left, similar to the M32 monitor page.
  local mx=x+18; local my=y+62; local mh=182
  meter(mx,my,12,mh,monitor); meter(mx+20,my,12,mh,monitor)
  centered(mx-3,my+mh+8,38,'L   R',8,C.dim)
  monitor_knob('mon_level',x+52,y+286,26,'MONITOR LEVEL','LIVE32_MON_LEVEL_DB',-60,10,0,function(v)return fmt_db(v)..' dB' end)

  text(x+72,y+61,'SOLO OPTIONS',11,C.blue)
  monitor_checkbox(x+76,y+87,'Select Follows Solo','LIVE32_MON_SELECT_FOLLOWS',false)
  monitor_checkbox(x+76,y+112,'Ch Solo AFL','LIVE32_MON_CH_AFL',false)
  monitor_checkbox(x+76,y+137,'MixBus Solo AFL','LIVE32_MON_BUS_AFL',true)
  monitor_checkbox(x+76,y+162,'DCA Solo AFL','LIVE32_MON_DCA_AFL',true)
  monitor_checkbox(x+76,y+187,'Use DIM for PFL','LIVE32_MON_DIM_PFL',false)
  monitor_checkbox(x+76,y+212,'Use Master Fader','LIVE32_MON_MASTER_FADER',false)

  monitor_knob('mon_dim',x+300,y+119,24,'DIM ATTENUATION','LIVE32_MON_DIM_DB',-40,0,-20,function(v)return fmt_db(v)..' dB' end)

  local src=monitor_get('LIVE32_MON_SOURCE','MAIN')
  text(x+366,y+62,'MONITOR SOURCE',10,C.blue)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local opts={{'OFF','OFF'},{'LR BUS','MAIN'}}
  for i,o in ipairs(opts) do
    local yy=y+84+(i-1)*28
    local on=src==o[2]
    rect(x+366,yy,94,22,on and C.orange or C.panel2,true); rect(x+366,yy,94,22,on and C.white or C.edge,false)
    centered(x+366,yy+5,94,o[1],9,on and C.black or C.text)
    if click and inside(gfx.mouse_x,gfx.mouse_y,x+366,yy,94,22) then monitor_set('LIVE32_MON_SOURCE',o[2]); update_monitor_solo_routing() end
  end
  text(x+366,y+151,'SOLO BUS',9,C.dim)
  centered(x+366,y+169,94,solo_count>0 and solo_mode or 'IDLE',14,solo_count>0 and C.amber or C.dim)
  centered(x+342,y+197,132,solo_label,8,solo_count>0 and C.white or C.dim)

  -- A dedicated routing warning makes it obvious why a PFL may be silent.
  local hw=tonumber(get_ext(monitor,'LIVE32_HW_OUT') or '-1') or -1
  if hw<0 then
    centered(x+330,y+239,140,'MONITOR OUTPUT UNASSIGNED',8,C.red)
    centered(x+330,y+255,140,'Set it on ROUTING page',8,C.dim)
  else
    centered(x+330,y+241,140,'MONITOR OUTPUT: '..hw_route_label(hw,true,false),8,C.green)
  end
  centered(x+84,y+h-27,w-100,'PFL/AFL behaviour is selected here; SOLO keys remain simple.',9,C.dim)
end

-- Hardware output patching ----------------------------------------------------------
function hw_output_names()
  local out={}
  for i=0,63 do
    local name=reaper.GetOutputChannelName(i)
    if not name or name=='' then break end
    out[#out+1]=name
  end
  return out
end
function hw_route_value(tr)
  if not tr then return -1 end
  local v=get_ext(tr,'LIVE32_HW_OUT')
  if v=='' then return -1 end
  return tonumber(v) or -1
end
function remove_live32_hw_sends(tr)
  if not tr then return end
  for i=reaper.GetTrackNumSends(tr,1)-1,0,-1 do reaper.RemoveTrackSend(tr,1,i) end
end
function apply_hw_route(tr,idx,stereo,is_main)
  if not tr then return end
  remove_live32_hw_sends(tr)
  set_ext(tr,'LIVE32_HW_OUT',tostring(idx or -1))
  if is_main then reaper.SetMediaTrackInfo_Value(tr,'B_MAINSEND',(idx or -1)<0 and 1 or 0) end
  if (idx or -1)>=0 then
    local si=reaper.CreateTrackSend(tr,nil)
    if si>=0 then
      reaper.SetTrackSendInfo_Value(tr,1,si,'D_VOL',1.0)
      reaper.SetTrackSendInfo_Value(tr,1,si,'D_PAN',0.0)
      reaper.SetTrackSendInfo_Value(tr,1,si,'I_SENDMODE',0)
      reaper.SetTrackSendInfo_Value(tr,1,si,'I_SRCCHAN',0)
      reaper.SetTrackSendInfo_Value(tr,1,si,'I_DSTCHAN',stereo and idx or (idx|1024))
    end
  end
end
function hw_route_label(idx,stereo,is_main)
  if idx<0 then return is_main and 'REAPER MASTER' or 'UNASSIGNED' end
  local outs=hw_output_names()
  if stereo then
    local a=outs[idx+1] or ('OUT '..(idx+1)); local b=outs[idx+2] or ('OUT '..(idx+2))
    return string.format('%d/%d  %s / %s',idx+1,idx+2,a,b)
  end
  return string.format('%d  %s',idx+1,outs[idx+1] or ('OUT '..(idx+1)))
end
function cycle_hw_route(tr,stereo,is_main,delta)
  local outs=hw_output_names(); local choices={-1}
  if stereo then
    local i=0; while i+1<#outs do choices[#choices+1]=i; i=i+2 end
  else
    for i=0,#outs-1 do choices[#choices+1]=i end
  end
  local cur=hw_route_value(tr); local pos=1
  for i,v in ipairs(choices) do if v==cur then pos=i break end end
  pos=pos+delta; if pos<1 then pos=#choices elseif pos>#choices then pos=1 end
  apply_hw_route(tr,choices[pos],stereo,is_main)
end
function routing_selector(x,y,w,label,tr,stereo,is_main)
  text(x,y,label,9,C.dim)
  local v=hw_route_value(tr)
  rect(x,y+14,w,28,C.panel2,true); rect(x,y+14,w,28,C.edge,false)
  centered(x+26,y+21,w-52,hw_route_label(v,stereo,is_main),8,C.white)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if button(x,y+14,24,28,'<',false,C.blue,C.panel2) and click then cycle_hw_route(tr,stereo,is_main,-1) end
  if button(x+w-24,y+14,24,28,'>',false,C.blue,C.panel2) and click then cycle_hw_route(tr,stereo,is_main,1) end
end

function draw_lcd_routing(tr,x,y,w,h)
  screen_frame(x,y,w,h,'ROUTING / OUTPUT PATCH')
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local tabs={{'MAIN/MON',1},{'BUS 1-8',2},{'BUS 9-16',3},{'MTX 1-8',4}}
  local tw=108
  for i,t in ipairs(tabs) do
    if button(x+14+(i-1)*(tw+5),y+42,tw,24,t[1],route_page==t[2],C.blue) and click then route_page=t[2] end
  end
  if route_page==1 then
    routing_selector(x+28,y+91,w-56,'FOH - MAIN LR',master,true,true)
    routing_selector(x+28,y+161,w-56,'ENGINEER MONITOR / SOLO',monitor,true,false)
    text(x+28,y+230,'FOH remains independent from the Solo bus.',9,C.green)
    text(x+28,y+249,'For true PFL/AFL operation, patch MONITOR to a different hardware pair.',9,C.dim)
  else
    local first=route_page==2 and 1 or (route_page==3 and 9 or 1)
    local arr=(route_page==4) and matrices or buses
    local prefix=(route_page==4) and 'MTX' or 'BUS'
    local yy=y+80
    for row=0,7 do
      local n=first+row; local obj=arr[n]
      local role=(prefix=='BUS' and bus_role_name(n)) or nil
      text(x+20,yy+row*31,string.format('%s %02d%s',prefix,n,role and (' - '..role) or ''),8,C.text)
      local bx=x+122; local bw=w-142
      local v=hw_route_value(obj)
      rect(bx,yy-4+row*31,bw,24,C.panel2,true); rect(bx,yy-4+row*31,bw,24,C.edge,false)
      centered(bx+24,yy+1+row*31,bw-48,hw_route_label(v,false,false),8,v>=0 and C.green or C.dim)
      if button(bx,yy-4+row*31,22,24,'<',false,C.blue,C.panel2) and click then cycle_hw_route(obj,false,false,-1) end
      if button(bx+bw-22,yy-4+row*31,22,24,'>',false,C.blue,C.panel2) and click then cycle_hw_route(obj,false,false,1) end
    end
  end
end

function draw_lcd_setup(tr,x,y,w,h)
  screen_frame(x,y,w,h,"SETUP / SCRIBBLE STRIP")
  if control_is_matrix() then
    centered(x+20,y+130,w-40,"Select an input, FX return, mix bus, DCA or Main LR",13,C.amber)
    centered(x+20,y+155,w-40,"to edit its scribble strip.",11,C.dim)
    return
  end

  if setup_editing and setup_target and setup_target~=tr then
    setup_editing=false; setup_target=nil
  end
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local label=track_display_label(tr)
  local col=scribble_color(tr)

  text(x+18,y+55,"SCRIBBLE STRIP PREVIEW",10,C.dim)
  rect(x+18,y+73,w-36,54,col,true); rect(x+18,y+73,w-36,54,C.edge,false)
  centered(x+18,y+82,w-36,control_prefix(),12,C.white)
  centered(x+18,y+103,w-36,label,13,C.white)

  text(x+18,y+145,"NAME",10,C.dim)
  local fx=x+18; local fy=y+162; local fw=w-36; local fh=37
  rect(fx,fy,fw,fh,{0.025,0.035,0.042},true)
  rect(fx,fy,fw,fh,setup_editing and setup_target==tr and C.amber or C.edge,false)
  local shown=(setup_editing and setup_target==tr) and (setup_buffer.."|") or label
  text(fx+10,fy+10,shown,13,C.white)
  if inside(gfx.mouse_x,gfx.mouse_y,fx,fy,fw,fh) and click then
    setup_target=tr; setup_buffer=label; setup_editing=true
  end

  if button(x+18,y+207,112,25,"DEFAULT NAME",false,C.blue,C.panel2) and click then
    set_custom_label(tr,""); setup_editing=false; setup_target=nil
  end
  text(x+145,y+213,"Click name, type, press Enter",9,C.dim)

  text(x+18,y+248,"COLOUR",10,C.dim)
  local keys={"blue","purple","cyan","green","yellow","orange","red","pink"}
  local names={"BLUE","PURPLE","CYAN","GREEN","YELLOW","ORANGE","RED","PINK"}
  local bw=48; local gap=8; local bx=x+18; local by=y+267
  local current=scribble_key(tr)
  for i,k in ipairs(keys) do
    local xx=bx+(i-1)*(bw+gap)
    rect(xx,by,bw,32,SCRIBBLE_COLORS[k],true)
    rect(xx,by,bw,32,current==k and C.white or C.edge,false)
    if current==k then circle(xx+bw-7,by+7,3,C.white,true) end
    if inside(gfx.mouse_x,gfx.mouse_y,xx,by,bw,32) and click then set_scribble_key(tr,k) end
    centered(xx-4,by+37,bw+8,names[i],7,C.dim)
  end
  if button(x+18,y+324,112,24,"DEFAULT COLOUR",false,C.blue,C.panel2) and click then set_scribble_key(tr,nil) end
  local def=default_scribble_key(tr):upper()
  text(x+145,y+330,"Default: "..def,9,C.dim)
end

function draw_lcd_scenes(x,y,w,h)
  screen_frame(x,y,w,h,"LIBRARY / SCENES")
  centered(x+12,y+43,w-24,"8 full-console snapshots • Recall Safe objects are skipped",9,C.dim)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local colw=(w-34)/2; local rowh=58
  for slot=1,8 do
    local col=(slot-1)//4; local row=(slot-1)%4
    local rx=x+12+col*(colw+10); local ry=y+67+row*rowh
    local exists=scene_exists(slot)
    rect(rx,ry,colw,rowh-6,{0.065,0.082,0.092},true); rect(rx,ry,colw,rowh-6,exists and C.blue or C.edge,false)
    text(rx+8,ry+7,string.format("SCENE %d",slot),11,exists and C.white or C.dim)
    local ok,meta=reaper.GetProjExtState(0,scene_section(slot),"META")
    text(rx+8,ry+25,exists and (meta or "SAVED") or "EMPTY",7,exists and C.dim or C.edge)
    local bw=52; local bh=22
    if button(rx+colw-112,ry+15,bw,bh,"SAVE",false,C.blue,C.panel2) and click then scene_save(slot) end
    if button(rx+colw-56,ry+15,bw,bh,"RECALL",exists,C.orange,C.panel2) and click and exists then scene_recall(slot) end
  end
  if scene_status~="" and reaper.time_precise()-scene_status_time<4 then
    centered(x+12,y+h-31,w-24,scene_status,11,C.amber)
  else
    centered(x+12,y+h-31,w-24,"Use SAFE on HOME to exclude critical channels from recall.",9,C.dim)
  end
end

function draw_lcd_dca_home(tr,x,y,w,h)
  screen_frame(x,y,w,h,"DCA / GROUP OVERVIEW")
  local members=dca_member_count(selected_dca)
  local col=scribble_color(tr)
  rect(x+18,y+55,w-36,58,col,true); rect(x+18,y+55,w-36,58,C.edge,false)
  centered(x+18,y+66,w-36,string.format("DCA %02d",selected_dca),12,C.white)
  centered(x+18,y+88,w-36,track_display_label(tr),14,C.white)
  centered(x+18,y+132,w-36,string.format("%d MEMBER%s",members,members==1 and "" or "S"),12,C.amber)

  local db=track_db(tr)
  centered(x+18,y+166,w-36,"VCA MASTER",10,C.dim)
  centered(x+18,y+184,w-36,fmt_db(db).." dB",20,C.white)

  local mute=reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5
  local solo=dca_solo_active(selected_dca)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if button(x+86,y+225,120,34,"MUTE",mute,C.red) and click then reaper.SetTrackUIMute(tr,mute and 0 or 1,0) end
  if button(x+w-206,y+225,120,34,"SOLO",solo,C.yellow) and click then set_dca_solo_active(selected_dca,not solo) end

  centered(x+18,y+285,w-36,"Use SETUP to rename this DCA and choose its scribble-strip colour.",10,C.dim)
end

function draw_lcd(tr,x,y,w,h)
  if screen_page=="scenes" then draw_lcd_scenes(x,y,w,h)
  elseif screen_page=="monitor" then draw_lcd_monitor(tr,x,y,w,h)
  elseif screen_page=="routing" then draw_lcd_routing(tr,x,y,w,h)
  elseif screen_page=="meters" then draw_lcd_meters(tr,x,y,w,h)
  elseif control_is_dca() and screen_page~="setup" then draw_lcd_dca_home(tr,x,y,w,h)
  elseif screen_page=="setup" then draw_lcd_setup(tr,x,y,w,h)
  elseif screen_page=="effects" then draw_lcd_effects(x,y,w,h)
  elseif screen_page=="preamp" then draw_lcd_preamp(tr,x,y,w,h)
  elseif screen_page=="gate" then draw_lcd_gate(tr,x,y,w,h)
  elseif screen_page=="dyn" then draw_lcd_dyn(tr,x,y,w,h)
  elseif screen_page=="eq" then draw_lcd_eq(tr,x,y,w,h)
  elseif screen_page=="sends" then draw_lcd_sends(tr,x,y,w,h)
  else draw_lcd_home(tr,x,y,w,h) end
end

function draw_lcd_side_buttons(x,y)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local items={{"HOME","home"},{"METERS","meters"},{"ROUTING","routing"},{"MONITOR","monitor"},{"SETUP","setup"},{"LIBRARY","scenes"},{"EFFECTS","effects"}}
  for i,it in ipairs(items) do
    local yy=y+(i-1)*48
    local on=it[2] and screen_page==it[2]
    if button(x,yy,78,34,it[1],on,C.blue) and click and it[2] then
      screen_page=it[2]
      if it[2]~="setup" then setup_editing=false; setup_target=nil end
      -- EFFECTS edits the currently selected FX bus; opening the page must not
      -- silently change selection away from a channel, DCA, matrix or master.
      if it[2]=="effects" then
        if control_is_bus() and selected_bus>=13 and selected_bus<=16 then
          sof_focus="bus"; effects_subpage="engine"
        else
          effects_subpage="insert"
        end
      end
    end
  end
end

function draw_surface_bus_master(tr,x,y,w,h)
  local teal={0.055,0.105,0.115}
  rect(x,y,w,h,teal,true); rect(x,y,w,h,C.edge,false)
  centered(x,y+10,w,"BUS MASTER",12,C.text)
  centered(x,y+55,w,string.format("BUS %02d",selected_bus),18,C.blue)
  local role=bus_role_name(selected_bus)
  centered(x,y+84,w,role or "MIX BUS",12,role and C.orange or C.white)
  centered(x,y+132,w,"FADER",9,C.dim)
  centered(x,y+150,w,fmt_db(track_db(tr)).." dB",12,C.amber)
  centered(x,y+194,w,"EQ / DYN",9,C.dim)
  centered(x,y+212,w,"AVAILABLE",10,C.white)
  if role then
    centered(x,y+254,w,"FX ENGINE",9,C.dim)
    centered(x,y+271,w,role,11,C.orange)
  end
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  if role then
    if round_button(x+w/2,y+h-32,17,"FX",screen_page=="effects" and effects_subpage=="engine",C.orange) and click then screen_page="effects"; effects_subpage="engine" end
  else
    view_button(x+w/2,y+h-31,17,"home")
  end
end

function draw_surface_matrix_master(tr,x,y,w,h)
  local teal={0.055,0.105,0.115}
  rect(x,y,w,h,teal,true); rect(x,y,w,h,C.edge,false)
  centered(x,y+10,w,"MATRIX OUT",12,C.text)
  centered(x,y+55,w,string.format("MTX %02d",selected_matrix),18,C.blue)
  centered(x,y+92,w,"OUTPUT",11,C.white)
  centered(x,y+132,w,"FADER",9,C.dim)
  centered(x,y+150,w,fmt_db(track_db(tr)).." dB",12,C.amber)
  centered(x,y+194,w,"EQ / DYN",9,C.dim)
  centered(x,y+212,w,"AVAILABLE",10,C.white)
  centered(x,y+260,w,"NO MAIN LR",9,C.dim)
  view_button(x+w/2,y+h-31,17,"home")
end

function draw_transport()
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local state=reaper.GetPlayState()
  local playing=(state&1)==1
  local paused=(state&2)==2
  local recording=(state&4)==4
  local looping=reaper.GetSetRepeat(-1)==1

  local function icon_button(x,y,w,h,kind,on,oncolor)
    local fill=on and (oncolor or C.blue) or C.panel2
    rect(x,y,w,h,fill,true); rect(x,y,w,h,on and (oncolor or C.blue) or C.edge,false)
    local ic=on and C.black or C.text
    local cx=x+w/2; local cy=y+h/2
    setc(ic)
    if kind=="rtz" then
      rect(cx-9,cy-7,2,14,ic,true)
      gfx.triangle(cx-6,cy,cx+5,cy-7,cx+5,cy+7)
    elseif kind=="stop" then
      rect(cx-6,cy-6,12,12,ic,true)
    elseif kind=="play" then
      gfx.triangle(cx-6,cy-8,cx+8,cy,cx-6,cy+8)
    elseif kind=="pause" then
      rect(cx-7,cy-8,5,16,ic,true); rect(cx+2,cy-8,5,16,ic,true)
    elseif kind=="rec" then
      circle(cx,cy,7,ic,true)
    elseif kind=="loop" then
      draw_arc(cx,cy,8,math.rad(35),math.rad(315),ic,2,18)
      line(cx+5,cy-7,cx+10,cy-7,ic,2); line(cx+10,cy-7,cx+9,cy-2,ic,2)
    end
    return inside(gfx.mouse_x,gfx.mouse_y,x,y,w,h)
  end

  local x=589; local y=25; local w=34; local h=27; local gap=5
  local kinds={"rtz","stop","play","pause","rec","loop"}
  local active={false,not playing and not paused and not recording,playing and not recording,paused,recording,looping}
  local colors={C.blue,C.blue,C.green,C.yellow,C.red,C.blue}
  for i=1,#kinds do
    local xx=x+(i-1)*(w+gap)
    if icon_button(xx,y,w,h,kinds[i],active[i],colors[i]) and click then
      if i==1 then reaper.SetEditCurPos(0,true,true)
      elseif i==2 then reaper.OnStopButton()
      elseif i==3 then reaper.OnPlayButton()
      elseif i==4 then reaper.OnPauseButton()
      elseif i==5 then reaper.CSurf_OnRecord()
      elseif i==6 then reaper.GetSetRepeat(looping and 0 or 1) end
    end
  end
end

function draw_surface_master_status(tr,x,y,w,h)
  local teal={0.055,0.105,0.115}
  rect(x,y,w,h,teal,true); rect(x,y,w,h,C.edge,false)
  centered(x,y+12,w,"MAIN LR MASTER",12,C.text)
  centered(x,y+58,w,track_display_label(tr),16,C.orange)
  centered(x,y+102,w,"FADER",9,C.dim)
  centered(x,y+120,w,fmt_db(track_db(tr)).." dB",14,C.white)
  centered(x,y+164,w,"MASTER DSP",9,C.dim)
  centered(x,y+184,w,getp(tr,10)>=0.5 and "EQ ACTIVE" or "EQ READY",10,getp(tr,10)>=0.5 and C.orange or C.dim)
  centered(x,y+204,w,getp(tr,23)>=0.5 and "DYN ACTIVE" or "DYN READY",10,getp(tr,23)>=0.5 and C.orange or C.dim)
  centered(x,y+254,w,"SETUP",9,C.dim)
  centered(x,y+270,w,"Name + Colour",9,C.white)
  centered(x,y+310,w,"Select MAIN LR below",8,C.dim)
end

function draw_live32_logo(x,y,w)
  -- Independent Live32 branding for the public release.
  local silver={0.82,0.84,0.85}
  local cyan={0.30,0.68,0.98}
  local cx=x+17; local cy=y+13
  circle(cx,cy,10,silver,false)
  line(cx-5,cy,cx+5,cy,silver,2)
  line(cx,cy-5,cx,cy+5,silver,2)
  gfx.setfont(1,"Arial Black",20)
  setc(silver)
  gfx.x=x+35; gfx.y=y+1; gfx.drawstr("LIVE")
  gfx.setfont(1,"Arial Black",20)
  setc(cyan)
  gfx.x=x+88; gfx.y=y+1; gfx.drawstr("32")
  gfx.setfont(1,"Arial",8)
  setc(C.dim)
  gfx.x=x+128; gfx.y=y+10; gfx.drawstr("VIRTUAL LIVE CONSOLE")
end

function draw_selected_channel()
  local tr=control_track()
  enforce_stereo_link_pan(tr)
  rect(18,18,W-36,420,C.shell,true)
  rect(18,18,W-36,420,C.edge,false)
  text(32,28,"SELECTED  "..control_prefix(),20,C.blue)
  text(255,31,control_name(),15,C.text)
  draw_transport()
  -- Logo sits above the LCD, clear of the transport controls and SOF status.
  draw_live32_logo(862,25,290)
  local sof_label="MAIN LR"
  if control_is_master() then sof_label="MAIN LR MASTER"
  elseif control_is_dca() then sof_label="DCA / VCA"
  elseif sof then sof_label=sof_focus=="bus" and (string.format("TO BUS %02d",selected_bus)) or (selected_prefix().." → BUS") end
  centered(W-240,31,210,sof_label,14,sof and C.orange or (control_is_dca() and C.amber or (control_is_master() and C.orange or C.dim)))

  if control_is_dca() then
    rect(30,62,727,354,C.panel,true); rect(30,62,727,354,C.edge,false)
    centered(30,80,727,"DCA CONTROL GROUP",15,C.amber)
    centered(30,118,727,track_display_label(tr),22,C.white)
    centered(30,156,727,string.format("%d MEMBER%s",dca_member_count(selected_dca),dca_member_count(selected_dca)==1 and "" or "S"),13,C.dim)
    centered(30,205,727,"VCA MASTER",10,C.dim)
    centered(30,226,727,fmt_db(track_db(tr)).." dB",24,C.amber)
    centered(30,286,727,"Use HOME for group status • SETUP for name and colour",11,C.dim)
    draw_lcd(tr,765,62,485,354)
    draw_lcd_side_buttons(1260,77)
    draw_meter_bridge(1345,62,77,354)
    return
  end

  draw_surface_preamp(tr,30,62,180,118)
  draw_surface_gate(tr,30,186,180,112)
  draw_surface_dyn(tr,30,304,180,112)
  draw_surface_eq(tr,226,62,285,354)

  if control_is_master() then
    -- MAIN LR can feed all eight matrices just like a mix bus.
    draw_surface_matrix_sends(tr,523,62,134,354)
  elseif control_is_matrix() then
    draw_surface_matrix_master(tr,523,62,134,354)
  elseif control_is_bus() then
    -- On the M32, selecting a mix bus turns this hardware into Matrix sends.
    draw_surface_matrix_sends(tr,523,62,134,354)
  else
    draw_surface_bus_sends(tr,523,62,134,354)
  end

  -- MAIN BUS applies to inputs/FX and buses. MAIN LR uses the second column as
  -- a compact master-output status while the first column becomes Matrix Sends.
  if control_is_master() then
    local teal={0.055,0.105,0.115}
    rect(665,62,92,354,teal,true); rect(665,62,92,354,C.edge,false)
    centered(665,76,92,"MASTER",11,C.text)
    centered(669,142,84,"MAIN LR",11,C.orange)
    centered(669,174,84,"FADER",8,C.dim)
    centered(669,190,84,fmt_db(track_db(tr)),10,C.white)
    centered(669,230,84,"MATRIX",8,C.dim)
    centered(669,246,84,"SEND SOURCE",8,C.green)
  elseif control_is_matrix() then
    local teal={0.055,0.105,0.115}
    rect(665,62,92,354,teal,true); rect(665,62,92,354,C.edge,false)
    centered(665,76,92,"OUTPUT",11,C.text)
    centered(669,170,84,"MATRIX",10,C.blue)
    centered(669,190,84,"INDEPENDENT",8,C.dim)
    centered(669,225,84,"Route this",8,C.dim)
    centered(669,239,84,"REAPER track",8,C.dim)
    centered(669,253,84,"to hardware",8,C.dim)
  else
    draw_surface_main_bus(tr,665,62,92,354)
  end

  draw_lcd(tr,765,62,485,354)
  draw_lcd_side_buttons(1260,77)
  draw_meter_bridge(1345,62,77,354)
end

function fader_y_from_db(db,y,h)
  local n
  if db <= -60 then n=0
  elseif db < -10 then n=(db+60)/50*0.65
  else n=0.65 + (db+10)/20*0.35 end
  return y+h-(n*h)
end
function db_from_fader_y(my,y,h)
  local n=clamp((y+h-my)/h,0,1)
  if n<0.65 then return -60+(n/0.65)*50 end
  return -10+((n-0.65)/0.35)*20
end

function lcd(x,y,w,h,line1,line2,selected_on,bg_override)
  local bg=bg_override or (selected_on and C.blue2 or {0.07,0.17,0.24})
  rect(x,y,w,h,bg,true)
  rect(x,y,w,h,selected_on and C.blue or C.edge,false)
  -- Make the custom scribble-strip name the visual priority.
  centered(x,y+3,w,line1,7,C.white)
  local fs=14
  gfx.setfont(1,"Arial",fs)
  while fs>10 and gfx.measurestr(line2 or "")>w-6 do
    fs=fs-1
    gfx.setfont(1,"Arial",fs)
  end
  centered(x,y+15,w,line2,fs,C.white)
end

function strip_button(x,y,w,h,label,on,oncolor)
  rect(x,y,w,h,on and (oncolor or C.orange) or C.panel2,true)
  rect(x,y,w,h,on and (oncolor or C.orange) or C.edge,false)
  centered(x,y+math.floor((h-10)/2)-1,w,label,9,on and C.black or C.text)
  return inside(gfx.mouse_x,gfx.mouse_y,x,y,w,h)
end


-- Compact M32-style lower-strip status section: SEL at the top, a small
-- segmented meter with real COMP/CLIP/GATE activity indicators, SOLO, scribble strip, MUTE,
-- then the long-throw fader. This deliberately keeps the scribble display
-- between SOLO and MUTE like the physical console.
function strip_status_led(x,y,label,on,color)
  rect(x,y,6,4,on and (color or C.amber) or {0.12,0.10,0.05},true)
  text(x+9,y-3,label,6,on and (color or C.amber) or C.dim)
end

function strip_mini_meter(tr,x,y,w,h,status_mode,member_count,pre_on)
  rect(x,y,w,h,C.black,true)
  rect(x,y,w,h,C.edge2,false)
  local levels={-48,-36,-24,-18,-12,-6,-3,0}
  local pdb=-150
  local lit=0
  if member_count~=nil then
    lit=math.min(#levels,math.max(0,math.ceil(member_count/2)))
  else
    local peak=math.max(reaper.Track_GetPeakInfo(tr,0),reaper.Track_GetPeakInfo(tr,1))
    pdb=lin2db(peak)
    for i,db in ipairs(levels) do if pdb>=db then lit=i end end
  end
  local seggap=2
  local segh=(h-(#levels-1)*seggap)/#levels
  for i=1,#levels do
    local yy=y+h-i*segh-(i-1)*seggap
    local active=i<=lit
    local c
    if member_count~=nil then c=active and C.amber or {0.13,0.09,0.02}
    elseif i>=8 then c=active and C.red or {0.15,0.035,0.035}
    elseif i>=6 then c=active and C.yellow or {0.13,0.10,0.025}
    else c=active and C.green or {0.025,0.11,0.045} end
    rect(x+1,yy,w-2,math.max(2,segh-1),c,true)
  end
  if status_mode=="channel" or status_mode=="output" then
    -- Hidden JSFX telemetry: param 46 = actual compressor GR, param 47 = gate-closed activity.
    -- These indicators therefore show activity, not merely whether the processors are enabled.
    local comp_active=getp(tr,46)>0.25
    strip_status_led(x-19,y+1,'COMP',comp_active,C.amber)
    strip_status_led(x-19,y+13,'CLIP',pdb>-0.3,C.red)
    if status_mode=="channel" then
      local gate_closed=getp(tr,47)>0.5
      strip_status_led(x-19,y+h-5,'GATE',gate_closed,C.green)
    else
      strip_status_led(x-19,y+h-5,'PRE',pre_on==true,C.orange)
    end
  elseif member_count~=nil then
    text(x-20,y+3,'MEM',6,C.dim)
    centered(x-22,y+h-13,20,tostring(member_count),7,C.amber)
  end
  return pdb
end

function strip_fader_cap(cx,cy,accent)
  rect(cx-17,cy-10,34,20,{0.20,0.21,0.22},true)
  rect(cx-17,cy-10,34,20,accent or C.edge,false)
  line(cx-13,cy,cx+13,cy,C.white,1)
  circle(cx,cy,5,{0.72,0.74,0.75},true)
  circle(cx,cy,3,{0.45,0.48,0.50},true)
end

function strip_fader_scale(x,y,h,db,accent)
  local railx=x+31
  rect(railx-2,y,4,h,C.black,true)
  local marks={10,5,0,-5,-10,-20,-30,-40,-50,-60}
  for _,m in ipairs(marks) do
    local yy=fader_y_from_db(m,y,h)
    local major=(m==10 or m==0 or m==-10 or m==-20 or m==-40 or m==-60)
    line(railx-(major and 16 or 10),yy,railx-5,yy,C.edge,1)
    line(railx+5,yy,railx+(major and 15 or 10),yy,C.edge,1)
    if major then text(railx+17,yy-4,tostring(m),5,C.dim) end
  end
  local ky=fader_y_from_db(db,y,h)
  strip_fader_cap(railx,ky,accent)
  return railx,ky
end

function draw_source_strip(slot,x,y,w,h)
  local tr,kind,idx=source_track_for_slot(slot)
  if not tr then return end
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local is_selected=(meter_focus=="source" and selected_kind==kind and selected==idx)
  rect(x,y,w,h,is_selected and C.panel2 or C.panel,true)
  rect(x,y,w,h,is_selected and C.blue or C.edge,false)

  -- SELECT
  if round_button(x+w/2,y+17,10,"SEL",is_selected,C.blue) and click then
    selected_kind=kind; selected=idx; sof_focus="source"; meter_focus="source"
  end

  -- Compact channel meter / processing status.
  strip_mini_meter(tr,x+29,y+37,8,73,"channel",nil,false)

  -- SOLO
  local solo=monitor_solo_on(tr)
  if round_button(x+w/2,y+126,11,"SOLO",solo,C.yellow) and click then set_track_solo(tr,not solo) end

  -- Scribble strip between SOLO and MUTE.
  local _,nm=reaper.GetTrackName(tr,"")
  local title=kind=="FX" and string.format("FX %02d",idx) or string.format("CH %02d",idx)
  local subtitle=track_display_label(tr)
  if kind=="CH" and stereo_link_on(tr) then subtitle="LINK "..subtitle end
  lcd(x+3,y+145,w-6,42,title,subtitle,is_selected,scribble_color(tr))

  -- MUTE. In SUB GROUP SOF mode this key becomes membership:
  -- red = not assigned; releasing it joins the selected subgroup at unity.
  local subgroup_assign=(sof and sof_focus=="bus" and bus_is_subgroup(selected_bus))
  if subgroup_assign then
    local member=subgroup_member(tr,selected_bus)
    if round_button(x+w/2,y+207,11,"MUTE",not member,C.red) and click then
      set_subgroup_member(tr,selected_bus,not member)
    end
  else
    local mute=reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5
    if round_button(x+w/2,y+207,11,"MUTE",mute,C.red) and click then set_track_mute(tr,not mute) end
  end

  -- A subgroup send is fixed at unity, so in assignment mode the fader remains
  -- the source channel fader while the MUTE key handles membership.
  local fy=y+237; local fh=h-258
  local db
  if subgroup_assign then db=track_db(tr)
  elseif sof and sof_focus=="bus" then db=send_db(tr,selected_bus)
  else db=track_db(tr) end
  local railx=strip_fader_scale(x,fy,fh,db,C.white)
  if subgroup_assign then
    local member=subgroup_member(tr,selected_bus)
    centered(x,y+h-17,w,member and "IN GROUP" or "MUTED",7,member and C.orange or C.red)
  else
    centered(x,y+h-17,w,fmt_db(db),8,C.dim)
  end
  if (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,railx-22,fy-12,44,fh+24) and not active_knob then
    local ndb=db_from_fader_y(gfx.mouse_y,fy,fh)
    if subgroup_assign then set_track_db(tr,ndb)
    elseif sof and sof_focus=="bus" then set_send_db(tr,selected_bus,ndb)
    else set_track_db(tr,ndb) end
  end
end

function draw_bus_strip(busn,x,y,w,h)
  local tr=buses[busn]
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local is_selected=(meter_focus=="bus" and selected_bus==busn)
  local flipped=(sof and sof_focus=="source")
  rect(x,y,w,h,is_selected and {0.095,0.12,0.14} or C.panel,true)
  rect(x,y,w,h,is_selected and C.blue or (flipped and C.orange or C.edge),false)

  if round_button(x+w/2,y+17,10,"SEL",is_selected,C.blue) and click then
    selected_bus=busn; bus_bank=math.floor((busn-1)/4)+1; sof_focus="bus"; meter_focus="bus"
  end
  local tap=bus_tap_mode(busn)
  local pre=(tap=="PRE_EQ" or tap=="POST_EQ" or tap=="PRE_FADER")
  strip_mini_meter(tr,x+29,y+37,8,73,"output",nil,pre)

  local solo=monitor_solo_on(tr)
  if round_button(x+w/2,y+126,11,"SOLO",solo,C.yellow) and click then set_track_solo(tr,not solo) end

  local subtitle=flipped and (selected_prefix().." SEND") or track_display_label(tr)
  if stereo_link_on(tr) and not flipped and custom_label(tr)=="" then subtitle="LINK "..subtitle end
  lcd(x+3,y+145,w-6,42,string.format("BUS %02d",busn),subtitle,is_selected,scribble_color(tr))

  local mute=reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5
  if round_button(x+w/2,y+207,11,"MUTE",mute,C.red) and click then set_track_mute(tr,not mute) end

  local fy=y+237; local fh=h-258
  local db=flipped and send_db(selected_track(),busn) or track_db(tr)
  local railx=strip_fader_scale(x,fy,fh,db,flipped and C.orange or C.blue)
  local send_group=flipped and bus_is_subgroup(busn)
  centered(x,y+h-17,w,send_group and (db>-90 and "ON" or "OFF") or fmt_db(db),8,send_group and C.orange or (flipped and C.amber or C.dim))
  if (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,railx-22,fy-12,44,fh+24) and not active_knob then
    local ndb=db_from_fader_y(gfx.mouse_y,fy,fh)
    if flipped then set_send_db(selected_track(),busn,ndb) else set_track_db(tr,ndb) end
  end
end

function draw_matrix_strip(matrixn,x,y,w,h)
  local tr=matrices[matrixn]
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local is_selected=(meter_focus=="matrix" and selected_matrix==matrixn)
  rect(x,y,w,h,is_selected and {0.095,0.12,0.14} or C.panel,true)
  rect(x,y,w,h,is_selected and C.blue or C.edge,false)

  if round_button(x+w/2,y+17,10,"SEL",is_selected,C.blue) and click then
    selected_matrix=matrixn; matrix_bank=math.floor((matrixn-1)/4)+1; meter_focus="matrix"
  end
  strip_mini_meter(tr,x+29,y+37,8,73,"output",nil,false)
  local solo=monitor_solo_on(tr)
  if round_button(x+w/2,y+126,11,"SOLO",solo,C.yellow) and click then set_track_solo(tr,not solo) end
  lcd(x+3,y+145,w-6,42,string.format("MTX %02d",matrixn),track_display_label(tr),is_selected,scribble_color(tr))
  local mute=reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5
  if round_button(x+w/2,y+207,11,"MUTE",mute,C.red) and click then reaper.SetMediaTrackInfo_Value(tr,"B_MUTE",mute and 0 or 1) end

  local fy=y+237; local fh=h-258; local db=track_db(tr)
  local railx=strip_fader_scale(x,fy,fh,db,C.green)
  centered(x,y+h-17,w,fmt_db(db),8,C.dim)
  if (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,railx-22,fy-12,44,fh+24) and not active_knob then
    set_track_db(tr,db_from_fader_y(gfx.mouse_y,fy,fh))
  end
end

function draw_dca_strip(dcan,x,y,w,h)
  local tr=dcas[dcan]
  if not tr then return end
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local is_selected=(meter_focus=="dca" and selected_dca==dcan)
  local members=dca_member_count(dcan)
  rect(x,y,w,h,is_selected and {0.095,0.12,0.14} or C.panel,true)
  rect(x,y,w,h,is_selected and C.blue or C.edge,false)

  if round_button(x+w/2,y+17,10,"SEL",is_selected,C.blue) and click then
    selected_dca=dcan; meter_focus="dca"; setup_editing=false; setup_target=nil
  end
  strip_mini_meter(tr,x+29,y+37,8,73,nil,members,false)
  local solo=dca_solo_active(dcan)
  if round_button(x+w/2,y+126,11,"SOLO",solo,C.yellow) and click then set_dca_solo_active(dcan,not solo) end
  lcd(x+3,y+145,w-6,42,string.format("DCA %02d",dcan),track_display_label(tr),is_selected,scribble_color(tr))
  local mute=reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5
  if round_button(x+w/2,y+207,11,"MUTE",mute,C.red) and click then reaper.SetTrackUIMute(tr,mute and 0 or 1,0) end

  local fy=y+237; local fh=h-258; local db=track_db(tr)
  local railx=strip_fader_scale(x,fy,fh,db,C.amber)
  centered(x,y+h-29,w,string.format("%d MEM",members),7,C.dim)
  centered(x,y+h-17,w,fmt_db(db),8,C.amber)
  if (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,railx-22,fy-12,44,fh+24) and not active_knob then
    local ndb=db_from_fader_y(gfx.mouse_y,fy,fh)
    reaper.SetTrackUIVolume(tr,ndb<=-90 and 0.0 or db2lin(ndb),false,true,0)
  end
end

function draw_master_strip(x,y,w,h)
  local tr=master
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  local is_selected=(meter_focus=="master")
  rect(x,y,w,h,is_selected and C.panel2 or C.panel,true)
  rect(x,y,w,h,is_selected and C.blue or C.orange,false)

  if round_button(x+w/2,y+17,10,"SEL",is_selected,C.blue) and click then
    meter_focus="master"; setup_editing=false; setup_target=nil
  end
  -- M32-style master strip: the compact meter position is used for CLEAR SOLO.
  local solos_active=(select(1,monitor_solo_summary())>0)
  if round_button(x+w/2,y+70,17,"CLR",solos_active,C.yellow) and click then clear_all_solos() end
  centered(x,y+91,w,"SOLO",7,solos_active and C.yellow or C.dim)
  centered(x,y+121,w,"MAIN",7,C.orange)
  lcd(x+4,y+145,w-8,42,"MAIN LR",track_display_label(tr),is_selected,scribble_color(tr))
  local mute=reaper.GetMediaTrackInfo_Value(tr,"B_MUTE")>0.5
  if round_button(x+w/2,y+207,11,"MUTE",mute,C.red) and click then reaper.SetMediaTrackInfo_Value(tr,"B_MUTE",mute and 0 or 1) end

  local fy=y+237; local fh=h-258; local db=track_db(tr)
  local railx=strip_fader_scale(x+4,fy,fh,db,C.orange)
  centered(x,y+h-17,w,fmt_db(db),8,C.amber)
  if (gfx.mouse_cap&1)==1 and inside(gfx.mouse_x,gfx.mouse_y,railx-22,fy-12,44,fh+24) and not active_knob then
    set_track_db(tr,db_from_fader_y(gfx.mouse_y,fy,fh))
  end
end

function draw_layer_panel(x,y,w,h)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  rect(x,y,w,h,C.shell,true); rect(x,y,w,h,C.edge,false)
  centered(x,y+10,w,"INPUT",10,C.text)
  centered(x,y+24,w,"LAYERS",9,C.dim)
  local items={{1,"1-8"},{2,"9-16"},{3,"17-24"},{4,"25-32"},{5,"FX"}}
  for i,item in ipairs(items) do
    local yy=y+54+(i-1)*55
    if strip_button(x+7,yy,w-14,34,item[2],source_layer==item[1],C.blue) and click then source_layer=item[1] end
  end
end

function draw_bus_layer_panel(x,y,w,h)
  local click=(gfx.mouse_cap&1)==1 and (prev_mouse&1)==0
  rect(x,y,w,h,C.shell,true); rect(x,y,w,h,C.edge,false)
  centered(x,y+10,w,"OUTPUT",10,C.text)
  centered(x,y+24,w,"LAYERS",9,C.dim)
  if strip_button(x+6,y+51,w-12,32,"DCA 1-8",bus_fader_layer==4,C.amber) and click then
    bus_fader_layer=4
  end
  if strip_button(x+6,y+89,w-12,32,"BUS 1-8",bus_fader_layer==1,C.blue) and click then
    bus_fader_layer=1
    if selected_bus>8 then selected_bus=1; bus_bank=1 end
  end
  if strip_button(x+6,y+127,w-12,32,"BUS 9-16",bus_fader_layer==2,C.blue) and click then
    bus_fader_layer=2
    if selected_bus<9 then selected_bus=9; bus_bank=3 end
  end
  if strip_button(x+6,y+165,w-12,32,"MTX 1-8",bus_fader_layer==3,C.green) and click then
    bus_fader_layer=3
  end

  centered(x,y+214,w,"SENDS",8,C.dim)
  centered(x,y+227,w,"ON FADERS",8,C.dim)
  if round_button(x+w/2,y+258,20,"SOF",sof,C.orange) and click then sof=not sof end

  if sof then
    centered(x,y+291,w,sof_focus=="bus" and "TO BUS" or "FROM",8,C.dim)
    if sof_focus=="bus" then centered(x,y+307,w,string.format("BUS %02d",selected_bus),10,C.amber)
    else centered(x,y+307,w,selected_prefix(),10,C.amber) end
  else
    centered(x,y+300,w,"SOF OFF",9,C.dim)
  end

  if bus_fader_layer==4 then
    centered(x,y+h-50,w,"DCA",7,C.amber)
    centered(x,y+h-38,w,"VCA",7,C.dim)
    centered(x,y+h-26,w,"GROUPS",7,C.dim)
  else
    centered(x,y+h-50,w,"BUS SEL",7,C.dim)
    centered(x,y+h-38,w,"→ MATRIX",7,C.green)
    centered(x,y+h-26,w,"SENDS",7,C.dim)
  end
end

function draw_console_lower()
  if sof then
    rect(18,447,1390,36,C.orange,true)
    if sof_focus=="bus" then
      if bus_is_subgroup(selected_bus) then
        centered(18,456,1390,"SUB GROUP ASSIGN — BUS "..string.format("%02d",selected_bus).." — UNMUTE A SOURCE TO JOIN",15,C.black)
      else
        centered(18,456,1390,"SENDS ON FADERS — CHANNELS → BUS "..string.format("%02d",selected_bus),15,C.black)
      end
    else
      centered(18,456,1390,"SENDS ON FADERS — "..selected_prefix().." → BUSES",15,C.black)
    end
  else
    rect(18,447,1390,36,C.shell,true); rect(18,447,1390,36,C.edge,false)
    text(28,456,"INPUT / FX FADERS",13,C.dim)
    local bank_title=bus_fader_layer==3 and "MATRIX OUTPUT FADERS" or (bus_fader_layer==4 and "DCA FADERS" or "MIX BUS FADERS")
    local bank_color=bus_fader_layer==3 and C.green or (bus_fader_layer==4 and C.amber or C.dim)
    centered(650,456,720,bank_title,13,bank_color)
    text(1320,456,"MAIN",13,C.orange)
  end

  local sy=491; local sh=425; local sw=64; local gap=4
  local layerx=18; local layerw=70
  draw_layer_panel(layerx,sy,layerw,sh)

  local sx=94
  for slot=1,8 do draw_source_strip(slot,sx+(slot-1)*(sw+gap),sy,sw,sh) end

  local buslayerx=646; local buslayerw=70
  draw_bus_layer_panel(buslayerx,sy,buslayerw,sh)

  local bx=722
  if bus_fader_layer==3 then
    for slot=1,8 do draw_matrix_strip(slot,bx+(slot-1)*(sw+gap),sy,sw,sh) end
  elseif bus_fader_layer==4 then
    for slot=1,8 do draw_dca_strip(slot,bx+(slot-1)*(sw+gap),sy,sw,sh) end
  else
    local firstbus=(bus_fader_layer-1)*8+1
    for slot=1,8 do draw_bus_strip(firstbus+slot-1,bx+(slot-1)*(sw+gap),sy,sw,sh) end
  end

  draw_master_strip(1276,sy,72,sh)
end

function draw()
  enforce_fx_return_pans()
  enforce_all_stereo_link_pans()
  update_rta_focus()
  rect(0,0,gfx.w,gfx.h,C.bg,true)
  draw_selected_channel()
  draw_console_lower()
  text(1220,918,"Live32 v1.2.1",11,C.dim)
  text(32,918,"Esc closes",11,C.dim)
end

function loop()
  draw()
  gfx.update()
  local ch=gfx.getchar()
  if ch<0 then return end
  if setup_editing then
    if ch==13 then
      if setup_target then set_custom_label(setup_target,setup_buffer:sub(1,13)) end
      setup_editing=false; setup_target=nil
    elseif ch==27 then
      setup_editing=false; setup_target=nil
    elseif ch==8 or ch==127 then
      setup_buffer=setup_buffer:sub(1,math.max(0,#setup_buffer-1))
    elseif ch>=32 and ch<=126 and #setup_buffer<13 then
      setup_buffer=setup_buffer..string.char(ch)
    end
  elseif ch==27 then return end
  if (gfx.mouse_cap&1)==0 then active_knob=nil end
  prev_mouse=gfx.mouse_cap
  reaper.defer(loop)
end

-- Bring older v0.9.x linked projects up to the stronger stereo-link
-- semantics as soon as the console opens: odd side becomes the authoritative state.
sync_existing_stereo_links()

function Live32_RTA_Cleanup()
  if rta_active_track then
    local fx=rta_fxidx(rta_active_track)
    if fx>=0 then reaper.TrackFX_SetParam(rta_active_track,fx,0,0) end
  end
end
reaper.atexit(Live32_RTA_Cleanup)


-- Enforce the project-persistent bus preconfiguration whenever the console opens.
for i=1,32 do if channels[i] then reaper.SetMediaTrackInfo_Value(channels[i],"I_NCHAN",math.max(8,reaper.GetMediaTrackInfo_Value(channels[i],"I_NCHAN") or 2)) end end
for i=1,8 do if fxreturns[i] then reaper.SetMediaTrackInfo_Value(fxreturns[i],"I_NCHAN",math.max(8,reaper.GetMediaTrackInfo_Value(fxreturns[i],"I_NCHAN") or 2)) end end
apply_all_bus_tap_modes()
update_monitor_solo_routing()
gfx.init("Live32 v1.2.1 — Virtual Live Console",W,H,0)
loop()
