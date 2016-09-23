require 'pl'
require 'cunn'
local iproc = require 'iproc'
local gm = {}
gm.Image = require 'graphicsmagick.Image'
local data_augmentation = {}

local function pcacov(x)
   local mean = torch.mean(x, 1)
   local xm = x - torch.ger(torch.ones(x:size(1)), mean:squeeze())
   local c = torch.mm(xm:t(), xm)
   c:div(x:size(1) - 1)
   local ce, cv = torch.symeig(c, 'V')
   return ce, cv
end
function data_augmentation.color_noise(src, p, factor)
   factor = factor or 0.1
   if torch.uniform() < p then
      local src, conversion = iproc.byte2float(src)
      local src_t = src:reshape(src:size(1), src:nElement() / src:size(1)):t():contiguous()
      local ce, cv = pcacov(src_t)
      local color_scale = torch.Tensor(3):uniform(1 / (1 + factor), 1 + factor)
      
      pca_space = torch.mm(src_t, cv):t():contiguous()
      for i = 1, 3 do
	 pca_space[i]:mul(color_scale[i])
      end
      local dest = torch.mm(pca_space:t(), cv:t()):t():contiguous():resizeAs(src)
      dest:clamp(0.0, 1.0)

      if conversion then
	 dest = iproc.float2byte(dest)
      end
      return dest
   else
      return src
   end
end
function data_augmentation.overlay(src, p)
   if torch.uniform() < p then
      local r = torch.uniform()
      local src, conversion = iproc.byte2float(src)
      src = src:contiguous()
      local flip = data_augmentation.flip(src)
      flip:mul(r):add(src * (1.0 - r))
      if conversion then
	 flip = iproc.float2byte(flip)
      end
      return flip
   else
      return src
   end
end
function data_augmentation.unsharp_mask(src, p)
   if torch.uniform() < p then
      local radius = 0 -- auto
      local sigma = torch.uniform(0.5, 1.5)
      local amount = torch.uniform(0.1, 0.9)
      local threshold = torch.uniform(0.0, 0.05)
      local unsharp = gm.Image(src, "RGB", "DHW"):
	 unsharpMask(radius, sigma, amount, threshold):
	 toTensor("float", "RGB", "DHW")
      
      if src:type() == "torch.ByteTensor" then
	 return iproc.float2byte(unsharp)
      else
	 return unsharp
      end
   else
      return src
   end
end
function data_augmentation.blur(src, p, size, sigma_min, sigma_max)
   size = size or "3"
   filters = utils.split(size, ",")
   for i = 1, #filters do
      local s = tonumber(filters[i])
      filters[i] = s
   end
   if torch.uniform() < p then
      local src, conversion = iproc.byte2float(src)
      local kernel_size = filters[torch.random(1, #filters)]
      local sigma
      if sigma_min == sigma_max then
	 sigma = sigma_min
      else
	 sigma = torch.uniform(sigma_min, sigma_max)
      end
      local kernel = iproc.gaussian2d(kernel_size, sigma)
      local dest = iproc.convolve(src, kernel, 'same')
      if conversion then
	 dest = iproc.float2byte(dest)
      end
      return dest
   else
      return src
   end
end
function data_augmentation.shift_1px(src)
   -- reducing the even/odd issue in nearest neighbor scaler.
   local direction = torch.random(1, 4)
   local x_shift = 0
   local y_shift = 0
   if direction == 1 then
      x_shift = 1
      y_shift = 0
   elseif direction == 2 then
      x_shift = 0
      y_shift = 1
   elseif direction == 3 then
      x_shift = 1
      y_shift = 1
   elseif flip == 4 then
      x_shift = 0
      y_shift = 0
   end
   local w = src:size(3) - x_shift
   local h = src:size(2) - y_shift
   w = w - (w % 4)
   h = h - (h % 4)
   local dest = iproc.crop(src, x_shift, y_shift, x_shift + w, y_shift + h)
   return dest
end
function data_augmentation.flip(src)
   local flip = torch.random(1, 4)
   local tr = torch.random(1, 2)
   local src, conversion = iproc.byte2float(src)
   local dest
   src = src:contiguous()
   if tr == 1 then
      -- pass
   elseif tr == 2 then
      src = src:transpose(2, 3):contiguous()
   end
   if flip == 1 then
      dest = iproc.hflip(src)
   elseif flip == 2 then
      dest = iproc.vflip(src)
   elseif flip == 3 then
      dest = iproc.hflip(iproc.vflip(src))
   elseif flip == 4 then
      dest = src
   end
   if conversion then
      dest = iproc.float2byte(dest)
   end
   return dest
end

local function test_blur()
   torch.setdefaulttensortype("torch.FloatTensor")
   local image =require 'image'
   local src = image.lena()

   image.display({image = src, min=0, max=1})
   local dest = data_augmentation.blur(src, 1.0, "3,5", 0.5, 0.6)
   image.display({image = dest, min=0, max=1})
   dest = data_augmentation.blur(src, 1.0, "3", 1.0, 1.0)
   image.display({image = dest, min=0, max=1})
   dest = data_augmentation.blur(src, 1.0, "5", 0.75, 0.75)
   image.display({image = dest, min=0, max=1})
end
--test_blur()

return data_augmentation
