@tool
extends RefCounted

# Set this to true while developing the add-on. The release package uses false.
const DEBUG_MESSAGES := false

# Every preview is a separate EditorResourceTooltipPlugin module.
# A broken/undesired module can be disabled here without loading its script.
const ENABLE_SCRIPT_DOCUMENTATION := true
const ENABLE_MATERIAL_PREVIEW := true
const ENABLE_MESH_PREVIEW := true
const ENABLE_FONT_PREVIEW := true
const ENABLE_SHADER_PREVIEW := true
const ENABLE_SPRITE_FRAMES_PREVIEW := true
const ENABLE_THEME_PREVIEW := true
const ENABLE_STYLEBOX_PREVIEW := true
const ENABLE_CURVE_PREVIEW := true
const ENABLE_GRADIENT_PREVIEW := true
const ENABLE_ENVIRONMENT_PREVIEW := true
const ENABLE_SKY_PREVIEW := true
