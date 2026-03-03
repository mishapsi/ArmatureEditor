# major_view_plane_service.gd
# Computes a stable drag plane aligned to the camera's dominant axis.

@tool
extends RefCounted
class_name ArmatureViewPlaneService


## Returns a plane aligned to the camera's dominant viewing axis passing through origin.
func get_major_view_plane(camera: Camera3D, origin: Vector3) -> Plane:
	var forward := -camera.global_transform.basis.z.normalized()

	var abs_x := absf(forward.x)
	var abs_y := absf(forward.y)
	var abs_z := absf(forward.z)

	if abs_x > abs_y and abs_x > abs_z:
		return Plane(Vector3.RIGHT, origin)

	if abs_y > abs_x and abs_y > abs_z:
		return Plane(Vector3.UP, origin)

	return Plane(Vector3.BACK, origin)
