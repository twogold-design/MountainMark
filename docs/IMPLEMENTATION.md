# Mountain Mark — shared implementation contract

Original single-player 3D climbing game, Godot 4.7, GL compatibility. All authored files and runtime data stay under M:/NewGames/MountainMark. No external art required. Chinese UI with locally copied font. Visual: alpine ochre granite, deep teal blue valleys, warm summit light; stylized cinematic 3D.

## Shared coordinates
Wall face z=0, outside toward +z. Player climbs +y, x roughly -5..5. Route height 72m. Camera in front +z. World units metres.

## Environment scripts/world.gd (Node3D)
Owns environment, lighting, cliff meshes, backdrop, holds and camp/summit decor.
- var holds: Array[Dictionary] each {id:int, position:Vector3, rest:bool, checkpoint:bool}; sorted ascending y; first position near (0,1,0.45); last y about 72. Vertical gaps 1.1-1.6, x gaps <=1.6. Checkpoints/rest at y about 1,18,36,54,72. Main path plus optional nearby holds, avoid extreme isolated points. Rest holds visually distinct gold.
- func build_world() -> void (called explicitly once by main; do not auto-build in _ready)
- func set_hold_feedback(reachable_ids: Array, selected_id: int, used_id: int) -> void
- func update_atmosphere(progress: float, delta: float) -> void
- func get_summit_position() -> Vector3
No input, no player dependency. Static wall is decorative, no collisions needed. Don't add a camera. Main adds your script.

## Climber scripts/climber.gd (Node3D)
Owns articulated procedural human avatar meshes, backpack, harness, rope and limb animation.
- signal reached_hold(hold_id: int)
- signal fell
- var stamina: float = 100.0
- var climbing: bool = false
- var moving: bool = false
- var current_hold_id: int = 0
- var checkpoint_position: Vector3 = Vector3(0,1,0.45)
- var checkpoint_hold_id: int = 0
- var summit_mode: bool = false
- var total_moves: int = 0
- func setup(start_hold: Dictionary) -> void
- func climb_to(hold: Dictionary, hand: int = -1) -> bool # main only calls when reachable; return false if moving/stamina insufficient
- func get_reach_origin() -> Vector3 # latest committed hand target, for hold distance
- func get_body_position() -> Vector3 # camera target
- func rest(delta: float) -> void # main calls while on rest hold; recover stamina
- func chalk() -> bool # restores some stamina with internal cooldown
- func recover() -> void # return to checkpoint; false climbing until main enables? Keep climbing true if already true.
- func celebrate() -> void # summit animation
- func set_lean(value:float) -> void # optional A/D body lean visual
Avatar approx 1.65m tall. Hands attach to holds at z=.45, body at z=1.0, head below hand target. Smooth reach/swing, alternating limbs, feet against rock. Move ~0.7 sec. Stamina cost ~4 per move, idle drain <=1/sec, rest checkpoint recovers fast >=18/sec. Every 10m provide possible rest in world. Fallen stamina triggers fell and recover controlled by main. Rope to checkpoint.

## Root scripts/main.gd
Game orchestration, camera, title screen, HUD, picking projected hold circles, keyboard W/Up assistance, audio integration, save and summit sequence. Mouse left/right hands, W next hold, A/D lean, Space chalk, R recover, Esc pause. Need all scripts to parse without warnings-as-errors. Use explicit types when Godot inference from Variant is uncertain.

## Audio scripts/audio.gd (Node)
- func start_ambience() -> void
- func set_altitude(progress:float) -> void
- func play_grip() -> void
- func play_chalk() -> void
- func play_fall() -> void
- func play_checkpoint() -> void
- func play_summit() -> void
- func set_muted(muted:bool) -> void
Synthesize WAV offline into assets/audio (own script/tools allowed) or runtime AudioStreamWAV; ambient wind and sparse musical tones, tactile grip.

Save to res://.runtime/save.json through absolute project path (not user://). Tests and logs qa/. No writes to C drive; start executables with APPDATA/LOCALAPPDATA/TEMP/TMP redirected to project .runtime. No downloads needed.
