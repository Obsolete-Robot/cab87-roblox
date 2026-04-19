local Easing = {}

local function clampAlpha(alpha)
	if type(alpha) ~= "number" or alpha ~= alpha then
		return 0
	end

	return math.clamp(alpha, 0, 1)
end

function Easing.Linear(alpha)
	return clampAlpha(alpha)
end

function Easing.InQuad(alpha)
	alpha = clampAlpha(alpha)
	return alpha * alpha
end

function Easing.OutQuad(alpha)
	alpha = clampAlpha(alpha)
	return 1 - (1 - alpha) * (1 - alpha)
end

function Easing.InOutQuad(alpha)
	alpha = clampAlpha(alpha)
	if alpha < 0.5 then
		return 2 * alpha * alpha
	end

	return 1 - ((-2 * alpha + 2) ^ 2) / 2
end

function Easing.InCubic(alpha)
	alpha = clampAlpha(alpha)
	return alpha * alpha * alpha
end

function Easing.OutCubic(alpha)
	alpha = clampAlpha(alpha)
	return 1 - (1 - alpha) ^ 3
end

function Easing.InOutCubic(alpha)
	alpha = clampAlpha(alpha)
	if alpha < 0.5 then
		return 4 * alpha * alpha * alpha
	end

	return 1 - ((-2 * alpha + 2) ^ 3) / 2
end

function Easing.InQuart(alpha)
	alpha = clampAlpha(alpha)
	return alpha ^ 4
end

function Easing.OutQuart(alpha)
	alpha = clampAlpha(alpha)
	return 1 - (1 - alpha) ^ 4
end

function Easing.InOutQuart(alpha)
	alpha = clampAlpha(alpha)
	if alpha < 0.5 then
		return 8 * alpha ^ 4
	end

	return 1 - ((-2 * alpha + 2) ^ 4) / 2
end

function Easing.InQuint(alpha)
	alpha = clampAlpha(alpha)
	return alpha ^ 5
end

function Easing.OutQuint(alpha)
	alpha = clampAlpha(alpha)
	return 1 - (1 - alpha) ^ 5
end

function Easing.InOutQuint(alpha)
	alpha = clampAlpha(alpha)
	if alpha < 0.5 then
		return 16 * alpha ^ 5
	end

	return 1 - ((-2 * alpha + 2) ^ 5) / 2
end

function Easing.InSine(alpha)
	alpha = clampAlpha(alpha)
	return 1 - math.cos((alpha * math.pi) / 2)
end

function Easing.OutSine(alpha)
	alpha = clampAlpha(alpha)
	return math.sin((alpha * math.pi) / 2)
end

function Easing.InOutSine(alpha)
	alpha = clampAlpha(alpha)
	return -(math.cos(math.pi * alpha) - 1) / 2
end

function Easing.InExpo(alpha)
	alpha = clampAlpha(alpha)
	if alpha == 0 then
		return 0
	end

	return 2 ^ (10 * alpha - 10)
end

function Easing.OutExpo(alpha)
	alpha = clampAlpha(alpha)
	if alpha == 1 then
		return 1
	end

	return 1 - 2 ^ (-10 * alpha)
end

function Easing.InOutExpo(alpha)
	alpha = clampAlpha(alpha)
	if alpha == 0 or alpha == 1 then
		return alpha
	elseif alpha < 0.5 then
		return (2 ^ (20 * alpha - 10)) / 2
	end

	return (2 - 2 ^ (-20 * alpha + 10)) / 2
end

function Easing.InCirc(alpha)
	alpha = clampAlpha(alpha)
	return 1 - math.sqrt(1 - alpha * alpha)
end

function Easing.OutCirc(alpha)
	alpha = clampAlpha(alpha)
	return math.sqrt(1 - (alpha - 1) ^ 2)
end

function Easing.InOutCirc(alpha)
	alpha = clampAlpha(alpha)
	if alpha < 0.5 then
		return (1 - math.sqrt(1 - (2 * alpha) ^ 2)) / 2
	end

	return (math.sqrt(1 - (-2 * alpha + 2) ^ 2) + 1) / 2
end

function Easing.InBack(alpha, overshoot)
	alpha = clampAlpha(alpha)
	overshoot = overshoot or 1.70158
	return (overshoot + 1) * alpha * alpha * alpha - overshoot * alpha * alpha
end

function Easing.OutBack(alpha, overshoot)
	alpha = clampAlpha(alpha)
	overshoot = overshoot or 1.70158
	return 1 + (overshoot + 1) * (alpha - 1) ^ 3 + overshoot * (alpha - 1) ^ 2
end

function Easing.InOutBack(alpha, overshoot)
	alpha = clampAlpha(alpha)
	overshoot = (overshoot or 1.70158) * 1.525
	if alpha < 0.5 then
		return ((2 * alpha) ^ 2 * ((overshoot + 1) * 2 * alpha - overshoot)) / 2
	end

	return (((2 * alpha - 2) ^ 2 * ((overshoot + 1) * (alpha * 2 - 2) + overshoot)) + 2) / 2
end

function Easing.OutBounce(alpha)
	alpha = clampAlpha(alpha)
	local n1 = 7.5625
	local d1 = 2.75

	if alpha < 1 / d1 then
		return n1 * alpha * alpha
	elseif alpha < 2 / d1 then
		alpha -= 1.5 / d1
		return n1 * alpha * alpha + 0.75
	elseif alpha < 2.5 / d1 then
		alpha -= 2.25 / d1
		return n1 * alpha * alpha + 0.9375
	end

	alpha -= 2.625 / d1
	return n1 * alpha * alpha + 0.984375
end

function Easing.InBounce(alpha)
	alpha = clampAlpha(alpha)
	return 1 - Easing.OutBounce(1 - alpha)
end

function Easing.InOutBounce(alpha)
	alpha = clampAlpha(alpha)
	if alpha < 0.5 then
		return (1 - Easing.OutBounce(1 - 2 * alpha)) / 2
	end

	return (1 + Easing.OutBounce(2 * alpha - 1)) / 2
end

function Easing.Get(name)
	if type(name) == "string" and Easing[name] then
		return Easing[name]
	end

	return Easing.Linear
end

function Easing.Apply(name, alpha, ...)
	return Easing.Get(name)(alpha, ...)
end

return Easing
