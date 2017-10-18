return function(port)
    if port == nil then 
        port = 69 --default
    end

    local _tblk=0 --block counter
    local _lock=nil --lock for operations
    local _fn={} --filename store between packets

    local _tmrid = 6
    local _tmrtimeout = 5000

    local function reset()
        _tblk=0
        _lock = nil
        _fn = {}
        tmr.stop(_tmrid)
    end

    local function readsend(s,port,ip)
        _tblk=_tblk+1
        local msb = _tblk/256 --assumes int firmware
        local lsb = _tblk - msb*256
        local b=string.char(msb, lsb)

        if(file.open(_fn,"r")==nil) then
            s:send(port,ip,"\0\5\0\1\0") --Error: 1=file not found
            reset()
            return
        end
        local r = ""
        if(file.seek(set, (_tblk-1)*512)~=nil) then
            r = file.read(512)
        end
        file.close()
        if(r == nil) then
            r = ""
        end
        s:send(port,ip,"\0\3"..b..r)
        uart.write(0,"#")
        if(r:len() ~= 512) then
            print("done!")
            reset()
        end
    end
    
    local function timeoutCB()
        print("Connection timed out")
        if(_lock == 2) then
            file.remove(_fn) --remove incomplete file
        end
        reset()
    end

    local function alarmstop()
        tmr.stop(_tmrid)
    end
    local function alarmstart()
        tmr.alarm(_tmrid, _tmrtimeout, 0, timeoutCB)
    end
    local function alarmclear()
        alarmstop()
        alarmstart()
    end

    local s=net.createUDPSocket()
    s:on("receive", function(s,r,port,ip) 
        print("r",r,"port ",port," ip ",ip)
        local op=r:byte(2)
        print("port ",port," ip ",ip)
        if(op==1) then
            --RRQ
            if(_lock) then
                return
            end
            _fn=string.match(r,"..(%Z+)")
            uart.write(0,"TFTP RRQ '".._fn.."': ")
            if(file.open(_fn, "r")==nil) then
                s:send(port,ip,"\0\5\0\1\0") --Error: 1=file not found
                reset()
                return
            end
            file.close()
            _lock=op
            alarmstart()
            readsend(s,port,ip)
            collectgarbage()
        elseif(op==2) then
            --WRQ
            if(_lock) then
                return
            end
            _fn=string.match(r,"..(%Z+)")
            uart.write(0,"TFTP WRQ '".._fn.."': ")
            _tblk=1
            _lock=op
            alarmstart()
            s:send(port,ip,"\0\4\0\0")
        elseif(op==3) then
            --DATA received for a WRQ
            if(_lock~=2) then
                return
            end
            local b=r:byte(3)*256+r:byte(4)
            local sz=r:len()-4
            if(b~=_tblk) then
                return
            end
            alarmclear()
            s:send(port,ip,"\0\4"..r:sub(3,4))
            _tblk=b+1
            if(file.open(_fn,"a")==nil) then
                s:send(port,ip,"\0\5\0\1\0") --Error: 1=file not found
                reset()
                return
            end
            if(file.write(r:sub(5))==nil) then
                s:send(port,ip,"\0\5\0\3\0") --Error: no space left
                reset()
                return
            end
            file.close()
            uart.write(0,"#")
            if(sz~=512) then
                print(" done!")
                reset()
            end
            collectgarbage()
        elseif(op==4) then
            --ACK received for a RRQ
            if(_lock~=1) then
                return
            end
            local b=r:byte(3)*256+r:byte(4)
            if(b~=_tblk) then
                return
            end
            alarmclear()
            readsend(s,port,ip)
            collectgarbage()
        else
            --ERROR: 4=illegal op
            s:send(port,ip,"\0\5\0\4\0")
        end
    end) 
    s:listen(port)
    print("TFTP server running on port "..tostring(port))
    return s
end
