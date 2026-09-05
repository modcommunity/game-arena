class_name ArenaContent
extends RefCounted

## Every weapon, item, damage type and ruleset the game ships, built in code.
##
## [b]In code rather than as `.tres` files, deliberately, and only for this
## project.[/b] A real game ships resources an artist edits without touching code, and
## every class these build is `@tool`-annotated and inspector-editable for exactly
## that. What a *reference* game wants is the opposite: one file you can read top to
## bottom and see the whole content set, with the reasoning next to the numbers.
##
## The weapon set is the classic four. Not for nostalgia — they are four genuinely
## different answers to "how do I close distance", and a deathmatch with fewer than
## that is a deathmatch with one right answer.

const DAMAGE_BULLET := &"bullet"
const DAMAGE_BLAST := &"blast"
const DAMAGE_FALL := &"fall"
const DAMAGE_WORLD := &"world"

const AMMO_RIFLE := &"rifle_ammo"
const AMMO_SHELL := &"shells"
const AMMO_ROCKET := &"rockets"


# --- Damage types ----------------------------------------------------------

static func bullet() -> DotDamageType:
	var type := DotDamageType.make(DAMAGE_BULLET, "Bullet")
	type.armour_share = 0.5
	type.armour_wear = 1.0
	# Falloff starts well beyond a duel and ends beyond the map's diagonal, so it
	# punishes cross-map plinking without making a mid-range fight feel weak.
	type.falloff_start = 24.0
	type.falloff_end = 60.0
	type.falloff_floor = 0.55
	type.self_scale = 0.0
	return type


static func blast() -> DotDamageType:
	var type := DotDamageType.make(DAMAGE_BLAST, "Explosion")
	type.armour_share = 0.75
	type.armour_wear = 1.5
	# Hit groups off: a rocket at someone's feet must not do head damage because the
	# splash sphere happened to touch a head hitbox first.
	type.uses_hit_groups = false
	# Rocket jumping. Half damage to yourself is the number every game that has this
	# arrived at independently.
	type.self_scale = 0.5
	type.knockback_per_point = 0.35
	return type


static func fall() -> DotDamageType:
	var type := DotDamageType.make(DAMAGE_FALL, "Fall")
	# Armour does not soften a landing, and a fall has no hit group.
	type.armour_share = 0.0
	type.uses_hit_groups = false
	type.self_scale = 1.0
	return type


static func world() -> DotDamageType:
	var type := DotDamageType.make(DAMAGE_WORLD, "The world")
	type.armour_share = 0.0
	type.uses_hit_groups = false
	return type


static func damage_types() -> Array[DotDamageType]:
	return [bullet(), blast(), fall(), world()]


# --- Weapons ---------------------------------------------------------------

## The starting weapon. Always available, never runs out, and always loses a fair
## fight — which is what makes picking something up worth doing.
static func pistol() -> DotWeapon:
	var weapon := DotWeapon.make(&"pistol", 18.0)
	weapon.display_name = "Pistol"
	weapon.slot = 1
	weapon.fire_mode = DotWeapon.Fire.SEMI
	weapon.rpm = 380.0
	weapon.magazine = 0
	weapon.infinite_reserve = true
	weapon.spread_degrees = 0.4
	weapon.spread_moving = 1.6
	weapon.spread_bloom = 0.35
	weapon.spread_bloom_max = 3.0
	weapon.recoil_pitch = 0.5
	weapon.max_range = 120.0
	weapon.deploy_sec = 0.2
	weapon.holster_sec = 0.15
	weapon.damage_type = bullet()
	return weapon


## The all-rounder. Wins at range, loses in a corridor.
static func rifle() -> DotWeapon:
	var weapon := DotWeapon.make(&"rifle", 22.0)
	weapon.display_name = "Rifle"
	weapon.slot = 2
	weapon.fire_mode = DotWeapon.Fire.AUTO
	weapon.rpm = 620.0
	weapon.magazine = 30
	weapon.reserve = 90
	weapon.reserve_max = 180
	weapon.ammo_type = AMMO_RIFLE
	weapon.reload_sec = 2.1
	weapon.spread_degrees = 0.5
	weapon.spread_moving = 2.2
	weapon.spread_airborne = 4.5
	weapon.spread_crouched = 0.55
	weapon.spread_bloom = 0.28
	weapon.spread_bloom_max = 4.5
	weapon.spread_recovery = 9.0
	weapon.recoil_pitch = 0.35
	weapon.recoil_yaw = 0.14
	weapon.max_range = 200.0
	weapon.deploy_sec = 0.3
	weapon.holster_sec = 0.2
	weapon.damage_type = bullet()
	return weapon


## The corridor answer. Nine pellets in a learnable ring, so range is a skill rather
## than a dice roll.
static func shotgun() -> DotWeapon:
	var weapon := DotWeapon.make(&"shotgun", 11.0)
	weapon.display_name = "Shotgun"
	weapon.slot = 3
	weapon.fire_mode = DotWeapon.Fire.SEMI
	weapon.rpm = 75.0
	weapon.pellets = 9
	weapon.fixed_pattern = true
	weapon.spread_degrees = 4.5
	weapon.spread_moving = 0.5
	weapon.magazine = 6
	weapon.reserve = 24
	weapon.reserve_max = 48
	weapon.ammo_type = AMMO_SHELL
	weapon.reload_per_round = true
	weapon.reload_sec = 0.45
	weapon.reload_start_sec = 0.3
	weapon.recoil_pitch = 2.2
	# Well short of the map's diagonal, so a shotgun across the arena does nothing
	# rather than doing a little — which is a clearer rule to play against.
	weapon.max_range = 24.0
	weapon.deploy_sec = 0.35
	weapon.holster_sec = 0.25
	weapon.damage_type = bullet()
	return weapon


## Area denial, mobility, and the reason the raised middle is worth holding.
##
## Direct damage is deliberately low and the splash is deliberately high: a rocket that
## kills on a direct hit is a hitscan weapon with travel time, and the interesting part
## of a rocket launcher is what it does to the floor.
static func rocket_launcher() -> DotWeapon:
	var weapon := DotWeapon.make(&"rocket", 30.0)
	weapon.display_name = "Rocket Launcher"
	weapon.slot = 4
	weapon.fire_mode = DotWeapon.Fire.SEMI
	weapon.delivery = DotWeapon.Delivery.PROJECTILE
	weapon.rpm = 70.0
	weapon.magazine = 4
	weapon.reserve = 12
	weapon.reserve_max = 20
	weapon.ammo_type = AMMO_ROCKET
	weapon.reload_sec = 2.6
	weapon.projectile_speed = 42.0
	weapon.projectile_radius = 0.2
	weapon.projectile_life_sec = 5.0
	weapon.splash_radius = 4.5
	weapon.splash_damage = 85.0
	weapon.splash_hurts_owner = true
	weapon.spread_degrees = 0.0
	weapon.recoil_pitch = 3.0
	weapon.max_range = 220.0
	weapon.deploy_sec = 0.45
	weapon.holster_sec = 0.3
	weapon.damage_type = blast()
	weapon.splash_type = blast()
	return weapon


static func weapons() -> Array[DotWeapon]:
	return [pistol(), rifle(), shotgun(), rocket_launcher()]


## Weapons by id, for a module that has an item id and needs the weapon.
static func weapon_table() -> Dictionary:
	var table := {}
	for weapon in weapons():
		table[weapon.id] = weapon
	return table


# --- Loadout ---------------------------------------------------------------

## The items a loadout can name. One per weapon, plus armour.
##
## Note that the item ids match the weapon ids. That is a convention this game chose,
## not something dot-loadout requires — it is what makes `weapon_table()[item.id]` the
## whole of the mapping, and dot-loadout's `arsenal_slot` hint the whole of the rest.
static func catalogue() -> DotItemCatalogue:
	var items: Array[DotItem] = []

	for weapon in weapons():
		var item := DotItem.make(weapon.id, DotItem.KIND_WEAPON, weapon.id != &"rocket")
		item.display_name = weapon.display_name
		# No slot restriction on the item: the schema's `kinds` decides that a weapon
		# slot takes weapons, and the points budget decides which combination is
		# legal. Locking each weapon to one slot instead would mean four slots, and a
		# player carrying a shotgun could never also carry a rifle.
		item.cost = weapon.slot
		items.append(item)

	var armour := DotItem.make(&"armour", DotItem.KIND_EQUIPMENT, true)
	armour.display_name = "Armour"
	armour.slots = [&"gear"]
	armour.cost = 2
	items.append(armour)

	return DotItemCatalogue.of(items)


## The loadout schema: two weapon slots and a gear slot, on a small points budget.
##
## Points rather than an explicit list of legal combinations, because "a rifle and a
## shotgun, or a rocket launcher and a pistol" is four numbers rather than an
## enumeration that grows as the square of the weapon count.
static func loadout_schema() -> DotLoadoutSchema:
	var primary := DotLoadoutSlot.make(&"primary", true, &"rifle")
	primary.display_name = "Primary"
	primary.kinds = [DotItem.KIND_WEAPON]
	primary.arsenal_slot = 2
	primary.order = 10

	var secondary := DotLoadoutSlot.make(&"secondary", true, &"pistol")
	secondary.display_name = "Sidearm"
	secondary.kinds = [DotItem.KIND_WEAPON]
	secondary.arsenal_slot = 1
	secondary.order = 20

	var gear := DotLoadoutSlot.make(&"gear")
	gear.display_name = "Gear"
	gear.kinds = [DotItem.KIND_EQUIPMENT]
	gear.order = 30

	var schema := DotLoadoutSchema.of(
		&"arena", [primary, secondary, gear], catalogue()
	)
	# Costs are 1/2/3/4 for pistol/rifle/shotgun/rocket. Six buys a rifle and a
	# shotgun, or a rocket launcher and a pistol, and not a rocket launcher and a
	# shotgun -- four numbers instead of an enumeration that grows as the square of
	# the weapon count.
	schema.point_budget = 6
	return schema
