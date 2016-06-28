local VERSION = '0.02'
	
local http = require "resty.http"
local ngx = require "ngx"
local magick = require "magick"

local _gravity = {
	nw = "NorthWestGravity",
	ne = "NorthEastGravity",
	sw = "SouthWestGravity",
	se = "SouthEastGravity",
	ct = "CenterGravity"
}

local hc = http.new()

function get_tfsname(h00_name)
	local res = ngx.location.capture("/get?key=" .. h00_name)
	local tfs_key = nil
	if (res.body == "$-1\r\n") then
		tfs_key = nil
	else
		local sep_idx = string.find(res.body, "\n")
		local real = string.sub(res.body, sep_idx + 1)
		tfs_key = string.gsub(real, "^%s*(.-)%s*$", "%1")
	end
	return tfs_key
end


function file_exists(name)
	local f = io.open(name,"r")
	if f~=nil then io.close(f) return true else return false end
end


local function to_gravity(gravity_str)
	return _gravity[gravity_str]
end

function get_tfs_as_blob(tfsurl, tfsname)
	local ok, code, headers, status, body  = hc:request { url = tfsurl .. tfsname}
   	if code ~= ngx.HTTP_OK then
	   return nil
   	else
   		return body
   end
end

function get_tfs_as_img(tfsurl, tfsname)
	if not (tfsname) then
		return nil, "file can't be nil"
	end
	
	local img, err, code
	local _local = string.match(tfsname, "^%/")
	
	-- read file from tfs
	if not (_local) then 
		local blob = get_tfs_as_blob(tfsurl .. "/", tfsname)
		if not (blob) then
			return nil, "can't get image[" .. tfsname .."] from tfs!"
		end
		img, err, code = magick.load_image_from_blob(blob)
		if not (img) then
			return nil, "ivk method[load_image_from_blob] to load image[" .. tfsname 
				.. "] error, code:" .. code .. " msg:" .. msg 
		end

		-- strip metadata
		img:strip()
		img:set_gravity(to_gravity(ct))

	-- read file from local
	else 
		img = magick.load_image(tfsname)
		if not (img) then
			return nil, "can't get image[" .. tfsname .."] from local!"
		end
	end
	
	return img
end

function get_composite_as_image(url, b_f, c_f, gravity, compositeOp)
	local gv = to_gravity(gravity)
    if not (gv) then
        return nil, "invalid gravity type"
    end
	
	local base_img, change_img, err
	
	base_img, err = get_tfs_as_img(url .. "/", b_f)
	if not (base_img) then
		return nil, err
	end
	
	change_img, err = get_tfs_as_img(url .. "/", c_f)
	if not (base_img) then
		base_img:destroy()
		return nil, err
	end
   	
	local ok, msg, code = base_img:composite_by_gravity(change_img, gv, compositeOp)
	if not (ok) then
		base_img:destroy()
		change_img:destroy()
		return nil, "ivk method[composite_by_gravity] error, code: " .. code .. "msg: " .. msg
	else 
		-- gc
		change_img:destroy()
	end
	
	return base_img
end


function get_tfs_as_file(tfsurl, tfsname, suffix)
	local body  = get_tfs_as_blob(tfsurl, tfsname)
	local tmp_name = nil
	if not (body) then
		return nil
	else
		local suf = suffix
		if (suffix == nil) then
			suf = ""
		end
		tmp_name = os.tmpname() .. suf
		local file, msg = io.open(tmp_name, "w")
		file:write(body)
		file:close()
	end
	return tmp_name
end

--- resize image, remove tmp_name source on succeed
function img_resize(tmp_name, to_name, size_x, size_y)
	local area = size_x .. "x" .. size_y
	local command = "gm convert " .. tmp_name.. " -strip -resize " .. area .. 
		" -background white -gravity center -auto-orient " .. to_name 
	local exec_code = os.execute(command)
	local ret_val = 0
	if (exec_code == 0) then
		os.remove(tmp_name)
	else
		ret_val = 1 
		os.rename(tmp_name, tmp_name .. "_" ..  ngx.var.tfsname)
	end
	return ret_val
end

local self = {
	get_tfsname = get_tfsname,
	file_exists = file_exists,
	get_tfs_as_blob = get_tfs_as_blob,
	get_tfs_as_img = get_tfs_as_img,
	get_composite_as_image = get_composite_as_image,
	get_tfs_as_file = get_tfs_as_file,
	img_resize = img_resize,
	VERSION = VERSION 
}

return setmetatable({}, { __index = self})