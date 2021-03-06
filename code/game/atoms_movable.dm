/atom/movable
	layer = 3
	appearance_flags = TILE_BOUND
	var/last_move = null
	var/anchored = 0
	var/move_speed = 10
	var/l_move_time = 1
	var/throwing = 0
	var/thrower
	var/turf/throw_source = null
	var/throw_speed = 2
	var/throw_range = 7
	var/fly_speed = 0  // Used to get throw speed param exposed in proc, so we could use it in hitby reactions.
	var/moved_recently = 0
	var/mob/pulledby = null

	var/inertia_dir = 0
	var/atom/inertia_last_loc
	var/inertia_moving = 0
	var/inertia_next_move = 0
	var/inertia_move_delay = 5

	var/is_focused = FALSE // By telekinesis.
	var/list/client_mobs_in_contents
	var/freeze_movement = FALSE

/atom/movable/Destroy()
	//If we have opacity, make sure to tell (potentially) affected light sources.
	var/turf/T = loc
	if(opacity && istype(T))
		opacity = 0
		T.recalc_atom_opacity()
		T.reconsider_lights()

	unbuckle_mob()

	if(loc)
		loc.handle_atom_del(src)
	for(var/atom/movable/AM in contents)
		qdel(AM)
	loc = null
	invisibility = 101
	if(pulledby)
		pulledby.stop_pulling()
	return ..()

/atom/movable/Move(atom/newloc, direct = 0)
	if(!loc || !newloc || freeze_movement)
		return FALSE

	var/atom/oldloc = loc

	if(loc != newloc)
		if (!(direct & (direct - 1))) //Cardinal move
			. = ..()
		else //Diagonal move, split it into cardinal moves
			if (direct & 1)
				if (direct & 4)
					if (step(src, NORTH))
						. = step(src, EAST)
					else if (step(src, EAST))
						. = step(src, NORTH)
				else if (direct & 8)
					if (step(src, NORTH))
						. = step(src, WEST)
					else if (step(src, WEST))
						. = step(src, NORTH)
			else if (direct & 2)
				if (direct & 4)
					if (step(src, SOUTH))
						. = step(src, EAST)
					else if (step(src, EAST))
						. = step(src, SOUTH)
				else if (direct & 8)
					if (step(src, SOUTH))
						. = step(src, WEST)
					else if (step(src, WEST))
						. = step(src, SOUTH)

	if(!loc || (loc == oldloc && oldloc != newloc))
		last_move = 0
		return FALSE

	src.move_speed = world.time - src.l_move_time
	src.l_move_time = world.time

	last_move = direct

	if(. && buckled_mob && !handle_buckled_mob_movement(loc,direct)) //movement failed due to buckled mob
		. = 0

	if(.)
		Moved(oldloc, direct)

/atom/movable/proc/Moved(atom/OldLoc, Dir)
	if (!inertia_moving)
		inertia_next_move = world.time + inertia_move_delay
		newtonian_move(Dir)
	if(length(client_mobs_in_contents))
		update_parallax_contents()

	if (orbiters)
		for (var/thing in orbiters)
			var/datum/orbit/O = thing
			O.Check()
	if (orbiting)
		orbiting.Check()
	return 1

/atom/movable/proc/setLoc(T, teleported=0)
	loc = T

/atom/movable/Bump(atom/A, non_native_bump)
	STOP_THROWING(src, A)

	if(A && non_native_bump)
		A.last_bumped = world.time
		A.Bumped(src)

/atom/movable/proc/forceMove(atom/destination)
	if(destination)
		if(pulledby)
			pulledby.stop_pulling()
		var/atom/oldloc = loc
		var/same_loc = (oldloc == destination)
		var/area/old_area = get_area(oldloc)
		var/area/destarea = get_area(destination)

		if(oldloc && !same_loc)
			oldloc.Exited(src, destination)
			if(old_area)
				old_area.Exited(src, destination)

		loc = destination

		if(!same_loc)
			destination.Entered(src, oldloc)
			if(destarea && old_area != destarea)
				destarea.Entered(src, oldloc)

			for(var/atom/movable/AM in destination)
				if(AM == src)
					continue
				AM.Crossed(src)

		Moved(oldloc, 0)
		return TRUE
	return FALSE

/mob/living/forceMove()
	stop_pulling()
	if(buckled)
		buckled.unbuckle_mob()
	. = ..()
	update_canmove()

/mob/dead/observer/forceMove(atom/destination)
	if(destination)
		if(loc)
			loc.Exited(src)
		loc = destination
		loc.Entered(src)
		return 1
	return 0

//called when src is thrown into hit_atom
/atom/movable/proc/throw_impact(atom/hit_atom)
	hit_atom.hitby(src)

	if(isobj(hit_atom))
		var/obj/O = hit_atom
		if(!O.anchored)
			O.Move(get_step(O, dir))

	if(isturf(hit_atom) && hit_atom.density)
		Move(get_step(src, turn(dir, 180)))

/atom/movable/proc/throw_at(atom/target, range, speed, mob/thrower, spin = TRUE, diagonals_first = FALSE, datum/callback/callback, datum/callback/early_callback)
	if (!target || speed <= 0)
		return

	if (pulledby)
		pulledby.stop_pulling()

	//They are moving! Wouldn't it be cool if we calculated their momentum and added it to the throw?
	if (thrower && thrower.last_move && thrower.client && thrower.client.move_delay >= world.time + world.tick_lag*2)
		var/user_momentum = thrower.movement_delay()
		if (!user_momentum) //no movement_delay, this means they move once per byond tick, lets calculate from that instead.
			user_momentum = world.tick_lag

		user_momentum = 1 / user_momentum // convert from ds to the tiles per ds that throw_at uses.

		if (get_dir(thrower, target) & last_move)
			user_momentum = user_momentum //basically a noop, but needed
		else if (get_dir(target, thrower) & last_move)
			user_momentum = -user_momentum //we are moving away from the target, lets slowdown the throw accordingly
		else
			user_momentum = 0


		if (user_momentum)
			//first lets add that momentum to range.
			range *= (user_momentum / speed) + 1
			//then lets add it to speed
			speed += user_momentum
			if (speed <= 0)
				return //no throw speed, the user was moving too fast.

	var/datum/thrownthing/TT = new()
	TT.thrownthing = src
	TT.target = target
	TT.target_turf = get_turf(target)
	TT.init_dir = get_dir(src, target)
	TT.maxrange = range
	TT.speed = speed
	TT.thrower = thrower
	TT.diagonals_first = diagonals_first
	TT.callback = callback
	TT.early_callback = early_callback

	var/dist_x = abs(target.x - src.x)
	var/dist_y = abs(target.y - src.y)
	var/dx = (target.x > src.x) ? EAST : WEST
	var/dy = (target.y > src.y) ? NORTH : SOUTH

	if (dist_x == dist_y)
		TT.pure_diagonal = TRUE

	else if(dist_x <= dist_y)
		var/olddist_x = dist_x
		var/olddx = dx
		dist_x = dist_y
		dist_y = olddist_x
		dx = dy
		dy = olddx
	TT.dist_x = dist_x
	TT.dist_y = dist_y
	TT.dx = dx
	TT.dy = dy
	TT.diagonal_error = dist_x/2 - dist_y
	TT.start_time = world.time

	if(pulledby)
		pulledby.stop_pulling()

	src.thrower = thrower
	throw_source = get_turf(loc)
	fly_speed = speed
	throwing = TRUE
	if(spin)
		SpinAnimation(5, 1)

	SSthrowing.processing[src] = TT
	if (SSthrowing.state == SS_PAUSED && length(SSthrowing.currentrun))
		SSthrowing.currentrun[src] = TT
	TT.tick()

//Called whenever an object moves and by mobs when they attempt to move themselves through space
//And when an object or action applies a force on src, see newtonian_move() below
//Return 0 to have src start/keep drifting in a no-grav area and 1 to stop/not start drifting
//Mobs should return 1 if they should be able to move of their own volition, see client/Move() in mob_movement.dm
//movement_dir == 0 when stopping or any dir when trying to move
/atom/movable/proc/Process_Spacemove(movement_dir = 0)
	if(has_gravity(src))
		return 1

	if(pulledby)
		return 1

	if(throwing)
		return 1

	if(locate(/obj/structure/lattice) in orange(1, get_turf(src))) //Not realistic but makes pushing things in space easier
		return 1

	return 0

/atom/movable/proc/newtonian_move(direction) //Only moves the object if it's under no gravity

	if(!loc || Process_Spacemove(0))
		inertia_dir = 0
		return 0

	inertia_dir = direction
	if(!direction)
		return 1

	inertia_last_loc = loc
	SSspacedrift.processing[src] = src
	return 1

//Overlays
/atom/movable/overlay
	var/atom/master = null
	anchored = 1

/atom/movable/overlay/atom_init()
	. = ..()
	for(var/x in verbs)
		verbs -= x

/atom/movable/overlay/attackby(a, b, params)
	if (src.master)
		return src.master.attackby(a, b)
	return

/atom/movable/overlay/attack_paw(a, b, c)
	if (src.master)
		return src.master.attack_paw(a, b, c)
	return

/atom/movable/overlay/attack_hand(a, b, c)
	if (src.master)
		return src.master.attack_hand(a, b, c)
	return

/atom/movable/proc/handle_rotation()
	return

/atom/movable/proc/handle_buckled_mob_movement(newloc,direct)
	if(!buckled_mob.Move(newloc, direct))
		loc = buckled_mob.loc
		last_move = buckled_mob.last_move
		inertia_dir = last_move
		buckled_mob.inertia_dir = last_move
		return 0
	return 1

/atom/movable/CanPass(atom/movable/mover, turf/target, height=1.5)
	if(buckled_mob == mover)
		return 1
	return ..()
