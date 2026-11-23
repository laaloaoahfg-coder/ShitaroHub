-- A bounded, local-only session log. No networking, chat, hooks or raw packets.
return function(clock, maxLines)
    maxLines=maxLines or 1200
    local entries, first, count, lost = {},1,0,0
    local started=clock()
    local logger={}
    function logger.add(kind, message)
        local function clean(value, limit)
            local s=tostring(value):gsub("[\r\n\t]"," ")
            if #s>limit then return s:sub(1,limit).."..." end
            return s
        end
        local line=string.format("%7.2fs %s %s",clock()-started,clean(kind,32),clean(message,700))
        if count<maxLines then
            local index=(first+count-1)%maxLines+1
            entries[index]=line;count=count+1
        else
            entries[first]=line;first=first%maxLines+1;lost=lost+1
        end
    end
    function logger.report()
        local out={"SHITAROHUB CHECKERS BOT LOG v1",
            "Локальный журнал действий бота и выбранных событий игры. Ники, UserId, JobId, чат и сырые пакеты намеренно не записываются.",
            "Некоторые игровые имена объектов, координаты доски и технические ошибки могут содержать данные сессии. Перед передачей проверьте содержимое.",
            "dropped_oldest="..tostring(lost)}
        for i=0,count-1 do out[#out+1]=entries[(first+i-1)%maxLines+1] end
        out[#out+1]="END OF LOG"
        return table.concat(out,"\n")
    end
    return logger
end
