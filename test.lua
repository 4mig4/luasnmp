local snmp = require "snmp"
local mib = snmp.mib

-- stdlib compatibility 5.0 versus 5.1
local tostring2, pretty
if _VERSION == "Lua 5.1" then
   -- 5.1: use general stdlib, here only base modules
   tostring2 = tostring
   require "base"
   pretty = prettytostring
else
   -- 5.0: use own stdlib
   require "stdlib"
end

require "logging.console"

----------------------------------------------------------------------
-- CUSTOMIZATION
-- Adopt below variables to your platform setup
-- true means yes, false means no
----------------------------------------------------------------------
-- Peers: customize!
PEER = "localhost"
--PEER = "daniel"
--PEER = "goofy"

-- User: customize!
USER = "leuwer"
PASSPHRASE = "leuwer2006"
--USER = "ronja"
--PASSPHRASE = "ronja2006"
PRIVPASSPHRASE = PASSPHRASE

-- Communities: customize!
COMMUNITY = "private"
--COMMUNITY = "public"

-- Traps: customize!
-- a) test only traps
traponly = traponly or false
informonly = informonly or false
-- b) automatic trap testing only on local machine
if PEER == "localhost" then
  trapyes = trapyes or false
--  trapyes = true
else
  trapyes = trapyes or false
end

-- c) use -d option to snmptrap command used to send trap
--trapdebug = "-d"
trapdebug = ""

-- MIB only - no SNMP access to agent: customize!
mibonly = mibonly or false

-- Versions to test: customize!
testv1 = testv1 or true
testv2 = testv2 or true
testv3 = testv3 or true

-- Encryption: customize!
encrypt = true

----------------------------------------------------------------------
-- Logging
----------------------------------------------------------------------
local loglevel = string.upper(arg[1] or "INFO")
local log = logging.console("%message")
log:setLevel(loglevel)
testpath = ""
local info = function(fmt, ...) 
	       log:info(string.format(testpath..fmt.."\n", unpack(arg))) 
	     end
local debug = function(fmt, ...) 
		log:debug(string.format(fmt.."\n", unpack(arg))) 
	      end
----------------------------------------------------------------------
-- STDLIB compatibility stuff
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Trap-sink Daemon setup
----------------------------------------------------------------------
info("Initialising SNMP")
if snmp.gettrapd() == "snmptrapd" then
  info("  You are using `%s' as trap-sink daemon. Be sure it's running!",
       snmp.gettrapd())
else
  err = snmp.inittrap("straps")
  assert(not err, err)
end

----------------------------------------------------------------------
-- Test MIB access
----------------------------------------------------------------------
local function test_mib()
  info("MIB ACCESS Test ... ")
  debug("Loading MIBS")

  -- Load a few additional mibs
  local mp = "/usr/share/mibs/ietf/"
  assert(mib.load("ATM-TC-MIB") or mib.load(mp.."ATM-TC-MIB"))
  assert(mib.load("ATM-MIB") or mib.load(mp.."ATM-MIB"))
  assert(mib.fullname("sysContact") == "iso.org.dod.internet.mgmt.mib-2.system.sysContact")
  assert(mib.oid("ifTable") == "1.3.6.1.2.1.2.2")
  local obj = "atmVccAalType"
  local oid, err = mib.oid(obj)
  assert(oid, err)

  debug("  DETAILS of '"..obj.."'")
  debug("  NAME: '" .. mib.name(oid))
  debug("  FULLNAME: '"..mib.fullname(obj).."'")
  debug("  OID: " .. mib.oid(obj))
  debug("  OIDLEN (from oid): " .. mib.oidlen(mib.oid(obj)))
  debug("  OIDLEN (from name): " .. (mib.oidlen(obj) or "nil"))
  debug("  DESCRIPTION def: \n  ==='" .. (mib.description(obj) or "nil").."'\n  ===")
  debug("  DESCRIPTION width 20: \n  ==='" .. (mib.description(obj,20) or "nil").."'\n  ===")
  debug("  DESCRIPTION width 80 buf 64: \n  ==='" .. (mib.description(obj,80,64) or "nil").."'\n  ===")
  debug("  ACCESS: " .. mib.access(obj))
  tn, ts = mib.type(obj)
  debug("  TYPE: '" .. ts .."' ["..tn.."]" )
  debug("  DEFAULT: '" .. mib.default(obj).. "'")
  debug("  ENUM: ")
  if mib.enums(obj) then 
    table.foreach(mib.enums(obj), function(k,v) debug("  "..v) end )
  end
  local poid = mib.parent(obj)
  debug("  PARENT OID: %s", poid)
  debug("  PARENT OID LEN: %d", mib.oidlen(poid))
  debug("  PARENT NAME: '%s'", mib.name(poid))
  debug("  PARENT FULLNAME: '%s'", mib.fullname(poid))
  debug("  SUCCESSOR: ")
  table.foreach(mib.successor(poid), function(k,v) 
				       debug("  "..v.."\t'".. mib.name(v).."'") 
				     end)
  info("MIB ACCESS ok.")
end


local function get(sess, name)
  local vbind, status, errix = snmp.get(sess, name)
  if vbind then
    debug("-----------------------")
    debug("value = "..vbind.value)
    debug("type = "..vbind.type)
    debug("Lua type = "..type(vbind.value))
    debug("oid = "..vbind.oid)
    debug("name = "..mib.fullname(vbind.oid))
    return vbind.value, vbind.type, vbind.oid, vbind.fullname
  else
    debug("error: %s %s", tostring(status), tostring(errix))
    return nil, status, errix
  end
end

----------------------------------------------------------------------
-- Test counter64 datatype
----------------------------------------------------------------------
local function test_counter64()
   info("COUNTER64 Test ... ")
   local cn = snmp.counter64
   local max = cn.pow(2,64)-1
   local maxt = cn.totable(max)
   debug("max = " .. tostring(max))
   assert(tostring(max) == "18446744073709551615")
   assert((cn.number(1) - 2) == max)
   assert((maxt.high == 0xffffffff) and (maxt.low == 0xffffffff))
   local mid = cn.number{high = 0, low = 0xffffffff}
   assert(mid + 1 == cn.pow(2,32))
   assert(mid < max)
   local a, b, c = cn.number(0), mid, max
   assert(b > a)
   assert(b <= mid)
   assert(cn.compare(a,b) == -1)
   assert(cn.compare(max,a) == 1)
   assert(cn.compare(mid, mid) == 0)
   local a = cn.number(123456789)
   assert(cn.tonumber(a) == 123456789)
   assert(cn.sqrt(cn.number(49)) == cn.number(7))
   local a = cn.number{high=1234, low=5678}
   local d = cn.pow(2,32)
   assert(cn.tonumber(cn.div(a, d)) == 1234)
   assert(cn.tonumber(cn.mod(a, d)) == 5678)
   x,y = cn.divmod(a, d)
   assert(x == cn.number(1234) and y == cn.number(5678))
   assert(cn.iszero(cn.number(0)))
   info("COUNTER64 ok.")

end
----------------------------------------------------------------------
-- Asynch request callback
----------------------------------------------------------------------
local function test_cb(vb, status, index, reqid, session, magic)
  debug("  DEFAULT CALLBACK with request id %d and magic '%s'", reqid, tostring(magic))
  debug("  status = %s index = %s", status or "nil", index or "nil")
  debug("  type(vb) = %s", type(vb))
  if type(magic) == "function" then magic() end
  if vb and type(vb) == "table" then
    if vb.oid then
      debug("  %s ", session.sprintvar(vb))
      debug("  value=%s", session.sprintval(vb))
    else
      for _,v in pairs(vb) do
	if v then
	  debug("  %s", session.sprintvar(v))
	  debug("  value=%s", session.sprintval(v))
	end
      end
    end    
  else
    debug("  Asynch_get with error: %s", err)
  end
end

local inform_done, trap_done = false, false

----------------------------------------------------------------------
-- Asynch inform callback
----------------------------------------------------------------------
local function inform_cb(vb, status, index, reqid, session, magic)
  debug("  DEFAULT INFORM CALLBACK: inform sent by : reqid=%d", reqid)
  debug("  status = %s index = %s", status or "nil", index or "nil")
  debug("  type(vb) = %s", type(vb))
  if vb and type(vb) == "table" then
    if vb.oid then
      debug("  %s ", session.sprintvar(vb))
      debug("  value=%s", session.sprintval(vb))
    else
      for _,v in pairs(vb) do
	if v then
	  debug("  %s", session.sprintvar(v))
	  debug("  value=%s", session.sprintval(v))
	end
      end
    end    
  else
    debug("  Asynch_get with error: %s", err)
  end
  if type(magic) == "function" then 
     debug("  magic param is a function - calling it ...")
     magic() 
  end
  inform_done = true
end

----------------------------------------------------------------------
-- Trap  callback
----------------------------------------------------------------------
local function trap_cb(vlist, ip, host, session)
  debug("  DEFAULT TRAP CALLBACK: trap sent by : %s (%s)", host, ip )
  debug("    SESSION name: '%s'", session.name)
  debug("    session version: %s", session:getversion())
  for _,vb in ipairs(vlist) do
     debug("   1 method session.sprintvar(vb): %s", session.sprintvar(vb))
--    print(pretty(vb))
     debug("   2 method tosting(vb)            %s", tostring(vb))
     debug("   3 method snmp.sprintvar2:       %s", snmp.sprintvar2(vb))
     debug("   4 method snmp.sprintval:        %s", snmp.sprintval(vb))
     debug("   5 method snmp.sprintval2:       %s", snmp.sprintval2(vb))
  end
  trap_done = true
end

----------------------------------------------------------------------
-- Test SNMP access
----------------------------------------------------------------------

----------------------------------------------------------------------
local function test_sessv1()

  info("SNMP SESSION Test")

  local sess, err = snmp.open{
    name = "sessv1",
    community = COMMUNITY, 
    peer = PEER,
    version = snmp.SNMPv1,
    callback = test_cb,
    trap = trap_cb
  }
  assert(sess, err);
  assert(type(sess) ~= "userdata")
  info("SNMP SESSION ok.")
  return sess
end

----------------------------------------------------------------------
local function test_sessv2()

  info("SNMP SESSION Test")

  local sess, err = snmp.open{
    name = "sessv2",
    community = COMMUNITY, 
    peer = PEER,
    version = snmp.SNMPv2C,
    callback = test_cb,
    inform = inform_cb,
    trap = trap_cb
  }
  assert(sess, err);
  assert(type(sess) ~= "userdata")
  info("SNMP SESSION ok.")
  return sess
end

----------------------------------------------------------------------
local function test_sessv3(encrypt)

  info("SNMP SESSION V3 Test")
  local seclevel
  if not encrypt then
    seclevel = "authNoPriv"
  else
    seclevel = "authPriv"
  end
  debug("  Using security Level: %s", seclevel)
  debug("  Using user: %s", USER)
  debug("  Using passphrase: %s", PASSPHRASE)
  local sess, err = snmp.open{
    name = "sessv3",
    version = snmp.SNMPv3,
    peer = PEER,
    user = USER,
    authPassphrase = PASSPHRASE,
    privPassphrase = PRIVPASSPHRASE,
    securityLevel = seclevel,
    authType = "MD5",
    privType = "DES",
    --    context = nil,
    --    authid = nil,
    --    contextid = nil,
    --    engboots = nil,
    --    engtime = nil,
    
    -- Callbacks
    callback = test_cb,
    inform = inform_cb,
    trap = trap_cb
  }
  assert(sess, err);
  assert(type(sess) ~= "userdata", "what is this ?")
  info("SNMP SESSION V3 ok.")
  return sess
end


----------------------------------------------------------------------
local function test_get(sess)
  info("SNMP GET ...")
  -- simple get with success
  info(" Simple get with success ...")
  local vb, err, index = snmp.get(sess, "sysORID.1")
  assert(vb, err)
  debug("  %s", snmp.sprintvar(vb))
  assert(mib.isoid(vb.value))

  -- simple get with error on client side
  info(" Simple get with error on client ...")
  local vb, err = snmp.get(sess, "whatever")
  assert(not vb)
  if not vb then 
    debug("  get with error in client: %s", err) 
  end

  -- simple get with error on server side
  info(" Simple get with error on server ...")
  local vb, err = snmp.get(sess, "1.3.6.1.2.1.999")
  assert(vb and not vb.value)
  if not vb.value then 
    debug("  get with error in server: oid=%s err=%s", vb.oid or "unknown", err or "nil") 
  end

  -- multiple get with success
  info(" Multiple get with success ...")
--  vb, err = snmp.get(sess, {"sysContact.0", "sysName.0"})
  vb, err = snmp.get(sess, {"SNMPv2-MIB::sysContact.0", "sysName.0"})
  assert(vb,err)
  for _,v in ipairs(vb) do
    debug("  %s = %s", mib.name(v.oid), tostring(v.value))
  end

  -- multiple get with error in client
  info(" Multiple get with error on client ...")
  vb, err = snmp.get(sess, {"sysContact.0", "whatever", "sysName.0"})
  assert(not vb)
  if not vb then 
    debug("  get with error: %s", err)
  else
    for _,v in ipairs(vb) do
      debug("  %s = %s", mib.name(v.oid), tostring(v.value))
    end
  end

  -- multiple get with error in client
  info(" Multiple get with only errors on client ...")
  vb, err = snmp.get(sess, {"whoknows", "whatever", "dontknow"})
  assert(not vb)
  if not vb then 
    debug("  get with error: %s", err)
  else
    for _,v in ipairs(vb) do
      debug("  %s = %s", mib.name(v.oid), tostring(v.value))
    end
  end

  -- multiple get with error in server
  info(" Multiple get with error on server ...")
  vb, err = snmp.get(sess, {"sysContact.0", "1.3.6.1.2.1.999", "sysName.0"})
  assert(vb, err)
  for _, v in ipairs(vb) do
    debug("  %s = %s", mib.name(v.oid), tostring(v.value))
  end

  -- asynchronous get with success
  info(" Asynchronous get with success ...")
  local reqid, err = snmp.asynch_get(sess, "sysContact.0")
--  local reqid = snmp.asynch_get(sess, "sysContact.0", test_cb, "here i am")
  assert(reqid, err)
  debug("  asynch_get with reqid: %d", reqid)
  snmp.wait(sess)


  -- asynchronous get with event call success
  info(" Asynchronous get with event call success ...")
  local gotone = false
  local reqid = snmp.asynch_get(sess, "sysContact.0", 
				function(...)
				  gotone = true
				  test_cb(unpack(arg))
				end, "here i am")
  debug("  asynch_get with reqid: %d", reqid)
  while not gotone do
    snmp:event()
  end

  -- several asynchronous get with success
  info(" Several asynchronous get with success ...")
  local reqid1 = snmp.asynch_get(sess, "sysContact.0", test_cb, "here i am")
  debug("  asynch_get with reqid: %d", reqid1)
  local reqid2 = snmp.asynch_get(sess, "sysName.0", test_cb, "here i am")
  debug("  asynch_get with reqid: %d", reqid2)
  snmp.wait(sess)

  -- asynchronous get with failure
  info(" Asynchronous get with error on client ...")
  reqid = snmp.asynch_get(sess, "whatever", test_cb, "here i am")
  assert(not reqid)

  -- asynchronous get with failure
  info(" Asynchronous get with error on server ...")
  local oid = "1.3.666.1.2.1.1.4.222"
  reqid = snmp.asynch_get(sess, oid, test_cb, "here i am")
  snmp.wait(sess)

  -- multiple asynchronous get with failure
  info(" Multiple asynchronous get with error on server ...")
  reqid = snmp.asynch_get(sess, 
			  {"sysContact.0", "1.3.6.1.2.1.999", "sysName.0"}, 
			  test_cb, "here i am")
  snmp.wait(sess)

  -- simple getnext with success
  info(" Simple getnext with success ...")
  local vb, err = snmp.getnext(sess, "sysORID.1")
  debug("  %s", sess.sprintvar(vb))
  debug("  %s", mib.oid("snmpMIB"))
  assert(mib.isoid(vb.value))


  --- getbulk
  if sess.version ~= snmp.SNMPv1 then
    info(" Interfaces using getbulk ...")
    local ifnum = 2
    if ifnum then
      debug("  ifnum=%d", ifnum)
      iflist=snmp.getbulk(sess,0,ifnum,{"ifDescr","ifType"})
      if iflist then
	types,err=mib.enums("ifType")
	assert(types, err)
	i = 1 last=ifnum*2
	while i < last do
	  debug("  "..iflist[i].value .. " : ".. (types[iflist[i+1].value] or "NIL"))
	  i = i + 2
	end
      end
    else
      info("  coulnd't retrieve object 'ifNumber.0'")
    end

    --- asynchronous getbulk
    info(" Interfaces using asynchronous getbulk ...")
    local ifnum = 2
    if ifnum then
      debug("  ifnum=%d", ifnum)
      local rid = sess:asynch_getbulk(0,ifnum,{"ifDescr","ifType"},
				      function(vb, stat, ix, rid, sess, magic)
					debug("  Callback with request id %d", rid)
					local iflist = vb
					if iflist then
					  types=mib.enums("ifType")
					  i = 1 last=ifnum*2
					  while i < last do
					    debug("  "..iflist[i].value .. " : ".. (types[iflist[i+1].value] or "NIL"))
					    i = i + 2
					  end
					end
				      end, "none")
      debug("  rid = %d", rid)
      snmp.wait(sess)
    else
      info("  coulnd't retrieve object 'ifNumber.0'")
    end
  else
    info("  SNMP version 1 does not support getbulk")
  end

  -- asynchronous get with success no callback
  info(" Asynchronous get with success no callback ...")
  local reqid, err = snmp.asynch_get(sess, "sysContact.0", nil, "here i am")
  if not reqid then 
    debug(err) 
  else 
    debug("  asynch_get with reqid: %d", reqid)
    sess:wait()
  end
  info("SNMP GET ok.")
end

----------------------------------------------------------------------
local function test_set(sess)
  info("SNMP SET  ...")

  --- Simple set with success
  info(" Simple set with success ...")
  local vb, err = sess:get("sysContact.0")
  assert(vb,err)
  debug("  path 1: %s", sess.sprintvar(vb))
  local oldval = vb.value
  vb, err = sess:set{oid = "sysContact.0", value="unknown"}
  assert(vb, err)
  vb = sess:get("sysContact.0")
  debug("  path 2: %s", sess.sprintvar(vb))
  debug("  path 2a: %s", snmp.sprint_variable(vb))
  debug("  path 2a: %s", snmp.sprint_variable(sess:get("sysContact.0")))
  debug("  path 2b: %s", sess:sprintvar(sess:get("sysContact.0")))
  local vb, err = sess:set{oid = "sysContact.0", type=snmp.TYPE_INTEGER32, value=oldval}
--  debug("  path 3: %s", sess.sprintvar(sess:get("sysContact.0")))
  vb, err = sess:get("sysContact.0")
  debug("  path 3: %s", sess.sprintvar(vb))

  --- Simple set with error on client
  info(" Simple set with error on client ..,")
  vb, err = sess:set{oid="sysContact.0", type="Integer32", value="root"}
  debug("  %s", sess.sprintvar(sess:get("sysContact.0")))
  if not vb then debug(err) end
  assert(not vb,err)

  --- Multiple set with success
  info(" Multiple set with success")
  debug("  %s", sess.sprintvar(sess:get("sysContact.0")))
  debug("  %s", sess.sprintvar(sess:get("sysLocation.0")))
  vb, err = sess:set{{oid="sysContact.0", value="root"},{oid="sysLocation.0", value="dddhome"}}
  debug("  %s", sess.sprintvar(sess:get("sysContact.0")))
  debug("  %s", sess.sprintvar(sess:get("sysLocation.0")))

  info("SNMP SET ok.")

end

----------------------------------------------------------------------
local function test_mib_retrieve(sess)
  -- get next test
  info("MIB TREE retrieval using getnext ...")
  local sum = 0
  local vb = {oid = "1"}
  local err
  local last = vb.oid
  repeat
    vb, err = sess:getnext (vb)
    if vb then
      sum = sum + 1
      debug(" (%3d) %s %s", sum, sess.sprintvar(vb), vb.type)
    else
      break
    end
    if vb.type ~= snmp.ENDOFMIBVIEW then
      assert(mib.oidcompare(last, vb.oid) < 0, "oid is not increasing")
    end
    last = vb.oid
  until vb.type == snmp.ENDOFMIBVIEW
  debug("  %d objects retrieved.", sum)  
  info("MIB TREE ok")
end

----------------------------------------------------------------------
local function test_meta(sess)
  info("SNMP META access ...")
  debug("  %d", sess["ifSpeed.1"])
  debug("  %s", sess["system.sysContact.0"])
  debug("  %d", sess.ifSpeed_1)
  debug("  %s", sess.sysName_0)

  debug("  1 %s", sess.sysContact_0)
  local oldval = sess.sysContact_0
  sess.sysContact_0 = "hleuwer"
  debug("  2 %s", sess.sysContact_0)
  assert(sess.sysContact_0 == "hleuwer")
  sess.sysContact_0 = oldval
  debug("  3 %s", sess.sysContact_0)
  assert(sess.sysContact_0 == oldval)
  if _VERSION == "Lua 5.1" then
     debug("   collecting (5.1)...")
     collectgarbage("collect")
  else
    collectgarbage(0)
  end
  sess.sysContact_0 = oldval
  debug("  3 %s", sess.sysContact_0)
  sess.sysContact_0 = oldval
  debug("  3 %s", sess.sysContact_0)
  sess.sysContact_0 = oldval
  debug("  3 %s", sess.sysContact_0)
  info("SNMP META ok.")
  
end

----------------------------------------------------------------------
local function test_perf(sess,n,str)
  info("PERFORMANCE ...")
  local oldval = sess.sysContact_0
  for i=1,n do
    sess[str] = "hleu"
  end
  sess.sysContact_0 = oldval
  info("PERFORMANCE o.k.")
end

----------------------------------------------------------------------
-- NOTE: This test does not work, since the session has not been configured
--       to send on trap port 162 => we need a dedicated trap session.
local function test_inform1(sess)
  info("INFORM (1) (sess sync) ...")
  local vb = sess:get("sysContact.0")
  vb, err = sess:inform("sysName.0", vb)
  assert(vb, err)
  info("INFORM (1) o.k.")
end

----------------------------------------------------------------------
local function test_inform3(sess,port)
   info("INFORM (3) (trapsess async) ...")
   local trapsess, err = snmp.open{
      name = "trapsess_async",
      community = COMMUNITY,
      peer = PEER,
      version = snmp.SNMPv2C,
      port = port,
      callback = test_cb,
      timeout = 5
   }
   assert(trapsess, err)
   local vb = sess:get("sysContact.0")
   local ok = false
   local reqid, err = trapsess:asynch_inform("sysName.0", {vb}, inform_cb, 
					     function() 
						ok = true 
					     end)
   assert(reqid, err)
   debug("  asynch inform reqid=%d", reqid)
   trapsess:wait()
   assert(ok, "failed")
   trapsess:close()
   info("INFORM (3) o.k.")
end

----------------------------------------------------------------------
local function test_inform2(sess, port)
  info("INFORM (2) (trapsess sync) ...")
  local trapsess, err = snmp.open{
     name = "trapsess_sync",
     community = COMMUNITY,
     peer = PEER,
     version = snmp.SNMPv2C,
     port = port,
     timeout = 5
  }
  assert(trapsess, err)
  local vb1 = sess:get("sysContact.0")
  local vb2 = sess:get("sysLocation.0")
  local vb, err
  vb, err = trapsess:inform("sysName.0", {vb1,vb2})
  assert(vb, err)
  for _,v in ipairs(vb) do
    debug("  %s", sess.sprintvar(v))
  end
  assert(vb[3].value == vb1.value)
  assert(vb[4].value == vb2.value)
  trapsess:close()
  info("INFORM (2) o.k.")
end

----------------------------------------------------------------------
local function test_trap(sess)
  info("TRAP ...")
  if sess.version == snmp.SNMPv1 then
    local trapcmd = "snmptrap "..trapdebug.." -v 1 -c "..COMMUNITY.." localhost:162 2 1 sysName.0 s 'hello'"
    debug("  Sending traps via %s", trapcmd)
    os.execute(trapcmd.." &")
    while trap_done == false do
      local x = snmp.event()
    end
    trap_done = false
    debug(" captured SNMP version 1 trap")
  elseif sess.version == snmp.SNMPv2c then
    local trapcmd = "snmptrap "..trapdebug.." -v 2c -c "..COMMUNITY.." localhost:162  '' 0 sysName.0 s 'hello'"
    debug("  Sending traps via %s", trapcmd)
    os.execute(trapcmd.." &")
    while trap_done == false do
      snmp.event()
    end
    trap_done = false
    debug(" captured SNMP version 2c trap")
  elseif sess.version == snmp.SNMPv3 then
    local trapcmd = "snmptrap "..trapdebug.." -e 0x0102030405 -v 3 -u ".. USER ..
      " -a MD5 -A "..PASSPHRASE.." -l authNoPriv localhost:162 '' 0 sysName.0 s hello"
    debug("  Sending traps via %s", trapcmd)
    os.execute(trapcmd.." &")
    while trap_done == false do
      snmp.event()
    end
    trap_done = false
    debug(" captured SNMP version 3 trap")
  end
  info("TRAP  o.k.")
end

----------------------------------------------------------------------
local function test_walk(sess, var)
  info("SNMP WALK ...")
  vlist, err = sess:walk(var)
  assert(vlist, err)
  local sum = 0
  for _,v in pairs(vlist) do
    sum = sum + 1
    debug("  (%3d) %s : %s", sum, v.oid, sess.sprintvar(v))
  end
  debug("  %d varbinds found", table.getn(vlist))
  info("SNMP WALK o.k.")
end

----------------------------------------------------------------------
local function test_vbindtostring(sess, skip)
  info("VBIND METATABLE ...")
  local oldval = sess.sysContact_0
  local newval = "herbert.leuwer@t-online.de"
  sess.sysContact_0 = newval
  vb, err = sess:get("sysContact.0") 
  sess.sysContact_0 = oldval
  debug("  newval = %s", tostring(vb))
  debug("  oldval = %s", tostring(sess.sysContact_0))
  if not skip then
    if sess.sprintvar == snmp.sprint_variable then
      assert(tostring(vb) == "SNMPv2-MIB::sysContact.0 = STRING: "..newval)
    else
      assert(tostring(vb) == "sysContact.0 (Integer32) = "..newval)
    end
    info("VBIND METATABLE o.k.")
--  else
--    assert(tostring(vb) == "vb = {['value'] = 'herbert.leuwer@t-online.de', ['type'] = 16, ['oid'] = '1.3.6.1.2.1.1.4.0'}")
--    debug("  %s", tostring(vb()))
  end
  if skip then return end
  local _inform = inform_cb
  if sess.version == snmp.SNMPv1 then
    _inform = nil
  end
  local newsess, err = sess:clone()
  assert(newsess, err)
--  local newsess, err = snmp.open{
--    name = "newsess",
--    community = COMMUNITY,
--    peer = PEER,
--    version = sess.version,
--    callback = nil,
--    inform = _inform,
--    trap = trap_cb,
--    sprintvar = function(vb) return "vb = "..tostring2(vb) end,
--    callvar = function(self) self.fullname = mib.fullname(self.oid) return self end
--  }
  assert(newsess, err)
  test_vbindtostring(newsess, true)
  newsess:close()
  info("VBIND METATABLE o.k.")
end

----------------------------------------------------------------------
local function test_vbindequal(sess)
  info("VBIND COMPARE ...")
  local oldval = sess:get("sysContact.0")
  sess:set{oid="sysContact.0", value="someone"}
  debug("  %s", tostring(oldval))
  local newval = sess:get("sysContact.0")
  debug("  %s", tostring(newval))
  assert(oldval ~= newval)
  if oldval.value < newval.value then
    assert(oldval < newval)
  end
  if oldval.value <= newval.value then
    assert(oldval <= newval)
  end
  sess:set(oldval)
  assert(oldval == sess:get("sysContact.0"))
  info("VBIND COMPARE o.k.")
end

----------------------------------------------------------------------
local function test_vbindconcat(sess)
  info("VBIND CONCAT ...")
  local o1, err = sess:get("sysContact.0")
  local o2, err = sess:get("sysLocation.0")
  sess:set(o1..o2..o1..o2..o2..o1)
  assert(o1 == sess:get("sysContact.0"))
  assert(o2 == sess:get("sysLocation.0"))
  info("VBIND CONCAT o.k.")
end

----------------------------------------------------------------------
local function test_vbindcreate(sess)
  info("VBIND CREATE ...")
  local o1, err = sess.sysContact_0
  vb1 = sess:newvar("sysContact.0", sess.sysContact_0)
  debug("  %s", sess.sprintvar(vb1))
  vb2 = sess:set(vb1)
  debug("  %s", sess.sprintvar(vb2))
  assert(vb1 == vb2)
  info("VBIND CREATE o.k.")
end

----------------------------------------------------------------------
local function test_misc(sess)
  info("MISCELLANOUS ...")
  debug("  sess.ifTable: %s", pretty(sess.ifTable))
  debug("  sess.ifEntry: %s", pretty(sess.ifEntry))
  info("  !!! NOTE: 'sess.ifAdEntAddr' leads to failurs in subsequent requests on WindowsXP (Cygwin) - commented out")
  --debug("  sess.ipAdEntAddr: %s", pretty(sess.ipAdEntAddr))
  debug("  sess.ifSpeed: %s", pretty(sess.ifSpeed))
  debug("  sess.ifDescr: %s", pretty(sess.ifDescr))
  local vl, err = sess:walk("ifSpeed.1")
  debug("  sess:walk('ifSpeed.1'): %s %s", pretty(vl), err or "nil")
  debug("  sess.ifSpeed.1: %s", pretty(sess.ifSpeed_1))
  debug("  sess.tcpConnState: %s", pretty(sess.tcpConnState))
  debug("  sess.nsModuleName: %s", pretty(sess.nsModuleName))
  debug("  mib.oid('ifTable'): %s", mib.oid("ifTable"))
  debug("  mib.oid('ifEntry'): %s", mib.oid("ifEntry"))
  debug("  sess:walk('ifTable'): %s", pretty(sess:walk("ifTable"))) 
if true then
  debug("  sess:get('ifSpped.1'): %s", tostring(sess:get("ifSpeed.1")))
  debug("  sess:get('ifSpeed'): %s", tostring(sess:get("ifSpeed")))
  debug("  sess.ifSpeed: %s", tostring2(sess.ifSpeed))
  debug("  sess.ifSpeed_1: %s", tostring2(sess.ifSpeed_1))
  debug("  succ(ifSpeed): %s", tostring(mib.successor("ifSpeed")))  
  debug("  oid(ifSpeed): %s", tostring(mib.oid("ifSpeed")))  
  debug("  oid(ifSpeed.1): %s", tostring(mib.oid("ifSpeed.1")))  
  debug("  sess.ipAdEntAddr: %s", tostring2(sess.ipAdEntAddr))
  local tcpConnState = sess.tcpConnState
  debug("  sess.tcpConnState: %s", tostring2(tcpConnState))
  local tcpConnStateKeys = snmp.getkeys(tcpConnState)
  for _,v in ipairs(tcpConnStateKeys) do
    debug("  %s = %s", v, tcpConnState[v])
  end
  for k,v in snmp.spairs(tcpConnState) do
    debug("  %s = %s", k, v)
  end
  local iftab = sess.ifTable
  for k,v in pairs(iftab) do
    debug("  unsorted %s = %s", k, tostring(v))
  end
  for k,v in spairs(iftab) do
    debug("  sorted %s = %s", k, tostring(v))
  end
end
  info("MISCELLANOUS o.k.")
end

----------------------------------------------------------------------
local function test_newpassword(sess)
  info("PASSWORD CHNAGE SNMP V3...")
  local user = "ronja"
  local oldpw = "ronja2006"
  local newpw = "mydog2006"

  local sessold, err = snmp.open{
    peer = "localhost",
    version = snmp.SNMPv3,
    user = user,
    password = oldpw
  }
  assert(sessold, err)
  local vb, err = sess:get("sysContact.0")
  assert(vb, err)
  debug ("  %s", tostring(vb))
  local ref = vb.value

  debug("  Changing password from own session (implicit user)")
  local vl, err = sessold:newpassword(oldpw, newpw, "a")
  assert(vl, err)
  for _,v in ipairs(vl) do 
    debug("  %s", tostring(v)) 
  end

  local sessnew, err = sessold:clone{password = newpw}
  vb, err = sessnew:get("sysContact.0")
  assert(vb, err)
  assert(vb.value == ref)

  debug("  Changing password back from foreign session (explicit user)")
  vl, err = sess:newpassword(newpw, oldpw, "a", user)
  assert(vl, err)
  for _,v in ipairs(vl) do
    debug("  %s", tostring(v)) 
  end

  debug("  Reopen a session with old password")
  sessold2, err = sessold:clone()
  assert(sessold2, err)

  vb, err = sessold2:get("sysContact.0")
  assert(vb,err)
  debug ("  %s", tostring(vb))
  assert(vb.value == ref)

  debug("  Closing intermediate sessions")
  local rv, err = sessold:close()
  assert(rv, err)

  rv, err = sessnew:close()
  assert(rv, err)
  info("PASSWORD CHNAGE SNMP V3.o.k.")
end

----------------------------------------------------------------------
local function test_createuser(sess)
  info("CREATE SNMP V3.USER (no cloning) ...")
  local check = snmp.check

  local user = "popey"
  local newpw = "gonzosfriend"
  local clonefromuser = "ronja"
  local clonefromuserpw = "ronja2006"
  
  debug("  Creating user %q", user)
  local vb, err = check(sess:createuser(user))
  local oid = "usmUserStatus"..snmp.mkindex(sess.contextEngineID, user)
  local vb ,err = check(sess:get("usmUserStatus"..snmp.mkindex(sess.contextEngineID, user)))
  debug("  %s", tostring(vb))
  assert(vb.value == snmp.rowStatus.notReady)
  debug("  Deleting user %q", user)
  local vb, err = check(sess:deleteuser(user))
  debug("  %s", tostring(vb))
  info("CREATE SNMP V3.USER (no cloning) o.k.")
end

----------------------------------------------------------------------
local function test_createcloneuser(sess)
  info("CREATE SNMP V3.USER (cloning) ...")
  local check = snmp.check

  local user = "popey"
  local newpw = "gonzosfriend"
  local clonefromuser = "ronja"
  local clonefromuserpw = "ronja2006"
  
  debug("  Creating user %q as clone from %q", user, clonefromuser)
  local vb, err = check(sess:createuser(user,clonefromuser))
  local oid = "usmUserStatus"..snmp.mkindex(sess.contextEngineID, user)
  local vb ,err = check(sess:get("usmUserStatus"..snmp.mkindex(sess.contextEngineID, user)))
  debug("  %s", tostring(vb))
  assert(vb.value == snmp.rowStatus.active)
  debug("  Deleting user %q", user)
  local vb, err = check(sess:deleteuser(user))
  debug("  %s", tostring(vb))
  info("CREATE SNMP V3.USER (cloning) o.k.")
end

----------------------------------------------------------------------
local function test_cloneuser(sess)
  info("CREATE AND CLONE SNMP V3.USER ...")
  local check = snmp.check

  local user = "popey"
  local newpw = "gonzosfriend"
  local clonefromuser = "ronja"
  local clonefromuserpw = "ronja2006"
  
  debug("  Creating user %q", user)
  local vb, err = check(sess:createuser(user))
  local vb ,err = check(sess:get("usmUserStatus"..snmp.mkindex(sess.contextEngineID, user)))
  debug("  %s", tostring(vb))
  assert(vb.value == snmp.rowStatus.notReady)
  debug("  Make %q a clone of %q", user, clonefromuser)
  local vb, err = check(sess:clonefromuser(user, clonefromuser))
  debug("  %s", tostring(vb))
  local vb ,err = check(sess:get("usmUserStatus"..snmp.mkindex(sess.contextEngineID, user)))
  debug("  %s", tostring(vb))
  assert(vb.value == snmp.rowStatus.active)
  debug("  Deleting user %q", user)
  local vb, err = check(sess:deleteuser(user))
  debug("  %s", tostring(vb))
  info("CREATE AND CLONE SNMP V3.USER o.k.")
end

local mindent = 0
local function sprintvl(vl, indent) 
  local s = ""
  mindent = indent or mindent
  table.foreach(vl, function(i,vb)
		      s = s ..string.format("%s%s\n", string.rep(" ",mindent), tostring(vb))
		    end)
  return s
end

----------------------------------------------------------------------
local function test_vacm(sess)
  info("VIEW BASED ACCESS")

  local check = snmp.check

  -- Create a user
  local vl = check(sess:createuser("olivia", "ronja"))
  
  vl = check(sess:newpassword("ronja2006", "gonzo2006", "a", "olivia"))
  debug("  %s", sprintvl(vl, 2))

  debug("  Create sectogroup")
  vl, err = sess:createsectogroup("usm", "olivia", "rwgroup")
  if err then
    debug("  %s", err)
    vl = check(sess:deleteuser("olivia"))
    sess:close()
    os.exit(1)
  else
    debug("  %s", sprintvl(vl))
  end

  debug("  Create view")
  vl = check(sess:createview("interfaces", mib.oid("ifTable"), "80", "include"))
  debug("  %s", sprintvl(vl))

  debug("  Create access")
  vl = check(sess:createaccess("rwgroup", "usm", "authNoPriv", "exact", 
			       "interfaces", "interfaces", "_none_"))
  debug("  %s", sprintvl(vl))

  debug("  Cleanup - Delete access")
  local vb = check(sess:deleteaccess("rwgroup", "usm", "authNoPriv"))
  debug("  %s", tostring(vb))

  debug("  Cleanup - Delete view")
  vb = check(sess:deleteview("interfaces", mib.oid("ifTable")))
  debug("  %s", tostring(vb))

  debug("  Cleanup - Delete sectogroup")
  vb = check(sess:deletesectogroup("usm", "olivia"))
  debug("  %s", tostring(vb))

  debug("  Cleanup - Delete user")
  vb = check(sess:deleteuser("olivia"))
  info("VIEW BASED ACCESS o.k.")
end

----------------------------------------------------------------------
-- Execute all the tests
----------------------------------------------------------------------

test_mib()
test_counter64()

if mibonly then return end

local sessions = {}

if testv1 == true then
  table.insert(sessions, {func = test_sessv1})
end

if testv2 == true then
  table.insert(sessions, {func = test_sessv2})
end

if testv3 == true then
  table.insert(sessions, {func = test_sessv3, encrypt = encrypt})
end

for _,param in ipairs(sessions) do
   testpath = ""
   sess = param.func(param.encrypt)
   testpath = sess:getversion().." "
   if traponly == false then
      if informonly == false then
	 test_get(sess)
	 test_set(sess)
	 test_meta(sess)
	 if sess.version ~= snmp.SNMPv1 then
	    test_mib_retrieve(sess)
	 end
	 test_perf(sess,10,"sysContact.0")
      end
      if trapyes == true and sess.version ~= snmp.SNMPv1 then
	 test_inform2(sess, 162)
	 test_inform3(sess, 162)
      end
   end
   if trapyes == true and informonly == false then
      test_trap(sess)
   end
   if traponly == false and informonly == false then
      test_walk(sess, {oid="ifType"})
      test_walk(sess, mib.oid("ifType"))
      test_walk(sess, {oid=mib.oid("ifType")})
      test_walk(sess)
      test_walk(sess, "1")
      test_vbindtostring(sess)
      test_vbindequal(sess)
      test_vbindconcat(sess)
      test_vbindcreate(sess)
      test_misc(sess)
      if sess.version == snmp.SNMPv3 then
	 test_newpassword(sess)
	 test_createuser(sess)
	 test_createcloneuser(sess)
	 test_cloneuser(sess)
	 test_vacm(sess)
      end
   end
   sess:close()
end