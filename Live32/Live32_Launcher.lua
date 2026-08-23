-- Live32 v1.2.0 Launcher
-- Front door for new consoles, existing multitracks and training templates.

local VERSION="1.2.0"
local W,H=860,600
local running=true
local prev_mouse=0
local _,script_file=reaper.get_action_context()
local function dirname(path) return path:match("^(.*)[/\\]") or "." end
local DIR=dirname(script_file)
local SEP=package.config:sub(1,1)
local SETUP=DIR..SEP.."Live32_Setup.lua"
local CONSOLE=DIR..SEP.."Live32_Console.lua"

local C={
  bg={0.025,0.028,0.032}, shell={0.060,0.066,0.073}, panel={0.085,0.094,0.103},
  panel2={0.110,0.121,0.132}, edge={0.25,0.28,0.31}, text={0.92,0.93,0.94},
  dim={0.53,0.57,0.60}, blue={0.27,0.59,0.98}, cyan={0.13,0.73,0.83},
  amber={1.00,0.66,0.13}, green={0.18,0.78,0.39}, purple={0.60,0.28,0.78},
  red={0.88,0.22,0.22}, black={0.012,0.014,0.016}, white={1,1,1}
}
local function setc(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,fill) setc(c); gfx.rect(x,y,w,h,fill==false and 0 or 1) end
local function line(x1,y1,x2,y2,c,w) setc(c); gfx.line(x1,y1,x2,y2,w or 1) end
local function text(x,y,s,size,c) gfx.setfont(1,"Arial",size or 14); setc(c or C.text); gfx.x=x; gfx.y=y; gfx.drawstr(s) end
local function centered(x,y,w,s,size,c) gfx.setfont(1,"Arial",size or 14); local tw=gfx.measurestr(s); text(x+(w-tw)/2,y,s,size,c) end
local function inside(mx,my,x,y,w,h) return mx>=x and mx<=x+w and my>=y and my<=y+h end
local function click_now() return (gfx.mouse_cap&1)==1 and (prev_mouse&1)==0 end

local function role(tr)
  local _,v=reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_ROLE","",false)
  return v or ""
end
local function live32_state()
  local count=0
  local required={CH=0,FXRTN=0,BUS=0,MATRIX=0,DCA=0,MUTEGRP=0,MAIN=0,MONITOR=0}
  for i=0,reaper.CountTracks(0)-1 do
    local r=role(reaper.GetTrack(0,i))
    if r~="" then
      count=count+1
      if r:match("^CH%d+$") then required.CH=required.CH+1
      elseif r:match("^FXRTN%d+$") then required.FXRTN=required.FXRTN+1
      elseif r:match("^BUS%d+$") then required.BUS=required.BUS+1
      elseif r:match("^MATRIX%d+$") then required.MATRIX=required.MATRIX+1
      elseif r:match("^DCA%d+$") then required.DCA=required.DCA+1
      elseif r:match("^MUTEGRP%d+$") then required.MUTEGRP=required.MUTEGRP+1
      elseif r=="MAIN" then required.MAIN=1
      elseif r=="MONITOR" then required.MONITOR=1 end
    end
  end
  local ready=required.CH>=32 and required.FXRTN>=8 and required.BUS>=16 and required.MATRIX>=8 and required.DCA>=8 and required.MUTEGRP>=6 and required.MAIN==1 and required.MONITOR==1
  return count,ready,required
end

local function selected_or_media_tracks()
  local out={}
  local nsel=reaper.CountSelectedTracks(0)
  if nsel>0 then
    for i=0,math.min(nsel,32)-1 do
      local tr=reaper.GetSelectedTrack(0,i)
      if tr and role(tr)=="" then out[#out+1]=tr end
    end
  else
    for i=0,reaper.CountTracks(0)-1 do
      local tr=reaper.GetTrack(0,i)
      if role(tr)=="" and reaper.CountTrackMediaItems(tr)>0 then
        out[#out+1]=tr
        if #out>=32 then break end
      end
    end
  end
  return out
end

local function launch_console()
  if not io.open(CONSOLE,"rb") then reaper.ShowMessageBox("Live32_Console.lua was not found beside the Launcher.","Live32",0); return end
  running=false; gfx.quit(); dofile(CONSOLE)
end

local function call_setup(mode,tracks,keepfx)
  _G.LIVE32_SETUP_MODE=mode
  _G.LIVE32_ATTACH_TRACKS=tracks or {}
  _G.LIVE32_ATTACH_KEEP_FX=(keepfx~=false)
  local ok,err=pcall(dofile,SETUP)
  _G.LIVE32_SETUP_MODE=nil; _G.LIVE32_ATTACH_TRACKS=nil; _G.LIVE32_ATTACH_KEEP_FX=nil
  if not ok then reaper.ShowMessageBox("Live32 Setup stopped:\n\n"..tostring(err),"Live32 v"..VERSION,0); return false end
  local _,ready=live32_state()
  return ready
end

local function repair_project()
  local count,ready,r=live32_state()
  if ready then launch_console(); return end
  if count==0 then return end
  local prompt=string.format(
    "This looks like an older or incomplete Live32 project.\n\n"..
    "Found: %d/32 inputs, %d/8 FX returns, %d/16 buses, %d/8 matrices, %d/8 DCAs, %d/6 mute groups, MAIN %s, MONITOR %s.\n\n"..
    "REPAIR will keep the existing Live32 tracks, media, fader levels and existing send levels, then add only the missing Live32 infrastructure and required routing.\n\nContinue?",
    r.CH,r.FXRTN,r.BUS,r.MATRIX,r.DCA,r.MUTEGRP,r.MAIN==1 and "OK" or "MISSING",r.MONITOR==1 and "OK" or "MISSING")
  if reaper.ShowMessageBox(prompt,"Live32 — Repair Project",1)~=1 then return end
  if call_setup("repair",{},true) then launch_console() end
end

local function new_console()
  local count=select(1,live32_state())
  if count>0 then launch_console(); return end
  if reaper.CountTracks(0)>0 then
    reaper.ShowMessageBox("This project already contains tracks.\n\nUse ATTACH PROJECT to keep the existing tracks, or IMPORT MULTITRACK for a clean Live32 copy.","Live32 v"..VERSION,0)
    return
  end
  if call_setup("new",{},true) then launch_console() end
end

local function attach_project()
  local count=select(1,live32_state())
  if count>0 then reaper.ShowMessageBox("This project already contains Live32.\n\nOpen the console instead.","Live32",0); return end
  local tracks=selected_or_media_tracks()
  if #tracks==0 then
    reaper.ShowMessageBox("No multitrack sources were found.\n\nSelect up to 32 tracks first, or make sure the project contains media items.","Live32 — Attach Project",0)
    return
  end
  local prompt=string.format("Attach %d existing track%s as Live32 CH 1–%d?\n\nThe media, automation, names and track plug-ins stay on those tracks. Live32 processing is inserted before the existing FX.\n\nYES = keep existing track FX active\nNO = bypass existing track FX\nCANCEL = do nothing\n\nExisting sends are preserved, so IMPORT is safer for an already-complex mix.",#tracks,#tracks==1 and "" or "s",#tracks)
  local r=reaper.ShowMessageBox(prompt,"Live32 — Attach Existing Project",3)
  if r==2 then return end
  local keepfx=(r==6)
  if call_setup("attach",tracks,keepfx) then launch_console() end
end

local function clone_items(src,dst)
  for i=0,reaper.CountTrackMediaItems(src)-1 do
    local item=reaper.GetTrackMediaItem(src,i)
    local ok,chunk=reaper.GetItemStateChunk(item,"",false)
    if ok and chunk and chunk~="" then
      -- Let REAPER create fresh item/take GUIDs for the imported copy.
      chunk=chunk:gsub("\nGUID%s+{[^}]+}","")
      chunk=chunk:gsub("\nIGUID%s+{[^}]+}","")
      local ni=reaper.AddMediaItemToTrack(dst)
      reaper.SetItemStateChunk(ni,chunk,true)
    end
  end
end
local function find_live_channel(n)
  for i=0,reaper.CountTracks(0)-1 do
    local tr=reaper.GetTrack(0,i)
    if role(tr)=="CH"..n then return tr end
  end
end

local function inherit_scribble_colour(src,dst)
  if not reaper.ColorFromNative then return end
  local native=reaper.GetMediaTrackInfo_Value(src,"I_CUSTOMCOLOR") or 0
  if native<=0 then return end
  local r,g,b=reaper.ColorFromNative(native)
  local palette={
    blue={20,59,122}, purple={110,33,145}, cyan={15,87,102}, green={20,87,46},
    yellow={107,87,13}, orange={117,59,13}, red={107,20,20}, pink={110,26,71}
  }
  local best,bestd="blue",1e99
  for k,c in pairs(palette) do
    local d=(r-c[1])^2+(g-c[2])^2+(b-c[3])^2
    if d<bestd then best,bestd=k,d end
  end
  reaper.GetSetMediaTrackInfo_String(dst,"P_EXT:LIVE32_COLOR",best,true)
end

local function import_multitrack()
  local count=select(1,live32_state())
  if count>0 then reaper.ShowMessageBox("This project already contains Live32.\n\nOpen the console instead.","Live32",0); return end
  local src=selected_or_media_tracks()
  if #src==0 then
    reaper.ShowMessageBox("No source tracks were found.\n\nSelect up to 32 multitrack tracks first, or make sure the project contains media items.","Live32 — Import Multitrack",0)
    return
  end
  local r=reaper.ShowMessageBox(string.format("Import %d track%s into a fresh Live32 console?\n\nLive32 will COPY the media items to new Live32 channels. The original tracks are kept, muted and hidden — nothing is deleted.\n\nTrack FX and track automation are intentionally not copied, giving you a clean virtual-soundcheck mix.\n\nContinue?",#src,#src==1 and "" or "s"),"Live32 — Import Multitrack",1)
  if r~=1 then return end
  if not call_setup("attach",{},true) then return end
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  for i,tr in ipairs(src) do
    local dst=find_live_channel(i)
    if dst then
      local _,nm=reaper.GetTrackName(tr,"")
      nm=(nm and nm~="") and nm or string.format("INPUT %02d",i)
      reaper.GetSetMediaTrackInfo_String(dst,"P_EXT:LIVE32_LABEL",nm,true)
      local col=reaper.GetMediaTrackInfo_Value(tr,"I_CUSTOMCOLOR")
      if col and col>0 then reaper.SetMediaTrackInfo_Value(dst,"I_CUSTOMCOLOR",col) end
      inherit_scribble_colour(tr,dst)
      clone_items(tr,dst)
      reaper.SetMediaTrackInfo_Value(tr,"B_MUTE",1)
      reaper.SetMediaTrackInfo_Value(tr,"B_SHOWINTCP",0)
      reaper.SetMediaTrackInfo_Value(tr,"B_SHOWINMIXER",0)
      reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_IMPORTED_SOURCE","1",true)
    end
  end
  reaper.PreventUIRefresh(-1); reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange()
  reaper.Undo_EndBlock("Import multitrack into Live32",-1)
  launch_console()
end

local function training_template()
  local count=select(1,live32_state())
  if count>0 then reaper.ShowMessageBox("This project already contains Live32.\n\nOpen the console instead.","Live32",0); return end
  if reaper.CountTracks(0)>0 then
    reaper.ShowMessageBox("Create the Training Template in an empty project tab.\n\nThis avoids altering the project you already have open.","Live32 — Training Template",0)
    return
  end
  if not call_setup("new",{},true) then return end
  local names={"KICK","SNARE","HAT","TOM 1","TOM 2","OH L","OH R","BASS DI","GTR L","GTR R","KEYS L","KEYS R","LEAD VOX","BV 1","BV 2","PLAYBACK"}
  local cols={"red","red","red","red","red","red","red","yellow","green","green","cyan","cyan","purple","purple","purple","blue"}
  for i,nm in ipairs(names) do
    local tr=find_live_channel(i)
    if tr then
      reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_LABEL",nm,true)
      reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_COLOR",cols[i],true)
    end
  end
  local busnames={"MON 1","MON 2","MON 3","MON 4","IEM 1","IEM 2","IEM 3","IEM 4","DRUM SUB","BAND SUB","VOX SUB","SPARE"}
  for i,nm in ipairs(busnames) do
    for t=0,reaper.CountTracks(0)-1 do
      local tr=reaper.GetTrack(0,t)
      if role(tr)=="BUS"..i then reaper.GetSetMediaTrackInfo_String(tr,"P_EXT:LIVE32_LABEL",nm,true); break end
    end
  end
  reaper.ShowMessageBox("Training template created.\n\nDrop stems onto CH 1–16 and start mixing. The first twelve buses are labelled as monitors/IEMs/subgroups and Buses 13–16 remain the four FX sends.","Live32 Training Template",0)
  launch_console()
end

local function card(x,y,w,h,title,sub,accent,enabled,action,tag)
  local hover=enabled and inside(gfx.mouse_x,gfx.mouse_y,x,y,w,h)
  rect(x,y,w,h,hover and C.panel2 or C.panel,true)
  rect(x,y,w,h,enabled and (hover and accent or C.edge) or {0.13,0.14,0.15},false)
  rect(x,y,6,h,enabled and accent or {0.13,0.14,0.15},true)
  text(x+24,y+19,title,19,enabled and C.white or C.dim)
  text(x+24,y+52,sub,11,enabled and C.dim or {0.34,0.36,0.38})
  if tag then
    local tw=92; rect(x+w-tw-17,y+18,tw,22,enabled and accent or C.edge,true)
    centered(x+w-tw-17,y+23,tw,tag,9,C.black)
  end
  if hover then centered(x+w-96,y+h-28,76,"OPEN  ›",10,accent) end
  if enabled and click_now() and hover then action() end
end

local function draw_logo(x,y)
  text(x,y,"LIVE",31,C.white); text(x+76,y,"32",31,C.blue)
  text(x,y+38,"VIRTUAL LIVE CONSOLE",10,C.dim)
end

local function draw_status(x,y,w,h)
  rect(x,y,w,h,{0.025,0.050,0.058},true); rect(x,y,w,h,C.cyan,false)
  text(x+17,y+13,"PROJECT STATUS",10,C.cyan)
  local count,ready,r=live32_state()
  if ready then
    text(x+17,y+41,"LIVE32 READY",17,C.green)
    text(x+17,y+69,"32 CH  •  16 BUS  •  8 MTX  •  8 DCA  •  MONITOR",10,C.text)
    text(x+17,y+91,"Press OPEN CONSOLE to mix.",10,C.dim)
  elseif count>0 then
    text(x+17,y+41,"OLDER / INCOMPLETE LIVE32",14,C.amber)
    text(x+17,y+66,string.format("CH %d/32  FX %d/8  BUS %d/16  MTX %d/8",r.CH,r.FXRTN,r.BUS,r.MATRIX),9,C.text)
    text(x+17,y+82,string.format("DCA %d/8  MG %d/6  MAIN %s  MON %s",r.DCA,r.MUTEGRP,r.MAIN==1 and "OK" or "MISS",r.MONITOR==1 and "OK" or "MISS"),9,C.text)
    text(x+17,y+98,"Use REPAIR below — your existing mix is kept.",8,C.dim)
  else
    local cand=selected_or_media_tracks()
    text(x+17,y+41,reaper.CountTracks(0)==0 and "EMPTY PROJECT" or "MULTITRACK DETECTED",15,reaper.CountTracks(0)==0 and C.blue or C.amber)
    if reaper.CountTracks(0)==0 then text(x+17,y+69,"Ready for a new Live32 console.",10,C.dim)
    else text(x+17,y+69,string.format("%d source track%s ready",#cand,#cand==1 and "" or "s"),10,C.text); text(x+17,y+91,"Select tracks to control the mapping order.",9,C.dim) end
  end
end

local function draw()
  rect(0,0,gfx.w,gfx.h,C.bg,true)
  rect(18,18,W-36,H-36,C.shell,true); rect(18,18,W-36,H-36,C.edge,false)
  draw_logo(42,37)
  text(42,103,"Choose how Live32 should use this REAPER project.",13,C.text)
  text(42,124,"The launcher handles the console infrastructure so REAPER can stay in the background.",10,C.dim)
  draw_status(550,35,268,105)

  local _,ready=live32_state()
  local hasLive=select(1,live32_state())>0
  local blank=reaper.CountTracks(0)==0

  if ready then
    rect(42,159,776,48,C.green,true); centered(42,174,776,"OPEN LIVE32 CONSOLE",15,C.black)
    if click_now() and inside(gfx.mouse_x,gfx.mouse_y,42,159,776,48) then launch_console() end
  elseif hasLive then
    local hov=inside(gfx.mouse_x,gfx.mouse_y,42,159,776,48)
    rect(42,159,776,48,hov and C.amber or C.panel2,true); rect(42,159,776,48,C.amber,false)
    centered(42,171,776,"REPAIR / COMPLETE LIVE32 PROJECT",14,hov and C.black or C.amber)
    centered(42,190,776,"Keeps existing channels, media and mix settings",9,hov and C.black or C.dim)
    if click_now() and hov then repair_project() end
  else
    rect(42,159,776,48,C.panel2,true); rect(42,159,776,48,C.edge,false)
    centered(42,174,776,"LIVE32 v1.2 PROJECT LAUNCHER",14,C.blue)
  end

  local enableCreate=not hasLive
  card(42,225,370,132,"NEW CONSOLE","Build a clean 32-channel Live32 desk\nin this empty project.",C.blue,enableCreate and blank,new_console,"CLEAN")
  card(448,225,370,132,"ATTACH PROJECT","Use existing tracks directly. Keeps media,\nautomation, names and optional plug-ins.",C.cyan,enableCreate and not blank,attach_project,"FAST")
  card(42,376,370,132,"IMPORT MULTITRACK","Copy media into clean Live32 channels.\nOriginal tracks remain safely muted/hidden.",C.amber,enableCreate and not blank,import_multitrack,"SAFE")
  card(448,376,370,132,"TRAINING TEMPLATE","Create a labelled live-show template ready\nfor stems, virtual soundcheck or teaching.",C.purple,enableCreate and blank,training_template,"TEACH")

  line(42,530,818,530,C.edge,1)
  text(42,546,"Tip: select tracks before ATTACH/IMPORT to set CH 1 → CH 32 order.",10,C.dim)
  text(708,546,"v"..VERSION,10,C.dim)
end

local function loop()
  draw(); gfx.update()
  local ch=gfx.getchar(); if ch==27 or ch<0 or not running then return end
  prev_mouse=gfx.mouse_cap
  reaper.defer(loop)
end

gfx.init("Live32 v"..VERSION.." — Launcher",W,H,0)
loop()
