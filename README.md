# Armature Editor (Godot 4)

Armature Editor is a Godot 4 editor addon for directly creating and editing `Skeleton3D` hierarchies inside the 3D viewport. It provides bone authoring, structural editing, spring chain setup, auto-weighting, and integrated undo/redo workflows, all designed to work natively within the Godot editor.

This tool is intended for developers who want to:

- Author skeletons without external DCC tools
- Rapidly prototype rigs directly inside Godot
- Integrate spring bone chains for secondary motion
- Reweight meshes after structural changes

---

## Features

### Core Skeleton Editing

- Create, rename, and delete bones
- Extrude bones interactively in the viewport
- Subdivide bones with proper length redistribution
- Copy and Paste bones with full child subtree rebuild
- Multi-bone selection
- Undo/redo snapshot system
- Easy acces spring bone chain setup
- Autoweighting for meshinstances

---

## Installation

1. Copy the addons folder into your project

2. Open **Project > Project Settings > Plugins**
3. Enable **Armature Editor**

The toolbar will appear when a `Skeleton3D` is selected.

---

## Usage

### Selecting a Skeleton

- Select a `Skeleton3D` node in the scene tree.
- The viewport gizmo activates automatically.

---

### Edit vs Pose Mode

- **Edit Mode** modifies bone rest transforms.
- **Pose Mode** modifies bone pose transforms.

Switch modes using the toolbar.

---

### Creating and Extruding Bones

1. Select a bone.
2. Activate the Extrude tool.
3. Drag in the viewport to define length.
4. Confirm the action.

Extrusion uses the major view plane for consistent directional behavior.

---

### Subdividing Bones

- Select a bone.
- Use the Subdivide command.
- The original bone is split into evenly distributed segments.
- Tip bone positioning is preserved.

---

### Deleting Bones

- Select a bone.
- Use Delete.
- All children are recursively removed.
- Skeleton is rebuilt safely with index remapping.

---

### Renaming Bones

- Right-click a bone.
- Choose Rename.
- The dialog shows the current name beneath the input field.

---

### Multi-Bone Selection

- Use viewport selection or frustum drag.
- Chain building supports multi-selection.

---

### Spring Chain Authoring

To build a spring chain:

1. Select multiple bones in a linear order  
   **OR**
2. Select a single bone (auto-detect chain by traversing parents/children)

Validation rules:
- Start and end bones may overlap with other chains.
- Intermediate bones may not belong to other chains.
- A toaster warning appears if a conflict exists.

Chains are authored directly into `SpringBoneSimulator3D`.

---

### Auto Weighting

1. Select mesh instances and skeleton.
2. Open Auto Weight dialog with Right Click.
3. Configure:
   - Radius multiplier
   - Falloff power
   - Smoothing
4. Confirm.

Weights are computed in world space and respect mesh transforms.

---

## Undo/Redo

All structural changes use snapshot-based undo:

- Extrude
- Subdivide
- Delete
- Weighting

Snapshots fully reconstruct the skeleton to avoid partial corruption.

---

## Requirements

- Godot 4.x
- Designed for 4.5+ (earlier 4.x versions may work)
