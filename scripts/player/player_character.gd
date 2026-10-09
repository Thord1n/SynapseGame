class_name PlayerCharacter
extends Node
## Core player attributes. Health is a flat starting stat. Shield is no longer a stat here: it
## is the Block/Parry ability and sets max Guard on PlayerController (see ShieldPerkDefinition).

@export var max_health: int = 100
var current_health: int = max_health
