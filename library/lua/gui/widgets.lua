-- Simple widgets for screens

local _ENV = mkmodule('gui.widgets')

local gui = require('gui')
local utils = require('utils')

local dscreen = dfhack.screen

local function show_view(view,vis,act)
    if view then
        view.visible = vis
        view.active = act
    end
end

local function getval(obj)
    if type(obj) == 'function' then
        return obj()
    else
        return obj
    end
end

------------
-- Widget --
------------

Widget = defclass(Widget, gui.View)

Widget.ATTRS {
    frame = DEFAULT_NIL,
    frame_inset = DEFAULT_NIL,
    frame_background = DEFAULT_NIL,
}

function Widget:computeFrame(parent_rect)
    local sw, sh = parent_rect.width, parent_rect.height
    return gui.compute_frame_body(sw, sh, self.frame, self.frame_inset)
end

function Widget:onRenderFrame(dc, rect)
    if self.frame_background then
        dc:fill(rect, self.frame_background)
    end
end

-----------
-- Panel --
-----------

Panel = defclass(Panel, Widget)

Panel.ATTRS {
    on_render = DEFAULT_NIL,
}

function Panel:init(args)
    self:addviews(args.subviews)
end

function Panel:onRenderBody(dc)
    if self.on_render then self.on_render(dc) end
end

-----------
-- Pages --
-----------

Pages = defclass(Pages, Panel)

function Pages:init(args)
    for _,v in ipairs(self.subviews) do
        show_view(v, false, false)
    end
    self:setSelected(args.selected or 1)
end

function Pages:setSelected(idx)
    if type(idx) ~= 'number' then
        local key = idx
        if type(idx) == 'string' then
            key = self.subviews[key]
        end
        idx = utils.linear_index(self.subviews, key)
        if not idx then
            error('Unknown page: '..key)
        end
    end

    show_view(self.subviews[self.selected], false, false)
    self.selected = math.min(math.max(1, idx), #self.subviews)
    show_view(self.subviews[self.selected], true, true)
end

function Pages:getSelected()
    return self.selected, self.subviews[self.selected]
end

----------------
-- Edit field --
----------------

EditField = defclass(EditField, Widget)

EditField.ATTRS{
    text = '',
    text_pen = DEFAULT_NIL,
    on_char = DEFAULT_NIL,
    on_change = DEFAULT_NIL,
    on_submit = DEFAULT_NIL,
}

function EditField:onRenderBody(dc)
    dc:pen(self.text_pen or COLOR_LIGHTCYAN):fill(0,0,dc.width-1,0)

    local cursor = '_'
    if not self.active or gui.blink_visible(300) then
        cursor = ' '
    end
    local txt = self.text .. cursor
    if #txt > dc.width then
        txt = string.char(27)..string.sub(txt, #txt-dc.width+2)
    end
    dc:string(txt)
end

function EditField:onInput(keys)
    if self.on_submit and keys.SELECT then
        self.on_submit(self.text)
        return true
    elseif keys._STRING then
        local old = self.text
        if keys._STRING == 0 then
            self.text = string.sub(old, 1, #old-1)
        else
            local cv = string.char(keys._STRING)
            if not self.on_char or self.on_char(cv, old) then
                self.text = old .. cv
            end
        end
        if self.on_change and self.text ~= old then
            self.on_change(self.text, old)
        end
        return true
    end
end

-----------
-- Label --
-----------

function parse_label_text(obj)
    local text = obj.text or {}
    if type(text) ~= 'table' then
        text = { text }
    end
    local curline = nil
    local out = { }
    local active = nil
    local idtab = nil
    for _,v in ipairs(text) do
        local vv
        if type(v) == 'string' then
            vv = utils.split_string(v, NEWLINE)
        else
            vv = { v }
        end

        for i = 1,#vv do
            local cv = vv[i]
            if i > 1 then
                if not curline then
                    table.insert(out, {})
                end
                curline = nil
            end
            if cv ~= '' then
                if not curline then
                    curline = {}
                    table.insert(out, curline)
                end

                if type(cv) == 'string' then
                    table.insert(curline, { text = cv })
                else
                    table.insert(curline, cv)

                    if cv.on_activate then
                        active = active or {}
                        table.insert(active, cv)
                    end

                    if cv.id then
                        idtab = idtab or {}
                        idtab[cv.id] = cv
                    end
                end
            end
        end
    end
    obj.text_lines = out
    obj.text_active = active
    obj.text_ids = idtab
end

function render_text(obj,dc,x0,y0,pen,dpen)
    local width = 0
    for iline,line in ipairs(obj.text_lines) do
        local x = 0
        if dc then
            dc:seek(x+x0,y0+iline-1)
        end
        for _,token in ipairs(line) do
            token.line = iline
            token.x1 = x

            if token.gap then
                x = x + token.gap
                if dc then
                    dc:advance(token.gap)
                end
            end

            if token.text or token.key then
                local text = getval(token.text) or ''
                local keypen

                if dc then
                    if getval(token.disabled) then
                        dc:pen(getval(token.dpen) or dpen)
                        keypen = COLOR_GREEN
                    else
                        dc:pen(getval(token.pen) or pen)
                        keypen = COLOR_LIGHTGREEN
                    end
                end

                x = x + #text

                if token.key then
                    local keystr = gui.getKeyDisplay(token.key)
                    local sep = token.key_sep or ''

                    if sep == '()' then
                        if dc then
                            dc:string(text)
                            dc:string(' ('):string(keystr,keypen):string(')')
                        end
                        x = x + 3
                    else
                        if dc then
                            dc:string(keystr,keypen):string(sep):string(text)
                        end
                        x = x + #sep
                    end
                else
                    if dc then
                        dc:string(text)
                    end
                end
            end

            token.x2 = x
        end
        width = math.max(width, x)
    end
    obj.text_width = width
end

function check_text_keys(self, keys)
    if self.text_active then
        for _,item in ipairs(self.text_active) do
            if item.key and keys[item.key] and not getval(item.disabled) then
                item.on_activate()
                return true
            end
        end
    end
end

Label = defclass(Label, Widget)

Label.ATTRS{
    text_pen = COLOR_WHITE,
    text_dpen = COLOR_DARKGREY,
    auto_height = true,
}

function Label:init(args)
    self:setText(args.text)
end

function Label:setText(text)
    self.text = text
    parse_label_text(self)

    if self.auto_height then
        self.frame = self.frame or {}
        self.frame.h = self:getTextHeight()
    end
end

function Label:itemById(id)
    if self.text_ids then
        return self.text_ids[id]
    end
end

function Label:getTextHeight()
    return #self.text_lines
end

function Label:getTextWidth()
    render_text(self)
    return self.text_width
end

function Label:onRenderBody(dc)
    render_text(self,dc,0,0,self.text_pen,self.text_dpen)
end

function Label:onInput(keys)
    return check_text_keys(self, keys)
end

----------
-- List --
----------

List = defclass(List, Widget)

STANDARDSCROLL = {
    STANDARDSCROLL_UP = -1,
    STANDARDSCROLL_DOWN = 1,
    STANDARDSCROLL_PAGEUP = '-page',
    STANDARDSCROLL_PAGEDOWN = '+page',
}

List.ATTRS{
    text_pen = COLOR_CYAN,
    cursor_pen = COLOR_LIGHTCYAN,
    cursor_dpen = DEFAULT_NIL,
    inactive_pen = DEFAULT_NIL,
    on_select = DEFAULT_NIL,
    on_submit = DEFAULT_NIL,
    row_height = 1,
    scroll_keys = STANDARDSCROLL,
}

function List:init(info)
    self.page_top = 1
    self.page_size = 1
    self:setChoices(info.choices, info.selected)
end

function List:setChoices(choices, selected)
    self.choices = choices or {}

    for i,v in ipairs(self.choices) do
        if type(v) ~= 'table' then
            v = { text = v }
            self.choices[i] = v
        end
        v.text = v.text or v.caption or v[1]
        parse_label_text(v)
    end

    self:setSelected(selected)
end

function List:setSelected(selected)
    self.selected = selected or self.selected or 1
    self:moveCursor(0, true)
    return self.selected
end

function List:getSelected()
    return self.selected, self.choices[self.selected]
end

function List:getContentWidth()
    local width = 0
    for i,v in ipairs(self.choices) do
        render_text(v)
        local roww = v.text_width
        if v.key then
            roww = roww + 3 + #gui.getKeyDisplay(v.key)
        end
        width = math.max(width, roww)
    end
    return width
end

function List:getContentHeight()
    return #self.choices * self.row_height
end

function List:postComputeFrame(body)
    self.page_size = math.max(1, math.floor(body.height / self.row_height))
    self:moveCursor(0)
end

function List:moveCursor(delta, force_cb)
    local page = math.max(1, self.page_size)
    local cnt = #self.choices
    local off = self.selected+delta-1
    local ds = math.abs(delta)

    if ds > 1 then
        if off >= cnt+ds-1 then
            off = 0
        else
            off = math.min(cnt-1, off)
        end
        if off <= -ds then
            off = cnt-1
        else
            off = math.max(0, off)
        end
    end

    self.selected = 1 + off % cnt
    self.page_top = 1 + page * math.floor((self.selected-1) / page)

    if (force_cb or delta ~= 0) and self.on_select then
        self.on_select(self:getSelected())
    end
end

function List:onRenderBody(dc)
    local choices = self.choices
    local top = self.page_top
    local iend = math.min(#choices, top+self.page_size-1)

    for i = top,iend do
        local obj = choices[i]
        local current = (i == self.selected)
        local cur_pen = self.text_pen
        local cur_dpen = cur_pen

        if current and active then
            cur_pen = self.cursor_pen
            cur_dpen = self.cursor_dpen or self.text_pen
        elseif current then
            cur_pen = self.inactive_pen or self.cursor_pen
            cur_dpen = self.inactive_pen or self.text_pen
        end

        local y = (i - top)*self.row_height
        render_text(obj, dc, 0, y, cur_pen, cur_dpen)

        if obj.key then
            local keystr = gui.getKeyDisplay(obj.key)
            dc:seek(dc.width-2-#keystr,y):pen(self.text_pen)
            dc:string('('):string(keystr,COLOR_LIGHTGREEN):string(')')
        end
    end
end

function List:onInput(keys)
    if self.on_submit and keys.SELECT then
        self.on_submit(self:getSelected())
        return true
    else
        for k,v in pairs(self.scroll_keys) do
            if keys[k] then
                if v == '+page' then
                    v = self.page_size
                elseif v == '-page' then
                    v = -self.page_size
                end

                self:moveCursor(v)
                return true
            end
        end

        for i,v in ipairs(self.choices) do
            if v.key and keys[v.key] then
                self:setSelected(i)
                if self.on_submit then
                    self.on_submit(self:getSelected())
                end
                return true
            end
        end

        local current = self.choices[self.selected]
        if current then
            return check_text_keys(current, keys)
        end
    end
end

return _ENV