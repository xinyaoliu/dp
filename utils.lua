--useful for validating if an object is an instance of a class, 
--even when the class is a super class.
--e.g pattern = "^torch[.]%a*Tensor$"
--typepattern(torch.Tensor(4), pattern) and
--typepattern(torch.DoubleTensor(5), pattern) are both true.
--typepattern(3, pattern)
function typepattern(obj, pattern)
   local class = type(obj)
   if class == 'userdata' then
      class = torch.typename(obj)
   end
   local match = string.match(class, pattern)
   if match == nil then
      match = false
   end
   return match
end

function torch.isTensor(obj)
   return typepattern(obj, "^torch[.]%a*Tensor$")
end

function list_iter (t)
   local i = 0
   local n = table.getn(t)
   return function ()
            i = i + 1
            if i <= n then return t[i] end
          end
end

--http://lua-users.org/wiki/TableUtils
function table.val_to_str ( v )
  if "string" == type( v ) then
    v = string.gsub( v, "\n", "\\n" )
    if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
  else
    return "table" == type( v ) and table.tostring( v ) or
      tostring( v )
  end
end

function table.key_to_str ( k )
  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
    return k
  else
    return "[" .. table.val_to_str( k ) .. "]"
  end
end

function table.tostring( tbl )
  local result, done = {}, {}
  for k, v in ipairs( tbl ) do
    table.insert( result, table.val_to_str( v ) )
    done[ k ] = true
  end
  for k, v in pairs( tbl ) do
    if not done[ k ] then
      table.insert( result,
        table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
    end
  end
  return "{" .. table.concat( result, "," ) .. "}"
end

--http://stackoverflow.com/questions/2705793/how-to-get-number-of-entries-in-a-lua-table
function table.length(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

--http://stackoverflow.com/questions/8722620/comparing-two-index-tables-by-index-value-in-lua
local function recursive_compare(t1,t2)
  -- Use usual comparison first.
  if t1==t2 then return true end
  -- We only support non-default behavior for tables
  if (type(t1)~="table") and (type(t2)~="table") then return false end
  -- They better have the same metatables
  local mt1 = getmetatable(t1)
  local mt2 = getmetatable(t2)
  if( not recursive_compare(mt1,mt2) ) then return false end

  -- Check each key-value pair
  -- We have to do this both ways in case we miss some.
  -- TODO: Could probably be smarter and not check those we've 
  -- already checked though!
  for k1,v1 in pairs(t1) do
    local v2 = t2[k1]
    if( not recursive_compare(v1,v2) ) then return false end
  end
  for k2,v2 in pairs(t2) do
    local v1 = t1[k2]
    if( not recursive_compare(v1,v2) ) then return false end
  end

  return true  
end
table.eq = recursive_compare


--[[ From https://github.com/rosejn/lua-util: ]]--

-- Boolean predicate to determine if a path points to a valid file or directory.
function is_file(path)
    return paths.filep(path) or paths.dirp(path)
end

-- Check that a data directory exists, and create it if not.
function check_and_mkdir(dir)
  if not paths.filep(dir) then
    fs.mkdir(dir)
  end
end


-- Download the file at location url.
function download_file(url)
    local protocol, scpurl, filename = url:match('(.-)://(.*)/(.-)$')
    if protocol == 'scp' then
        os.execute(string.format('%s %s %s', 'scp', scpurl .. '/' .. filename, filename))
    else
        os.execute('wget ' .. url)
    end
end


-- Temporarily changes the current working directory to call fn, 
-- returning its result.
function do_with_cwd(path, fn)
    local cur_dir = fs.cwd()
    fs.chdir(path)
    local res = fn()
    fs.chdir(cur_dir)
    return res
end


-- Check that a file exists at path, and if not downloads it from url.
function check_and_download_file(path, url)
  if not paths.filep(path) then
      do_with_cwd(paths.dirname(path), function() download_file(url) end)
  end

  return path
end

-- Decompress a .tgz or .tar.gz file.
function dp.decompress_tarball(path)
   os.execute('tar -xvzf ' .. path)
end

-- unzip a .zip file
function dp.unzip(path)
   os.execute('unzip ' .. path)
end

-- gunzip a .gz file
function dp.gunzip(path)
   os.execute('gunzip ' .. path)
end


function dp.decompress_file(path)
    if string.find(path, ".zip") then
        dp.unzip(path)
    elseif string.find(path, ".tar.gz") or string.find(path, ".tgz") then
        dp.decompress_tarball(path)
    elseif string.find(path, ".gz") or string.find(path, ".gzip") then
        dp.gunzip(path)
    else
        print("Don't know how to decompress file: ", path)
    end
end

--[[ End From ]]--

-- From http://stackoverflow.com/questions/1283388/lua-merge-tables
-- values in table 1 have precedence
function merge(t1, t2)
    for k, v in pairs(t2) do
        if (type(v) == "table") and (type(t1[k] or false) == "table") 
         and (not torch.typename(v)) and (not torch.typename(t1[k])) then
            merge(t1[k], t2[k])
        else
            t1[k] = v
        end
    end
    return t1
end
table.merge = merge

function constrain_norms(max_norm, axis, matrix)
   local old_matrix = matrix
   local cuda
   if matrix:type() == 'torch.CudaTensor' then
      matrix = matrix:double()
      cuda = true
   end
   local norms = torch.norm(matrix,2,axis)
   -- clip
   local new_norms = norms:clone()
   new_norms[torch.gt(norms, max_norm)] = max_norm
   local div = torch.cdiv(new_norms, torch.add(norms,1e-7))
   if cuda then
      div = div:cuda()
   end
   old_matrix:cmul(div:expandAs(old_matrix))
end
dp.constrain_norms = constrain_norms

function typeString_to_tensorType(type_string)
   if type_string == 'cuda' then
      return 'torch.CudaTensor'
   elseif type_string == 'float' then
      return 'torch.FloatTensor'
   elseif type_string == 'double' then
      return 'torch.DoubleTensor'
   end
end

function torch.classof(obj)
   return torch.factory(torch.typename(obj))
end

function torch.view(tensor)
   return torch.classof(tensor)(tensor)
end

-- returns an empty (zero-dim) clone of an obj
function torch.emptyClone(obj)
   return torch.classof()
end

-- simple helpers to serialize/deserialize arbitrary objects/tables
function torch.serialize(object, mode)
   mode = mode or 'binary'
   local f = torch.MemoryFile()
   f = f[mode](f)
   f:writeObject(object)
   local s = f:storage():string()
   f:close()
   return s
end

function torch.deserialize(str, mode)
   mode = mode or 'binary'
   local x = torch.CharStorage():string(str)
   local tx = torch.CharTensor(x)
   local xp = torch.CharStorage(x:size(1)+1)
   local txp = torch.CharTensor(xp)
   txp:narrow(1,1,tx:size(1)):copy(tx)
   txp[tx:size(1)+1] = 0
   local f = torch.MemoryFile(xp)
   f = f[mode](f)
   local object = f:readObject()
   f:close()
   return object
end

-- torch.concat([res], tensors, [dim])
function torch.concat(result, tensors, dim)
   if type(result) == 'table' then
      dim = tensors
      tensors = dim
      result = torch.emptyClone(tensors[1])
   end
   dim = dim or 1

   local size
   for i,tensor in ipairs(tensors) do
      if not size then
         size = tensor:size():totable()
      else
         for i,v in ipairs(tensor:size():totable()) do
            if i == dim then
               size[i] = size[i] + v
            else
               assert(size[i] == v, "Cannot concat different sizes")
            end
         end
      end
   end
   
   result:resize(unpack(size))
   local start = 1
   for i, tensor in ipairs(tensors) do
      result:narrow(dim, start, tensor:size(dim)):copy(tensor)
      start = start+tensor:size(dim)
   end
   return result
end

function dp.printG()
   for k,v in pairs(_.omit(_G, 'torch', 'paths', 'nn', 'xlua', '_', 
                           'underscore', 'io', 'utils', '_G', 'nnx', 
                           'optim', '_preloaded_ ', 'math', 'libfs',
                           'cutorch', 'image')) do
      print(k, type(v))
   end
end

function torch.Tensor:dimshuffle(new_axes)
   return swapaxes(self, new_axes)
end

--http://stackoverflow.com/questions/640642/how-do-you-copy-a-lua-table-by-value
function table.copy(t)
   if t == nil then
      return {}
   end
   local u = { }
   for k, v in pairs(t) do u[k] = v end
   return setmetatable(u, getmetatable(t))
end

function dp.distReport(dist, sort_dist)
   local dist = torch.div(dist, dist:sum()+0.000001)
   local report = {
      dist=dist, min=dist:min(), max=dist:max(),   
      mean=dist:mean(), std=dist:std()
   }
   if sort_dist then
      report.dist = dist:sort()
   end
   return report
end

function table.channelValue(tbl, channel, dept)
   dept = dept or 1
   if type(tbl) ~= 'table' or dept > #channel then
      return tbl
   end
   return table.channelValue(tbl[channel[dept]], channel, dept+1)
end

function table.channelValues(tbls, channel)
   local values = {}
   for key, tbl in pairs(tbls) do
      table.insert(values, table.channelValue(tbl, channel))
   end
   return values
end

function table.fromString(str)
   if type(str) == 'table' then
      return str
   end
   return _.map(
      _.split(str:sub(2,-2),','), 
      function(c) return tonumber(c) end
   )
end

function torch.swapaxes(tensor, new_axes)

   -- new_axes : A table that give new axes of tensor, 
   -- example: to swap axes 2 and 3 in 3D tensor of original axes = {1,2,3}, 
   -- then new_axes={1,3,2}
 
   local sorted_axes = table.copy(new_axes)
   table.sort(sorted_axes)
   
   for k, v in ipairs(sorted_axes) do
      assert(k == v, 'Error: new_axes does not contain all the new axis values')
   end       

   -- tracker is used to track if a dim in new_axes has been swapped
   local tracker = torch.zeros(#new_axes)   
   local new_tensor = tensor

   -- set off a chain swapping of a group of intraconnected dimensions
   _chain_swap = function(idx)
      -- if the new_axes[idx] has not been swapped yet
      if tracker[new_axes[idx]] ~= 1 then
         tracker[idx] = 1
         new_tensor = new_tensor:transpose(idx, new_axes[idx])
         return _chain_swap(new_axes[idx])
      else
         return new_tensor
      end    
   end
   
   for idx = 1, #new_axes do
      if idx ~= new_axes[idx] and tracker[idx] ~= 1 then
         new_tensor = _chain_swap(idx)
      end
   end
   
   return new_tensor
end
   
function dp.reverseDist(dist, inplace)
   local reverse = dist
   if not inplace then
      reverse = dist:clone()
   end
   if dist:dim() == 1 then
      -- reverse distribution and make unlikely values more likely
      reverse:add(-reverse:max()):mul(-1):add(dist:min())
      reverse:div(math.max(reverse:sum(),0.000001))
   elseif dist:dim() == 2 then
      -- reverse distribution and make unlikely values more likely
      reverse:add(reverse:max(2):mul(-1):resize(reverse:size(1),1):expandAs(reverse)):mul(-1):add(dist:min(2):resize(reverse:size(1),1):expandAs(reverse))
      reverse:cdiv(reverse:sum(2):add(0.000001):resize(reverse:size(1),1):expandAs(reverse))
   end
   return reverse
end

--http://stackoverflow.com/questions/132397/get-back-the-output-of-os-execute-in-lua
function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

function os.pid()
   return tonumber(_.split(os.capture('cat /proc/self/stat'), ' ')[5])
end

function os.hostname()
   return os.capture('cat /etc/hostname')
end

-- Generates a globally unique identifier.
-- If a namespace is provided it is concatenated with 
-- the time of the call, and the next value from a sequence
-- to get a pseudo-globally-unique name.
-- Otherwise, we concatenate the linux hostname and PID.
local counter = 1
function dp.uniqueID(namespace, separator)
   local separator = separator or ':'
   local namespace = namespace or os.hostname()..separator..os.pid()
   local uid = namespace..separator..os.time()..separator..counter
   counter = counter + 1
   return uid
end
