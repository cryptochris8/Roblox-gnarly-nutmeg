-- UiTheme (client)
-- Shared colours, fonts, and tiny builder helpers so every Gnarly Nutmeg screen
-- looks consistent.

local UiTheme = {}

UiTheme.Header = Enum.Font.GothamBlack
UiTheme.Body = Enum.Font.GothamMedium

UiTheme.Colors = {
	Ink = Color3.fromRGB(28, 30, 38),
	Panel = Color3.fromRGB(255, 255, 255),
	PanelDark = Color3.fromRGB(24, 26, 34),
	Sub = Color3.fromRGB(120, 124, 140),
	Field = Color3.fromRGB(64, 150, 72),
	Red = Color3.fromRGB(225, 70, 70),
	Blue = Color3.fromRGB(70, 110, 225),
	Stamina = Color3.fromRGB(120, 210, 120),
	Charge = Color3.fromRGB(255, 180, 60),
	Track = Color3.fromRGB(60, 64, 78),
}

-- Generic instance builder. Sets every prop, then parents last.
function UiTheme.make(className, props)
	local o = Instance.new(className)
	local parent = nil
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				(o)[k] = v
			end
		end
	end
	if parent then
		o.Parent = parent
	end
	return o
end

function UiTheme.corner(radius, parent)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function UiTheme.stroke(color, thickness, parent)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

return UiTheme
