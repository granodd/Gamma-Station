/mob/living/var/traumatic_shock = 0
/mob/living/carbon/var/shock_stage = 0

// proc to find out in how much pain the mob is at the moment
/mob/living/carbon/proc/updateshock()
	src.traumatic_shock = 			\
	1	* src.getOxyLoss() + 		\
	0.7	* src.getToxLoss() + 		\
	1.5	* src.getFireLoss() + 		\
	1.2	* src.getBruteLoss() + 		\
	1.7	* src.getCloneLoss() + 		\
	2	* src.halloss

	if(reagents.has_reagent("alkysine"))
		src.traumatic_shock -= 10
	if(reagents.has_reagent("inaprovaline"))
		src.traumatic_shock -= 25
	if(reagents.has_reagent("synaptizine"))
		src.traumatic_shock -= 40
	if(reagents.has_reagent("paracetamol"))
		src.traumatic_shock -= 50
	if(reagents.has_reagent("tramadol"))
		src.traumatic_shock -= 80
	if(reagents.has_reagent("oxycodone"))
		src.traumatic_shock -= 200
	if(src.slurring)
		src.traumatic_shock -= 20
	if(src.analgesic)
		src.traumatic_shock = 0

	// broken or ripped off bodyparts will add quite a bit of pain
	if(istype(src,/mob/living/carbon/human))
		var/mob/living/carbon/human/M = src
		for(var/obj/item/organ/external/BP in M.bodyparts)
			if((BP.status & ORGAN_DESTROYED) && !BP.amputated)
				src.traumatic_shock += 60
			else if((BP.status & ORGAN_BROKEN) || BP.open)
				src.traumatic_shock += 30
				if(BP.status & ORGAN_SPLINTED)
					src.traumatic_shock -= 25

	if(src.traumatic_shock < 0)
		src.traumatic_shock = 0

	return src.traumatic_shock

/mob/living/carbon/human/updateshock()
	if (species && species.flags[NO_PAIN])
		return
	..()

/mob/living/carbon/proc/handle_shock()
	updateshock()
