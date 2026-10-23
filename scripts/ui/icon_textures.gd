class_name IconTextures
extends RefCounted
## Small procedural icon textures (white, tinted by the user): a targeting
## reticle (bounty beacons), a shield (escort beacons) and a hex nut
## (salvage beacons). Built once.

const SIZE := 64

static var _reticle: ImageTexture
static var _shield: ImageTexture
static var _salvage: ImageTexture


static func reticle() -> ImageTexture:
	if _reticle == null:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var c := Vector2(SIZE, SIZE) * 0.5
		for y in SIZE:
			for x in SIZE:
				var p := Vector2(x + 0.5, y + 0.5) - c
				var r := p.length()
				var a := 0.0
				# Ring with four gaps.
				var ring := 1.0 - clampf(absf(r - 21.0) - 1.2, 0.0, 1.0)
				var ang := fposmod(atan2(p.y, p.x) + PI * 0.25, PI * 0.5) - PI * 0.25
				if absf(ang) < 0.22:
					ring = 0.0
				a = maxf(a, ring)
				# Ticks pointing in.
				var on_axis := minf(absf(p.x), absf(p.y))
				if on_axis < 1.4 and r > 9.0 and r < 30.0 and absf(ang) < 0.3:
					a = maxf(a, 1.0 - clampf(on_axis - 0.6, 0.0, 1.0))
				# Centre dot.
				a = maxf(a, 1.0 - clampf(r - 1.8, 0.0, 1.0))
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_reticle = ImageTexture.create_from_image(img)
	return _reticle


static func shield() -> ImageTexture:
	if _shield == null:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		for y in SIZE:
			for x in SIZE:
				var u := (x + 0.5) / SIZE * 2.0 - 1.0
				var v := (y + 0.5) / SIZE
				var d := _shield_sdf(u, v)
				var edge := 1.0 - clampf(absf(d) * SIZE * 0.5 - 1.2, 0.0, 1.0)
				var fill := 0.28 if d < 0.0 else 0.0
				var a := maxf(edge, fill)
				# Inner chevron.
				var cd := absf(v - (0.62 - absf(u) * 0.45))
				if d < -0.1 and cd < 0.04 and absf(u) < 0.38:
					a = maxf(a, 0.9)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_shield = ImageTexture.create_from_image(img)
	return _shield


static func salvage() -> ImageTexture:
	if _salvage == null:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var c := Vector2(SIZE, SIZE) * 0.5
		for y in SIZE:
			for x in SIZE:
				var p := (Vector2(x + 0.5, y + 0.5) - c).abs()
				# Hexagon (flat top) of apothem 22 px.
				var hex := maxf(p.y, p.x * 0.866 + p.y * 0.5) - 22.0
				var edge := 1.0 - clampf(absf(hex) - 1.4, 0.0, 1.0)
				var fill := 0.25 if hex < 0.0 else 0.0
				var hole := 1.0 - clampf(absf(p.length() - 9.0) - 1.4, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, maxf(maxf(edge, fill), hole)))
		_salvage = ImageTexture.create_from_image(img)
	return _salvage


## Signed distance-ish to a shield outline: straight sides that curve in to
## a point at the bottom, slightly arched top. Negative inside.
static func _shield_sdf(u: float, v: float) -> float:
	var top := 0.1 + 0.05 * u * u
	if v < top:
		return top - v
	var k := clampf((v - 0.42) / 0.52, 0.0, 1.0)
	var half_w := 0.8 * sqrt(maxf(1.0 - k * k, 0.0))
	if v > 0.94:
		return maxf(v - 0.94, absf(u) - half_w)
	return absf(u) - half_w
