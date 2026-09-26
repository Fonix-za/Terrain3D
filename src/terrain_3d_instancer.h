// Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.

#ifndef TERRAIN3D_INSTANCER_CLASS_H
#define TERRAIN3D_INSTANCER_CLASS_H

#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/navigation_mesh.hpp>
#include <godot_cpp/classes/navigation_mesh_source_geometry_data3d.hpp>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "constants.h"
#include "terrain_3d_region.h"

class Terrain3D;
class Terrain3DAssets;

class Terrain3DInstancer : public Object {
	GDCLASS(Terrain3DInstancer, Object);
	CLASS_NAME();
	friend Terrain3D;

public: // Constants
	static inline const int CELL_SIZE = 32;

	enum InstancerMode {
		DISABLED,
		//PLACEHOLDER,
		NORMAL,
	};

private:
	Terrain3D *_terrain = nullptr;

	// MM Resources stored in Terrain3DRegion::_instances as
	// Region::_instances{mesh_id:int} -> cell{v2i} -> [ TypedArray<Transform3D>, PackedColorArray, modified:bool ]

	// A pair of MMI and MM RIDs, freed in destructor, stored as
	// _mmi_rids{region_loc} -> mesh{v2i(mesh_id,lod)} -> cell{v2i} -> std::pair<mmi_RID, mm_RID>

	using CellMMIDict = std::unordered_map<Vector2i, std::pair<RID, RID>, Vector2iHash>;
	using MeshMMIDict = std::unordered_map<Vector2i, CellMMIDict, Vector2iHash>;
	std::unordered_map<Vector2i, MeshMMIDict, Vector2iHash> _mmi_rids;

	// Physics bodies are grouped by region, mesh, and cell. Each cell has one
	// StaticBody RID per source StaticBody3D, with a shape for every instance.
	struct CollisionCell {
		std::vector<RID> bodies;
		std::vector<Ref<Shape3D>> shapes; // Keep resources alive while their RIDs are in use.
	};
	using CellCollisionDict = std::unordered_map<Vector2i, CollisionCell, Vector2iHash>;
	using MeshCollisionDict = std::unordered_map<int, CellCollisionDict>;
	std::unordered_map<Vector2i, MeshCollisionDict, Vector2iHash> _collision_rids;
	RID _navigation_parser;

	// MMI Updates tracked in a unique Set of <region_location, mesh_id>
	// <V2I_MAX, -2> means destroy first, then update everything
	// <V2I_MAX, -1> means update everything
	// <reg_loc, -1> means update all meshes in that region
	// <V2I_MAX, N> means update mesh ID N in all regions
	using V2IIntPair = std::unordered_set<std::pair<Vector2i, int>, PairVector2iIntHash>;
	V2IIntPair _queued_updates;

	InstancerMode _mode = NORMAL;
	uint32_t _density_counter = 0;

	uint32_t _get_density_count(const real_t p_density);
	int _get_master_lod(const Ref<Terrain3DMeshAsset> &p_ma);
	void _process_updates();
	void _update_mmi_by_region(const Terrain3DRegion *p_region, const int p_mesh_id);
	void _set_mmi_lod_ranges(RID p_mmi, const Ref<Terrain3DMeshAsset> &p_ma, const int p_lod);
	void _update_vertex_spacing(const real_t p_vertex_spacing);
	void _destroy_mmi_by_mesh(const int p_mesh_id);
	void _destroy_mmi_by_location(const Vector2i &p_region_loc, const int p_mesh_id);
	void _destroy_mmi_by_cell(const Vector2i &p_region_loc, const int p_mesh_id, const Vector2i p_cell, const int p_lod = INT32_MAX);
	void _update_collision_by_cell(const Terrain3DRegion *p_region, const int p_mesh_id, const Vector2i &p_cell,
			const TypedArray<Transform3D> &p_xforms, const Ref<Terrain3DMeshAsset> &p_asset);
	void _destroy_collision_by_cell(const Vector2i &p_region_loc, const int p_mesh_id, const Vector2i &p_cell);
	void _destroy_collision_by_location(const Vector2i &p_region_loc, const int p_mesh_id);
	void _destroy_all_collision();
	void _parse_navigation_geometry(const Ref<NavigationMesh> &p_navigation_mesh,
			const Ref<NavigationMeshSourceGeometryData3D> &p_source_geometry, Node *p_node);
	void _backup_region(const Ref<Terrain3DRegion> &p_region);
	RID _create_multimesh(const int p_mesh_id, const int p_lod, const TypedArray<Transform3D> &p_xforms = TypedArray<Transform3D>(), const PackedColorArray &p_colors = PackedColorArray()) const;
	Vector2i _get_cell(const Vector3 &p_global_position, const int p_region_size) const;
	Array _get_usable_height(const Vector3 &p_global_position, const Vector2 &p_slope_range, const bool p_on_collision, const real_t p_raycast_start) const;

public:
	Terrain3DInstancer() {}
	~Terrain3DInstancer();

	void initialize(Terrain3D *p_terrain);
	void destroy();

	void clear_by_mesh(const int p_mesh_id);
	void clear_by_location(const Vector2i &p_region_loc, const int p_mesh_id);
	void clear_by_region(const Ref<Terrain3DRegion> &p_region, const int p_mesh_id);

	void set_mode(const InstancerMode p_mode);
	InstancerMode get_mode() const { return _mode; }
	bool is_enabled() const { return _mode != DISABLED; }

	void add_instances(const Vector3 &p_global_position, const Dictionary &p_params);
	void remove_instances(const Vector3 &p_global_position, const Dictionary &p_params);
	void add_multimesh(const int p_mesh_id, const Ref<MultiMesh> &p_multimesh, const Transform3D &p_xform = Transform3D(), const bool p_update = true);
	void add_transforms(const int p_mesh_id, const TypedArray<Transform3D> &p_xforms, const PackedColorArray &p_colors = PackedColorArray(), const bool p_update = true);
	void append_location(const Vector2i &p_region_loc, const int p_mesh_id, const TypedArray<Transform3D> &p_xforms,
			const PackedColorArray &p_colors, const bool p_update = true);
	void append_region(const Ref<Terrain3DRegion> &p_region, const int p_mesh_id, const TypedArray<Transform3D> &p_xforms,
			const PackedColorArray &p_colors, const bool p_update = true);
	void update_transforms(const AABB &p_aabb);
	int get_closest_mesh_id(const Vector3 &p_global_position) const;
	void copy_paste_dfr(const Terrain3DRegion *p_src_region, const Rect2i &p_src_rect, const Terrain3DRegion *p_dst_region);

	void swap_ids(const int p_src_id, const int p_dst_id);
	void update_mmis(const int p_mesh_id = -1, const Vector2i &p_region_loc = V2I_MAX, const bool p_rebuild = false);

	void reset_density_counter() { _density_counter = 0; }

protected:
	static void _bind_methods();
};

using InstancerMode = Terrain3DInstancer::InstancerMode;
VARIANT_ENUM_CAST(Terrain3DInstancer::InstancerMode);

// Allows us to instance every X function calls for sparse placement
// Modifies _density_counter, not const!
inline uint32_t Terrain3DInstancer::_get_density_count(const real_t p_density) {
	uint32_t count = 0;
	if (p_density < 1.f && _density_counter++ % uint32_t(1.f / p_density) == 0) {
		count = 1;
	} else if (p_density >= 1.f) {
		count = uint32_t(p_density);
	}
	return count;
}

// Use lod0 to track instance counter and set AABB, but in shadows_only lod0 doesn't exist
inline int Terrain3DInstancer::_get_master_lod(const Ref<Terrain3DMeshAsset> &p_ma) {
	if (p_ma.is_valid() && p_ma->get_cast_shadows() == SHADOWS_ONLY) {
		return p_ma->get_shadow_impostor();
	}
	return 0;
}

#endif // TERRAIN3D_INSTANCER_CLASS_H
